import Foundation

/// Upload input for ``NeuroVerifyClient/detectImage(_:onProgress:)`` and
/// ``NeuroVerifyClient/detectVideo(_:maxFrames:sampleRate:onProgress:)``.
///
/// Every input can be replayed, so automatic retries send the same bytes again. Files are
/// streamed from disk and never loaded fully into memory.
public struct MediaInput: Sendable {
    enum Source: Sendable {
        case file(URL)
        case data(Data)
    }

    let source: Source
    let filename: String?

    /// Keeps a temporary copy (for example from ``init(photosPickerItem:)``) alive for as long
    /// as this input exists, then deletes it.
    let temporaryFile: TemporaryFile?

    init(source: Source, filename: String?, temporaryFile: TemporaryFile? = nil) {
        self.source = source
        self.filename = filename
        self.temporaryFile = temporaryFile
    }

    /// A readable regular file. `filename` defaults to the URL's last path component and
    /// selects the multipart content type, so it must carry the real extension.
    ///
    /// Security-scoped URLs (for example from a document picker) are accessed for the
    /// duration of each upload.
    public static func file(_ url: URL, filename: String? = nil) -> MediaInput {
        MediaInput(source: .file(url), filename: filename)
    }

    /// In-memory bytes. `filename` is required because it selects the multipart content type;
    /// include the real extension, for example `"photo.jpg"`.
    public static func data(_ data: Data, filename: String) -> MediaInput {
        MediaInput(source: .data(data), filename: filename)
    }
}

/// Deletes its file when the last reference goes away.
final class TemporaryFile: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Kind of detection endpoint.
enum DetectionKind: String, Sendable {
    case image
    case video

    var path: String { self == .image ? "/detect/image" : "/detect/video" }

    var maxBytes: Int64 { self == .image ? MediaLimits.imageMaxBytes : MediaLimits.videoMaxBytes }

    var limitLabel: String { self == .image ? "10 MiB" : "1.5 GB" }

    var extensions: Set<String> {
        self == .image ? MediaLimits.imageExtensions : MediaLimits.videoExtensions
    }

    var envelopeKey: String { self == .image ? imageEnvelopeKey : videoEnvelopeKey }
}

/// Documented upload limits, extensions, and content types.
public enum MediaLimits {
    /// Exact maximum image upload size: 10 MiB.
    public static let imageMaxBytes: Int64 = 10 * 1024 * 1024

    /// Exact maximum video upload size: 1,500,000,000 bytes.
    public static let videoMaxBytes: Int64 = 1_500_000_000

    static let imageContentTypes: [String: String] = [
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "bmp": "image/bmp",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "webp": "image/webp",
        "heic": "image/heic",
        "heif": "image/heif",
    ]

    static let videoContentTypes: [String: String] = [
        "mp4": "video/mp4",
        "avi": "video/vnd.avi",
        "mov": "video/quicktime",
        "mkv": "video/matroska",
        "wmv": "video/x-ms-wmv",
        "flv": "video/x-flv",
        "webm": "video/webm",
        "ogg": "video/ogg",
        "ogv": "video/ogg",
    ]

    /// Documented image extensions, lowercase and without the leading dot.
    public static let imageExtensions = Set(imageContentTypes.keys)

    /// Documented video extensions, lowercase and without the leading dot.
    public static let videoExtensions = Set(videoContentTypes.keys)

    /// Deterministic multipart content type for `filename`. Unknown extensions use
    /// `application/octet-stream`; the server still inspects the content.
    public static func contentType(forFilename filename: String) -> String {
        guard let ext = fileExtension(filename) else { return "application/octet-stream" }
        return imageContentTypes[ext] ?? videoContentTypes[ext] ?? "application/octet-stream"
    }

    static func fileExtension(_ filename: String) -> String? {
        guard let dot = filename.lastIndex(of: "."), filename.index(after: dot) != filename.endIndex
        else { return nil }
        return String(filename[filename.index(after: dot)...]).lowercased()
    }
}

/// Validated media ready for one or more upload attempts.
struct PreparedMedia: Sendable {
    let input: MediaInput
    let filename: String
    let length: Int64

    var contentType: String { MediaLimits.contentType(forFilename: filename) }
}

func prepareMedia(
    _ input: MediaInput,
    kind: DetectionKind,
    onWarning: (@Sendable (ValidationWarning) -> Void)?
) throws(NeuroVerifyError) -> PreparedMedia {
    let filename: String
    let length: Int64
    switch input.source {
    case .file(let url):
        guard url.isFileURL else {
            throw .validation(
                code: .unsupportedInput,
                message: "MediaInput.file requires a file URL, not \(url.scheme ?? "a relative") URL."
            )
        }
        filename = try requireFilename(input.filename ?? url.lastPathComponent)
        length = try withSecurityScope(url) { () throws(NeuroVerifyError) in try regularFileSize(url) }
    case .data(let data):
        filename = try requireFilename(input.filename)
        length = Int64(data.count)
    }

    if length <= 0 {
        throw .validation(code: .emptyFile, message: "The upload is empty.")
    }
    if length > kind.maxBytes {
        throw .validation(
            code: .fileTooLarge,
            message: "The \(kind.rawValue) exceeds the \(kind.limitLabel) limit."
        )
    }
    let ext = MediaLimits.fileExtension(filename)
    if ext.map({ !kind.extensions.contains($0) }) ?? true {
        onWarning?(
            ValidationWarning(
                code: "unsupported_extension",
                message: "The .\(ext ?? "(none)") extension is not documented for "
                    + "\(kind.rawValue) uploads; the server will inspect the content.",
                filename: filename
            )
        )
    }
    return PreparedMedia(input: input, filename: filename, length: length)
}

private func requireFilename(_ candidate: String?) throws(NeuroVerifyError) -> String {
    let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let base = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
    guard !base.isEmpty else {
        throw .validation(
            code: .filenameRequired,
            message: "A filename with the real extension is required, for example "
                + "\"photo.jpg\" or \"clip.mp4\"."
        )
    }
    return base
}

private func regularFileSize(_ url: URL) throws(NeuroVerifyError) -> Int64 {
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    } catch {
        throw .validation(code: .fileNotFound, message: "The file does not exist or is not readable.")
    }
    guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
        throw .validation(code: .unsupportedInput, message: "The path is not a regular file.")
    }
    guard let size = (attributes[.size] as? NSNumber)?.int64Value else {
        throw .validation(code: .unsupportedInput, message: "The file size could not be read.")
    }
    return size
}

/// Runs `body` while a security-scoped URL is accessible. Plain file URLs are unaffected.
func withSecurityScope<T>(
    _ url: URL,
    _ body: () throws(NeuroVerifyError) -> T
) throws(NeuroVerifyError) -> T {
    #if canImport(Darwin)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    #endif
    return try body()
}
