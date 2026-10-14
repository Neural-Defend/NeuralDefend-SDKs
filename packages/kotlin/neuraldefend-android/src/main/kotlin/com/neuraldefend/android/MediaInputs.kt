package com.neuraldefend.android

import android.content.ContentResolver
import android.content.Context
import android.content.res.AssetFileDescriptor
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.neuraldefend.MediaInput
import com.neuraldefend.ValidationError
import com.neuraldefend.ValidationErrorCode
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/**
 * Builds [MediaInput]s from Android content. Results from the photo picker
 * (`ActivityResultContracts.PickVisualMedia`), `GetContent`, `OpenDocument`, and camera
 * `TakePicture`/`CaptureVideo` are all content `Uri`s.
 */
public object MediaInputs {
    /**
     * Streams [uri] through the app's [ContentResolver]. The content is reopened for every
     * upload attempt, so automatic retries work, and it is never loaded into memory.
     *
     * The display name and size are read from the provider. [filename] overrides the display
     * name; when the provider supplies no name or extension, one is derived from the MIME type.
     * Call this off the main thread: providers may perform disk or network I/O.
     *
     * @throws ValidationError with [ValidationErrorCode.FILE_NOT_FOUND] when the Uri cannot be
     *   opened, or [ValidationErrorCode.UNSUPPORTED_INPUT] when its size is unknown.
     */
    @JvmStatic
    @JvmOverloads
    public fun fromUri(context: Context, uri: Uri, filename: String? = null): MediaInput {
        if (uri.scheme == ContentResolver.SCHEME_FILE) {
            val path = uri.path ?: throw notFound(uri)
            return MediaInput.file(File(path), filename)
        }
        val resolver = context.applicationContext?.contentResolver ?: context.contentResolver
        val metadata = query(resolver, uri)
        val length = metadata.size ?: assetLength(resolver, uri)
            ?: throw ValidationError(
                ValidationErrorCode.UNSUPPORTED_INPUT,
                "The size of $uri is unknown; copy it to a file and use MediaInput.file instead.",
            )
        val name = filename ?: withExtension(metadata.displayName ?: uri.lastPathSegment, resolver.getType(uri))
        return MediaInput.stream(length, name.orEmpty()) {
            try {
                resolver.openInputStream(uri) ?: throw notFound(uri)
            } catch (_: FileNotFoundException) {
                throw notFound(uri)
            } catch (_: SecurityException) {
                throw permissionDenied(uri)
            }
        }
    }

    private class Metadata(val displayName: String?, val size: Long?)

    private fun query(resolver: ContentResolver, uri: Uri): Metadata {
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        val name = if (nameIndex >= 0 && !cursor.isNull(nameIndex)) cursor.getString(nameIndex) else null
                        val size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else null
                        return Metadata(name, size?.takeIf { it >= 0 })
                    }
                }
        } catch (_: SecurityException) {
            throw permissionDenied(uri)
        } catch (_: IllegalArgumentException) {
            // Some providers reject the OpenableColumns projection; fall back to the descriptor.
        }
        return Metadata(null, null)
    }

    private fun assetLength(resolver: ContentResolver, uri: Uri): Long? = try {
        resolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
            descriptor.length.takeIf { it != AssetFileDescriptor.UNKNOWN_LENGTH && it >= 0 }
        }
    } catch (_: FileNotFoundException) {
        throw notFound(uri)
    } catch (_: SecurityException) {
        throw permissionDenied(uri)
    } catch (_: IOException) {
        null
    }

    private fun withExtension(name: String?, mimeType: String?): String? {
        val extension = mimeType?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
        val base = name?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
        return when {
            base == null -> extension?.let { "upload.$it" }
            base.substringAfterLast('.', "").isEmpty() && extension != null -> "$base.$extension"
            else -> base
        }
    }

    private fun permissionDenied(uri: Uri) =
        ValidationError(ValidationErrorCode.FILE_NOT_FOUND, "Permission to read $uri was denied.")

    private fun notFound(uri: Uri) =
        ValidationError(ValidationErrorCode.FILE_NOT_FOUND, "The content at $uri does not exist or is not readable.")
}
