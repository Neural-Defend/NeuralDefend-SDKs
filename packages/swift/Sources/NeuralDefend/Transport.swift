import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Receives upload progress for the current attempt, in bytes of the multipart request body.
/// `sentBytes` restarts at zero when an automatic retry begins.
public typealias UploadProgressHandler = @Sendable (_ sentBytes: Int64, _ totalBytes: Int64) -> Void

/// One HTTP exchange's outcome.
struct TransportResponse: Sendable {
    let statusCode: Int
    let headers: HTTPURLResponse
    let body: Data

    func header(_ name: String) -> String? {
        headers.value(forHTTPHeaderField: name)
    }
}

/// Streams uploads from disk with `URLSession`. Redirects are never followed, every attempt has
/// its own deadline, and cancelling the calling task cancels the transfer.
final class Transport: Sendable {
    private let session: URLSession
    private let delegate: TransportDelegate

    init(configuration: URLSessionConfiguration) {
        let delegate = TransportDelegate()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.neuraldefend.sdk.transport"
        self.delegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    func upload(
        _ request: URLRequest,
        bodyFile: URL,
        totalBytes: Int64,
        timeout: TimeInterval,
        label: String,
        onProgress: UploadProgressHandler?
    ) async throws(NeuroVerifyError) -> TransportResponse {
        let task = session.uploadTask(with: request, fromFile: bodyFile)
        let exchange = Exchange(
            task: task,
            totalBytes: totalBytes,
            timeout: timeout,
            label: label,
            onProgress: onProgress
        )
        delegate.register(exchange, for: task.taskIdentifier)
        let outcome: Result<TransportResponse, NeuroVerifyError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                exchange.start(continuation)
            }
        } onCancel: {
            exchange.end(.cancelled)
        }
        return try outcome.get()
    }
}

/// State of one upload task, shared between the caller, its timer, and the session delegate.
private final class Exchange: @unchecked Sendable {
    private static let maxResponseBytes = 8 * 1024 * 1024

    enum EndReason {
        case cancelled
        case timedOut
        case responseTooLarge
    }

    private let lock = NSLock()
    private let task: URLSessionTask
    private let totalBytes: Int64
    private let timeout: TimeInterval
    private let label: String
    private let onProgress: UploadProgressHandler?
    private var continuation: CheckedContinuation<Result<TransportResponse, NeuroVerifyError>, Never>?
    private var reason: EndReason?
    private var finished = false
    private var body = Data()
    private var timer: Task<Void, Never>?
    private var reportedBytes: Int64 = 0

    init(
        task: URLSessionTask,
        totalBytes: Int64,
        timeout: TimeInterval,
        label: String,
        onProgress: UploadProgressHandler?
    ) {
        self.task = task
        self.totalBytes = totalBytes
        self.timeout = timeout
        self.label = label
        self.onProgress = onProgress
    }

    func start(_ continuation: CheckedContinuation<Result<TransportResponse, NeuroVerifyError>, Never>) {
        lock.lock()
        self.continuation = continuation
        let alreadyEnded = reason != nil
        if !alreadyEnded {
            let nanoseconds = UInt64(timeout * 1_000_000_000)
            timer = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                self?.end(.timedOut)
            }
        }
        lock.unlock()
        if alreadyEnded {
            complete(error: nil, response: nil)
            return
        }
        onProgress?(0, totalBytes)
        task.resume()
    }

    /// Stops the transfer for `reason`. The first reason wins.
    func end(_ reason: EndReason) {
        lock.lock()
        let shouldCancel = self.reason == nil && !finished
        if shouldCancel { self.reason = reason }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func append(_ data: Data) {
        lock.lock()
        let overflows =
            data.count > Self.maxResponseBytes
            || body.count > Self.maxResponseBytes - data.count
        if overflows {
            let shouldCancel = reason == nil && !finished
            if shouldCancel { reason = .responseTooLarge }
            lock.unlock()
            if shouldCancel { task.cancel() }
            return
        }
        body.append(data)
        lock.unlock()
    }

    func progress(sent: Int64) {
        guard let onProgress else { return }
        lock.lock()
        let advanced = sent > reportedBytes
        if advanced { reportedBytes = sent }
        lock.unlock()
        if advanced { onProgress(sent, totalBytes) }
    }

    func complete(error: (any Error)?, response: URLResponse?) {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        let reason = self.reason
        let body = self.body
        timer?.cancel()
        timer = nil
        lock.unlock()
        // Darwin can complete an upload without delivering didSendBodyData callbacks, and
        // countOfBytesSent can still read 0 at that point, so a response ends the attempt at 100%.
        if reason == nil && error == nil && response is HTTPURLResponse {
            progress(sent: totalBytes)
        }
        continuation.resume(returning: outcome(reason: reason, error: error, response: response, body: body))
    }

    private func outcome(
        reason: EndReason?,
        error: (any Error)?,
        response: URLResponse?,
        body: Data
    ) -> Result<TransportResponse, NeuroVerifyError> {
        switch reason {
        case .cancelled?:
            return .failure(.cancelled)
        case .timedOut?:
            return .failure(timedOut())
        case .responseTooLarge?:
            return .failure(
                .protocol(
                    ErrorDetails(
                        message: "The response body exceeded 8 MiB.",
                        statusCode: (response as? HTTPURLResponse)?.statusCode,
                        requestID: (response as? HTTPURLResponse)?
                            .value(forHTTPHeaderField: "x-request-id")
                    )
                )
            )
        case nil:
            break
        }
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                return .failure(timedOut())
            }
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return .failure(.cancelled)
            }
            return .failure(
                .network(
                    message: "The \(label) request failed before receiving a response: "
                        + nsError.localizedDescription
                )
            )
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.network(message: "The \(label) request did not receive an HTTP response."))
        }
        return .success(TransportResponse(statusCode: http.statusCode, headers: http, body: body))
    }

    private func timedOut() -> NeuroVerifyError {
        let milliseconds = Int((timeout * 1000).rounded())
        return .timeout(message: "The \(label) request timed out after \(milliseconds) ms.")
    }
}

private final class TransportDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var exchanges: [Int: Exchange] = [:]

    func register(_ exchange: Exchange, for identifier: Int) {
        lock.lock()
        exchanges[identifier] = exchange
        lock.unlock()
    }

    private func exchange(for task: URLSessionTask, remove: Bool = false) -> Exchange? {
        lock.lock()
        defer { lock.unlock() }
        return remove ? exchanges.removeValue(forKey: task.taskIdentifier) : exchanges[task.taskIdentifier]
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // The redirect target would receive the API key and the media, so the 3xx response is
        // returned to the caller instead.
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        exchange(for: task)?.progress(sent: totalBytesSent)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        exchange(for: dataTask)?.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        exchange(for: task, remove: true)?.complete(error: error, response: task.response)
    }
}
