package com.neuraldefend

import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.atomic.AtomicBoolean

/** Opens a fresh stream over the complete media content. Called once per upload attempt. */
public fun interface StreamSupplier {
    @Throws(IOException::class)
    public fun open(): InputStream
}

/**
 * Upload input for [NeuroVerifyClient.detectImage] and [NeuroVerifyClient.detectVideo].
 *
 * Every variant except [singleUseStream] can be replayed, so automatic retries send the same
 * bytes again. Content is streamed in small chunks and never fully loaded into memory
 * (except [bytes], which is already in memory). On Android, use
 * `com.neuraldefend.android.MediaInputs.fromUri` for photo-picker and camera results.
 */
public sealed class MediaInput {
    internal abstract val explicitFilename: String?

    internal class FileMedia(val file: File, override val explicitFilename: String?) : MediaInput()

    internal class BytesMedia(val bytes: ByteArray, override val explicitFilename: String?) : MediaInput()

    internal class SuppliedMedia(
        val supplier: StreamSupplier,
        val length: Long,
        override val explicitFilename: String?,
    ) : MediaInput()

    internal class SingleUseMedia(
        val stream: InputStream,
        val length: Long,
        override val explicitFilename: String?,
    ) : MediaInput()

    public companion object {
        /** Exact maximum image upload size: 10 MiB. */
        public const val IMAGE_MAX_BYTES: Long = 10L * 1024 * 1024

        /** Exact maximum video upload size: 1,500,000,000 bytes. */
        public const val VIDEO_MAX_BYTES: Long = 1_500_000_000L

        private val imageMimeTypes = linkedMapOf(
            "jpg" to "image/jpeg",
            "jpeg" to "image/jpeg",
            "png" to "image/png",
            "bmp" to "image/bmp",
            "tif" to "image/tiff",
            "tiff" to "image/tiff",
            "webp" to "image/webp",
            "heic" to "image/heic",
            "heif" to "image/heif",
        )

        private val videoMimeTypes = linkedMapOf(
            "mp4" to "video/mp4",
            "avi" to "video/vnd.avi",
            "mov" to "video/quicktime",
            "mkv" to "video/matroska",
            "wmv" to "video/x-ms-wmv",
            "flv" to "video/x-flv",
            "webm" to "video/webm",
            "ogg" to "video/ogg",
            "ogv" to "video/ogg",
        )

        /** Documented image extensions, lower case and without the leading dot. */
        @JvmField
        public val IMAGE_EXTENSIONS: Set<String> = java.util.Collections.unmodifiableSet(imageMimeTypes.keys.toSet())

        /** Documented video extensions, lower case and without the leading dot. */
        @JvmField
        public val VIDEO_EXTENSIONS: Set<String> = java.util.Collections.unmodifiableSet(videoMimeTypes.keys.toSet())

        /**
         * Deterministic multipart MIME type for [filename]. Unknown extensions use
         * `application/octet-stream`; the server still inspects the content.
         */
        @JvmStatic
        public fun mimeTypeFor(filename: String): String {
            val extension = extensionOf(filename)
            return imageMimeTypes[extension] ?: videoMimeTypes[extension] ?: "application/octet-stream"
        }

        /**
         * A readable regular file. It is streamed and reopened for each retry. [filename]
         * defaults to the file's name and selects the multipart MIME type.
         */
        @JvmStatic
        @JvmOverloads
        public fun file(file: File, filename: String? = null): MediaInput = FileMedia(file, filename)

        /**
         * In-memory bytes. [filename] is required because it selects the multipart MIME type;
         * include the real extension. The array is not copied; do not modify it during upload.
         */
        @JvmStatic
        public fun bytes(bytes: ByteArray, filename: String): MediaInput = BytesMedia(bytes, filename)

        /**
         * Content that can be read more than once. [supplier] is called once per attempt and
         * must return a new stream over exactly [length] bytes each time. The SDK closes each
         * stream it opens.
         *
         * ```kotlin
         * MediaInput.stream(file.length(), "clip.mp4") { FileInputStream(file) }
         * ```
         */
        @JvmStatic
        public fun stream(length: Long, filename: String, supplier: StreamSupplier): MediaInput =
            SuppliedMedia(supplier, length, filename)

        /**
         * A single-use stream of exactly [length] bytes. Because it cannot be replayed, the
         * client must be configured with `maxRetries = 0`. The SDK closes the stream.
         */
        @JvmStatic
        public fun singleUseStream(stream: InputStream, length: Long, filename: String): MediaInput =
            SingleUseMedia(stream, length, filename)

        internal fun extensionOf(filename: String): String? {
            val dot = filename.lastIndexOf('.')
            if (dot < 0 || dot == filename.length - 1) return null
            return filename.substring(dot + 1).lowercase(java.util.Locale.ROOT)
        }

        internal fun isDocumented(kind: DetectionKind, extension: String?): Boolean =
            extension != null && (if (kind == DetectionKind.IMAGE) imageMimeTypes else videoMimeTypes).containsKey(extension)
    }
}

internal enum class DetectionKind(
    val path: String,
    val maxBytes: Long,
    val limitLabel: String,
    val label: String,
    val envelope: String,
    val messageField: String,
) {
    IMAGE("/detect/image", MediaInput.IMAGE_MAX_BYTES, "10 MiB", "image", "unified_face_authenticity_score", "message"),
    VIDEO("/detect/video", MediaInput.VIDEO_MAX_BYTES, "1.5 GB", "video", "unified_video_authenticity_score", "video_message"),
}

/** Validated media ready for one or more upload attempts. */
internal class PreparedMedia(
    val filename: String,
    val length: Long,
    val replayable: Boolean,
    private val opener: () -> InputStream,
) {
    private val opened = AtomicBoolean(false)

    val contentType: String get() = MediaInput.mimeTypeFor(filename)

    fun open(): InputStream {
        if (opened.getAndSet(true) && !replayable) {
            throw ValidationError(
                ValidationErrorCode.STREAM_NOT_REPLAYABLE,
                "A single-use stream cannot be uploaded more than once.",
            )
        }
        return opener()
    }
}

internal fun prepareMedia(
    input: MediaInput,
    kind: DetectionKind,
    onWarning: (ValidationWarning) -> Unit,
): PreparedMedia {
    val prepared = when (input) {
        is MediaInput.FileMedia -> {
            val file = input.file
            val length = inspectFile(file)
            PreparedMedia(
                filename = requireFilename(input.explicitFilename ?: file.name),
                length = length,
                replayable = true,
            ) { FileInputStream(file) }
        }
        is MediaInput.BytesMedia -> {
            val bytes = input.bytes
            PreparedMedia(requireFilename(input.explicitFilename), bytes.size.toLong(), true) {
                ByteArrayInputStream(bytes)
            }
        }
        is MediaInput.SuppliedMedia -> {
            val supplier = input.supplier
            PreparedMedia(requireFilename(input.explicitFilename), input.length, true) { supplier.open() }
        }
        is MediaInput.SingleUseMedia -> {
            val stream = input.stream
            PreparedMedia(requireFilename(input.explicitFilename), input.length, false) { stream }
        }
    }

    if (prepared.length <= 0) {
        throw ValidationError(ValidationErrorCode.EMPTY_FILE, "The upload is empty.")
    }
    if (prepared.length > kind.maxBytes) {
        throw ValidationError(
            ValidationErrorCode.FILE_TOO_LARGE,
            "The ${kind.label} exceeds the ${kind.limitLabel} limit.",
        )
    }
    val extension = MediaInput.extensionOf(prepared.filename)
    if (!MediaInput.isDocumented(kind, extension)) {
        onWarning(
            ValidationWarning(
                code = "unsupported_extension",
                filename = prepared.filename,
                message = "The .${extension ?: "(none)"} extension is not documented for ${kind.label} " +
                    "uploads; the server will inspect the content.",
            ),
        )
    }
    return prepared
}

private fun inspectFile(file: File): Long {
    if (file.path.isBlank()) {
        throw ValidationError(ValidationErrorCode.FILE_NOT_FOUND, "The file path must not be empty.")
    }
    val isSymlink = try {
        file.absoluteFile.canonicalFile != file.absoluteFile.parentFile?.canonicalFile?.resolve(file.name)
    } catch (_: IOException) {
        false
    }
    if (isSymlink && file.exists()) {
        throw ValidationError(ValidationErrorCode.UNSUPPORTED_INPUT, "The file path must not be a symbolic link.")
    }
    if (!file.exists()) {
        throw ValidationError(ValidationErrorCode.FILE_NOT_FOUND, "The file path does not exist or is not readable.")
    }
    if (!file.isFile) {
        throw ValidationError(ValidationErrorCode.UNSUPPORTED_INPUT, "The file path must reference a regular file.")
    }
    if (!file.canRead()) {
        throw ValidationError(ValidationErrorCode.FILE_NOT_FOUND, "The file path does not exist or is not readable.")
    }
    return file.length()
}

private fun requireFilename(filename: String?): String {
    val trimmed = filename?.trim().orEmpty()
    if (trimmed.isEmpty()) {
        throw ValidationError(
            ValidationErrorCode.FILENAME_REQUIRED,
            "A filename with the real extension is required, for example \"photo.jpg\" or \"clip.mp4\".",
        )
    }
    val separator = maxOf(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
    val basename = if (separator < 0) trimmed else trimmed.substring(separator + 1)
    if (basename.isEmpty()) {
        throw ValidationError(
            ValidationErrorCode.FILENAME_REQUIRED,
            "A filename with the real extension is required, for example \"photo.jpg\" or \"clip.mp4\".",
        )
    }
    return basename
}
