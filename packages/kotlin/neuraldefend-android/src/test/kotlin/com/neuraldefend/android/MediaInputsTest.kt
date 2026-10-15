package com.neuraldefend.android

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import androidx.test.core.app.ApplicationProvider
import com.neuraldefend.kotlin.NeuroVerifyClient
import com.neuraldefend.kotlin.ValidationError
import com.neuraldefend.kotlin.ValidationErrorCode
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.io.FileNotFoundException
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

private const val AUTHORITY = "com.neuraldefend.android.test"

private val SUCCESS_BODY = """
    {"unified_face_authenticity_score": {"unique_trx_id": "trx_test", "filename": "photo.jpg",
    "content_type": "image/jpeg", "status": "success", "status_code": 1, "billable": "Y",
    "risk_score": 2.2, "risk_level": "low", "message": "Not likely to be Spoof or AI-generated",
    "ai_threat_signals": []}}
""".trimIndent()

/** Serves files from [root]; the first path segment selects how much metadata the provider reports. */
class TestProvider : ContentProvider() {
    var root: File? = null
    var opens: Int = 0

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        val mode = uri.pathSegments.first()
        val file = fileFor(uri)
        return when (mode) {
            "full" -> row(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), file.name, file.length())
            "noname" -> row(arrayOf(OpenableColumns.SIZE), file.length())
            "nosize" -> row(arrayOf(OpenableColumns.DISPLAY_NAME), file.name)
            "denied" -> throw SecurityException("no grant")
            else -> null
        }
    }

    override fun getType(uri: Uri): String? = when {
        uri.lastPathSegment.orEmpty().endsWith(".mp4") -> "video/mp4"
        else -> "image/jpeg"
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (uri.pathSegments.first() == "revoked" && opens > 0) throw SecurityException("grant revoked")
        val file = fileFor(uri)
        if (!file.isFile) throw FileNotFoundException(uri.toString())
        opens++
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun fileFor(uri: Uri) = File(checkNotNull(root), uri.lastPathSegment.orEmpty())

    private fun row(columns: Array<String>, vararg values: Any?) =
        MatrixCursor(columns).apply { addRow(values) }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}

@RunWith(RobolectricTestRunner::class)
// Robolectric 4.17 runs API 23 and newer; API 21 and 22 are covered by lint NewApi checks.
@Config(sdk = [23, 36])
class MediaInputsTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var provider: TestProvider
    private val uploads = mutableListOf<String>()
    private var responses = ArrayDeque<Int>()
    private lateinit var client: NeuroVerifyClient

    private val image = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte()) +
        ByteArray(4096) { (it % 251).toByte() }

    @Before
    fun setUp() {
        provider = Robolectric.buildContentProvider(TestProvider::class.java).create(AUTHORITY).get()
        provider.root = folder.root
        File(folder.root, "photo.jpg").writeBytes(image)
        File(folder.root, "clip").writeBytes(image)
        val http = OkHttpClient.Builder().addInterceptor(Interceptor { chain -> respond(chain) }).build()
        client = NeuroVerifyClient.builder().apiKey("test-key").okHttpClient(http).build()
    }

    @After
    fun tearDown() {
        client.close()
    }

    private fun respond(chain: Interceptor.Chain): Response {
        val buffer = Buffer()
        checkNotNull(chain.request().body).writeTo(buffer)
        uploads += buffer.readString(Charsets.ISO_8859_1)
        val code = responses.removeFirstOrNull() ?: 200
        return Response.Builder()
            .request(chain.request())
            .protocol(Protocol.HTTP_1_1)
            .code(code)
            .message("status $code")
            .apply { if (code == 429) header("retry-after", "0") }
            .body((if (code == 200) SUCCESS_BODY else """{"detail":"slow down"}""").toResponseBody("application/json".toMediaType()))
            .build()
    }

    private fun uri(mode: String, name: String) = Uri.parse("content://$AUTHORITY/$mode/$name")

    @Test
    fun usesProviderNameAndStreamsTheContent() {
        val result = runBlocking { client.detectImage(MediaInputs.fromUri(context, uri("full", "photo.jpg"))) }

        assertTrue(result.scored)
        assertEquals(1, uploads.size)
        assertTrue(uploads[0].contains("filename=\"photo.jpg\""), uploads[0])
        assertTrue(uploads[0].contains("Content-Type: image/jpeg"), uploads[0])
        assertTrue(uploads[0].contains(String(image, Charsets.ISO_8859_1)))
    }

    @Test
    fun reopensTheUriForEveryRetry() {
        responses = ArrayDeque(listOf(429))

        val result = runBlocking { client.detectImage(MediaInputs.fromUri(context, uri("full", "photo.jpg"))) }

        assertTrue(result.scored)
        assertEquals(2, provider.opens)
        assertEquals(2, uploads.size)
        val content = String(image, Charsets.ISO_8859_1)
        assertTrue(uploads.all { it.contains(content) })
    }

    @Test
    fun explicitFilenameOverridesTheProvider() {
        runBlocking { client.detectImage(MediaInputs.fromUri(context, uri("full", "photo.jpg"), "selfie.jpeg")) }

        assertTrue(uploads[0].contains("filename=\"selfie.jpeg\""), uploads[0])
    }

    @Test
    fun derivesAFilenameFromTheMimeTypeWhenTheProviderHasNone() {
        runBlocking { client.detectImage(MediaInputs.fromUri(context, uri("noname", "clip"))) }

        // Android versions map image/jpeg to either "jpg" or "jpeg"; both are accepted image extensions.
        assertTrue(Regex("filename=\"clip\\.jpe?g\"").containsMatchIn(uploads[0]), uploads[0])
    }

    @Test
    fun fallsBackToTheFileDescriptorForTheSize() {
        val media = MediaInputs.fromUri(context, uri("nosize", "photo.jpg"))

        runBlocking { client.detectImage(media) }

        assertTrue(uploads[0].contains(String(image, Charsets.ISO_8859_1)))
    }

    @Test
    fun missingContentIsFileNotFound() {
        val error = assertFailsWith<ValidationError> { MediaInputs.fromUri(context, uri("other", "missing.jpg")) }

        assertEquals(ValidationErrorCode.FILE_NOT_FOUND, error.code)
    }

    @Test
    fun deniedPermissionIsFileNotFound() {
        val error = assertFailsWith<ValidationError> { MediaInputs.fromUri(context, uri("denied", "photo.jpg")) }

        assertEquals(ValidationErrorCode.FILE_NOT_FOUND, error.code)
    }

    @Test
    fun permissionRevokedBeforeUploadIsFileNotFound() {
        // The size fallback opens the descriptor once, so the upload's open is the revoked one.
        val media = MediaInputs.fromUri(context, uri("revoked", "photo.jpg"))

        val error = assertFailsWith<ValidationError> { runBlocking { client.detectImage(media) } }

        assertEquals(ValidationErrorCode.FILE_NOT_FOUND, error.code)
        assertTrue(uploads.isEmpty())
    }

    @Test
    fun fileUrisUseTheFileInput() {
        val file = File(folder.root, "photo.jpg")

        runBlocking { client.detectImage(MediaInputs.fromUri(context, Uri.fromFile(file))) }

        assertTrue(uploads[0].contains("filename=\"photo.jpg\""), uploads[0])
        assertContentEquals(image, file.readBytes())
    }

    @Test
    fun missingFileUriIsFileNotFound() {
        val media = MediaInputs.fromUri(context, Uri.fromFile(File(folder.root, "absent.jpg")))

        val error = assertFailsWith<ValidationError> { runBlocking { client.detectImage(media) } }

        assertEquals(ValidationErrorCode.FILE_NOT_FOUND, error.code)
    }
}
