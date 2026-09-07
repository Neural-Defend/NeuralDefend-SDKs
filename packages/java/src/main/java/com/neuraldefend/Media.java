package com.neuraldefend;

import java.io.ByteArrayInputStream;
import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.Set;

/** Upload input for {@link NeuroVerifyClient#detectImage} and {@link NeuroVerifyClient#detectVideo}. */
public final class Media {
    public static final long IMAGE_MAX_BYTES = 10L * 1024L * 1024L;
    public static final long VIDEO_MAX_BYTES = 1_500_000_000L;

    private static final Map<String, String> IMAGE_MIME_TYPES =
            Map.ofEntries(
                    Map.entry(".jpg", "image/jpeg"),
                    Map.entry(".jpeg", "image/jpeg"),
                    Map.entry(".png", "image/png"),
                    Map.entry(".bmp", "image/bmp"),
                    Map.entry(".tif", "image/tiff"),
                    Map.entry(".tiff", "image/tiff"),
                    Map.entry(".webp", "image/webp"),
                    Map.entry(".heic", "image/heic"),
                    Map.entry(".heif", "image/heif"));
    private static final Map<String, String> VIDEO_MIME_TYPES =
            Map.ofEntries(
                    Map.entry(".mp4", "video/mp4"),
                    Map.entry(".avi", "video/vnd.avi"),
                    Map.entry(".mov", "video/quicktime"),
                    Map.entry(".mkv", "video/matroska"),
                    Map.entry(".wmv", "video/x-ms-wmv"),
                    Map.entry(".flv", "video/x-flv"),
                    Map.entry(".webm", "video/webm"),
                    Map.entry(".ogg", "video/ogg"),
                    Map.entry(".ogv", "video/ogg"));
    static final Set<String> IMAGE_EXTENSIONS = IMAGE_MIME_TYPES.keySet();
    static final Set<String> VIDEO_EXTENSIONS = VIDEO_MIME_TYPES.keySet();

    private final String filename;
    private final Path path;
    private final byte[] data;
    private final InputStream stream;
    private final long size;

    private Media(String filename, Path path, byte[] data, InputStream stream, long size) {
        this.filename = filename;
        this.path = path;
        this.data = data;
        this.stream = stream;
        this.size = size;
    }

    /** Builds media from a readable regular file path. */
    public static Media fileMedia(Path path) {
        return new Media(null, path, null, null, -1);
    }

    /** Builds media from a readable regular file path string. */
    public static Media fileMedia(String path) {
        return fileMedia(Path.of(path));
    }

    /** Builds media from an in-memory byte array. */
    public static Media bytesMedia(String name, byte[] data) {
        return new Media(name, null, data, null, -1);
    }

    /**
     * Builds media from an input stream. When {@code size} is negative the stream is treated as
     * non-seekable and the client must use {@code maxRetries=0}.
     */
    public static Media inputStreamMedia(String name, InputStream stream, long size) {
        return new Media(name, null, null, stream, size);
    }

    static String mimeForFilename(String filename) {
        String ext = extension(filename);
        String mime = IMAGE_MIME_TYPES.get(ext);
        if (mime != null) {
            return mime;
        }
        mime = VIDEO_MIME_TYPES.get(ext);
        if (mime != null) {
            return mime;
        }
        return "application/octet-stream";
    }

    PreparedUpload prepare(MediaKind kind, long maxBytes, Set<String> extensions)
            throws ValidationException {
        String selectedName = filename == null ? "" : filename.strip();
        if (path != null) {
            if (!Files.isRegularFile(path)) {
                throw new ValidationException("file path does not exist or is not readable");
            }
            long fileSize;
            try {
                fileSize = Files.size(path);
            } catch (IOException ex) {
                throw new ValidationException("file path does not exist or is not readable");
            }
            if (fileSize == 0) {
                throw new ValidationException("file must not be empty");
            }
            if (fileSize > maxBytes) {
                throw new ValidationException("file exceeds the endpoint size limit");
            }
            if (selectedName.isEmpty()) {
                selectedName = path.getFileName().toString();
            }
            return PreparedUpload.fromPath(selectedName, path, maxBytes, extensions);
        }
        if (data != null) {
            if (data.length == 0) {
                throw new ValidationException("file must not be empty");
            }
            if (data.length > maxBytes) {
                throw new ValidationException("file exceeds the endpoint size limit");
            }
            if (selectedName.isEmpty()) {
                throw new ValidationException("filename is required when uploading bytes");
            }
            return PreparedUpload.fromBytes(selectedName, maxBytes, data, extensions);
        }
        if (stream != null) {
            if (selectedName.isEmpty()) {
                throw new ValidationException("filename is required for a nameless file-like object");
            }
            if (stream.markSupported() && size >= 0) {
                if (size == 0) {
                    throw new ValidationException("file must not be empty");
                }
                if (size > maxBytes) {
                    throw new ValidationException("file exceeds the endpoint size limit");
                }
                try {
                    stream.mark(Integer.MAX_VALUE);
                    stream.reset();
                } catch (IOException ex) {
                    throw new ValidationException("file-like object must support seek() and tell()");
                }
                Closeable closer = stream instanceof Closeable ? (Closeable) stream : null;
                return PreparedUpload.fromStream(
                        selectedName, maxBytes, stream, stream, closer != null, extensions);
            }
            if (size >= 0) {
                if (size == 0) {
                    throw new ValidationException("file must not be empty");
                }
                if (size > maxBytes) {
                    throw new ValidationException("file exceeds the endpoint size limit");
                }
            }
            byte[] prefix = new byte[1];
            int read;
            try {
                read = stream.read(prefix);
            } catch (IOException ex) {
                throw new ValidationException("file-like object is not readable");
            }
            if (read <= 0) {
                throw new ValidationException("file must not be empty");
            }
            Closeable closer = stream instanceof Closeable ? (Closeable) stream : null;
            return PreparedUpload.fromPrefix(
                    selectedName,
                    maxBytes,
                    stream,
                    closer != null,
                    extensions,
                    prefix,
                    read);
        }
        throw new ValidationException("file must be a path, bytes, or binary file-like object");
    }

    private static String extension(String filename) {
        int dot = filename.lastIndexOf('.');
        if (dot < 0) {
            return "";
        }
        return filename.substring(dot).toLowerCase();
    }

    enum MediaKind {
        IMAGE,
        VIDEO
    }

    static final class PreparedUpload implements AutoCloseable {
        final String filename;
        final long maxBytes;
        final byte[] data;
        final Path path;
        final InputStream stream;
        final InputStream seeker;
        final byte[] prefix;
        final boolean ownsStream;
        final boolean unsupported;

        private PreparedUpload(
                String filename,
                long maxBytes,
                byte[] data,
                Path path,
                InputStream stream,
                InputStream seeker,
                byte[] prefix,
                boolean ownsStream,
                Set<String> extensions) {
            this.filename = filename;
            this.maxBytes = maxBytes;
            this.data = data;
            this.path = path;
            this.stream = stream;
            this.seeker = seeker;
            this.prefix = prefix;
            this.ownsStream = ownsStream;
            String ext = Media.extension(filename);
            this.unsupported = !ext.isEmpty() && !extensions.contains(ext);
        }

        static PreparedUpload fromBytes(
                String filename, long maxBytes, byte[] data, Set<String> extensions) {
            return new PreparedUpload(
                    filename, maxBytes, data, null, null, null, null, false, extensions);
        }

        static PreparedUpload fromPath(
                String filename, Path path, long maxBytes, Set<String> extensions) {
            return new PreparedUpload(
                    filename, maxBytes, null, path, null, null, null, false, extensions);
        }

        static PreparedUpload fromStream(
                String filename,
                long maxBytes,
                InputStream stream,
                InputStream seeker,
                boolean ownsStream,
                Set<String> extensions) {
            return new PreparedUpload(
                    filename,
                    maxBytes,
                    null,
                    null,
                    stream,
                    seeker,
                    null,
                    ownsStream,
                    extensions);
        }

        static PreparedUpload fromPrefix(
                String filename,
                long maxBytes,
                InputStream stream,
                boolean ownsStream,
                Set<String> extensions,
                byte[] prefix,
                int prefixLength) {
            byte[] copied = new byte[prefixLength];
            System.arraycopy(prefix, 0, copied, 0, prefixLength);
            return new PreparedUpload(
                    filename,
                    maxBytes,
                    null,
                    null,
                    stream,
                    null,
                    copied,
                    ownsStream,
                    extensions);
        }

        boolean isSeekable() {
            return data != null || path != null || seeker != null;
        }

        InputStream openAttempt() throws ValidationException {
            if (data != null) {
                return new ByteArrayInputStream(data);
            }
            if (path != null) {
                try {
                    return Files.newInputStream(path);
                } catch (IOException ex) {
                    throw new ValidationException("file path does not exist or is not readable");
                }
            }
            if (seeker != null) {
                try {
                    if (seeker.markSupported()) {
                        seeker.reset();
                    }
                } catch (IOException ex) {
                    throw new ValidationException("file-like object could not be rewound for retry");
                }
                return seeker;
            }
            if (stream == null) {
                throw new ValidationException("invalid upload source");
            }
            return new LimitedInputStream(stream, prefix, maxBytes);
        }

        @Override
        public void close() {
            if (ownsStream && stream instanceof Closeable) {
                try {
                    ((Closeable) stream).close();
                } catch (IOException ignored) {
                    // Best effort close.
                }
            }
        }
    }

    private static final class LimitedInputStream extends InputStream {
        private final InputStream source;
        private final byte[] prefix;
        private int prefixOffset;
        private final long limit;
        private long count;

        LimitedInputStream(InputStream source, byte[] prefix, long limit) {
            this.source = source;
            this.prefix = prefix == null ? new byte[0] : prefix;
            this.limit = limit;
        }

        @Override
        public int read() throws IOException {
            byte[] buffer = new byte[1];
            int read = read(buffer, 0, 1);
            return read < 0 ? -1 : buffer[0] & 0xff;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            if (length == 0) {
                return 0;
            }
            int written = 0;
            if (prefixOffset < prefix.length) {
                int copy = Math.min(length, prefix.length - prefixOffset);
                System.arraycopy(prefix, prefixOffset, buffer, offset, copy);
                prefixOffset += copy;
                written += copy;
                count += copy;
                if (written == length) {
                    checkLimit();
                    return written;
                }
                offset += copy;
                length -= copy;
            }
            int read = source.read(buffer, offset, length);
            if (read > 0) {
                written += read;
                count += read;
            }
            checkLimit();
            return written == 0 && read < 0 ? -1 : written;
        }

        private void checkLimit() throws ValidationException {
            if (count > limit) {
                throw new ValidationException("file exceeds the endpoint size limit");
            }
        }
    }
}
