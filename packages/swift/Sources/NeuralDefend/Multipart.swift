import Foundation

/// A complete `multipart/form-data` request body written to a temporary file, so that
/// `URLSession` can stream it from disk and every retry sends identical bytes.
final class MultipartBody: Sendable {
    let fileURL: URL
    let boundary: String
    let length: Int64

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    private init(fileURL: URL, boundary: String, length: Int64) {
        self.fileURL = fileURL
        self.boundary = boundary
        self.length = length
    }

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Writes the body for `media` under the `file` field. Checks for task cancellation between
    /// chunks, so large copies stop promptly.
    static func write(
        _ media: PreparedMedia,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws(NeuroVerifyError) -> MultipartBody {
        let boundary = "neuraldefend-" + UUID().uuidString.lowercased()
        let head = Data(
            ("--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"file\"; "
                + "filename=\"\(escapeQuoted(media.filename))\"\r\n"
                + "Content-Type: \(media.contentType)\r\n\r\n").utf8
        )
        let tail = Data("\r\n--\(boundary)--\r\n".utf8)
        let fileURL = directory.appendingPathComponent("neuraldefend-\(UUID().uuidString).multipart")

        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            throw .validation(
                code: .unsupportedInput,
                message: "Could not create a temporary upload file."
            )
        }
        let body = MultipartBody(
            fileURL: fileURL,
            boundary: boundary,
            length: Int64(head.count) + media.length + Int64(tail.count)
        )
        do {
            let output = try FileHandle(forWritingTo: fileURL)
            defer { try? output.close() }
            try output.write(contentsOf: head)
            switch media.input.source {
            case .data(let data):
                try output.write(contentsOf: data)
            case .file(let url):
                try withSecurityScope(url) { () throws(NeuroVerifyError) in
                    try copy(url, into: output, expected: media.length)
                }
            }
            try output.write(contentsOf: tail)
        } catch let error as NeuroVerifyError {
            throw error
        } catch {
            throw .validation(
                code: .unsupportedInput,
                message: "Could not write the temporary upload file."
            )
        }
        return body
    }

    private static func copy(
        _ url: URL,
        into output: FileHandle,
        expected: Int64
    ) throws(NeuroVerifyError) {
        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: url)
        } catch {
            throw .validation(code: .fileNotFound, message: "The file could not be opened.")
        }
        defer { try? input.close() }
        var copied: Int64 = 0
        while true {
            if Task.isCancelled { throw .cancelled }
            let chunk: Data
            do {
                chunk = try withAutoreleasePool { try input.read(upToCount: 1 << 20) } ?? Data()
            } catch {
                throw .validation(code: .unsupportedInput, message: "The file could not be read.")
            }
            if chunk.isEmpty { break }
            copied += Int64(chunk.count)
            if copied > expected {
                throw .validation(
                    code: .fileTooLarge,
                    message: "The file grew beyond its declared \(expected) bytes during the upload."
                )
            }
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw .validation(
                    code: .unsupportedInput,
                    message: "Could not write the temporary upload file."
                )
            }
        }
        if copied != expected {
            throw .validation(
                code: .unsupportedInput,
                message: "The file ended after \(copied) of the expected \(expected) bytes."
            )
        }
    }
}

/// Percent-encodes the characters that would break a quoted multipart header parameter,
/// matching the WHATWG form-data encoding used by browsers.
func escapeQuoted(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\r", with: "%0D")
        .replacingOccurrences(of: "\n", with: "%0A")
        .replacingOccurrences(of: "\"", with: "%22")
}

#if canImport(ObjectiveC)
    @inline(__always)
    func withAutoreleasePool<T>(_ body: () throws -> T) rethrows -> T {
        try autoreleasepool(invoking: body)
    }
#else
    @inline(__always)
    func withAutoreleasePool<T>(_ body: () throws -> T) rethrows -> T {
        try body()
    }
#endif
