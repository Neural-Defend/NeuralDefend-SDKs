import Foundation
import NeuralDefend
import Observation

/// Drives the demo screen: uploads one image or video and turns the outcome into text.
///
/// It branches on `status` first, shows rejections as normal outcomes, and maps each
/// `NeuroVerifyError` case to guidance, which is the pattern a real app should follow.
@MainActor
@Observable
public final class DetectionModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case uploading(fraction: Double)
        case finished(Summary)
        case failed(String)
    }

    public struct Summary: Equatable, Sendable {
        public let title: String
        public let detail: String
        public let transactionID: String
    }

    public private(set) var phase: Phase = .idle

    private let client: NeuroVerifyClient
    private var current: Task<Void, Never>?

    public init(client: NeuroVerifyClient) {
        self.client = client
    }

    /// Starts an upload, cancelling any upload still in progress.
    public func start(_ media: MediaInput, isVideo: Bool) {
        current?.cancel()
        current = Task { await analyze(media, isVideo: isVideo) }
    }

    public func cancel() {
        current?.cancel()
    }

    /// Uploads `media` and waits for the outcome.
    public func analyze(_ media: MediaInput, isVideo: Bool) async {
        phase = .uploading(fraction: 0)
        let progress: UploadProgressHandler = { [weak self] sent, total in
            let fraction = total > 0 ? Double(sent) / Double(total) : 0
            Task { @MainActor in self?.reportProgress(fraction) }
        }
        do {
            if isVideo {
                let result = try await client.detectVideo(media, maxFrames: 12, onProgress: progress)
                phase = .finished(Self.summary(result))
            } else {
                let result = try await client.detectImage(media, onProgress: progress)
                phase = .finished(Self.summary(result))
            }
        } catch let error as NeuroVerifyError {
            phase = .failed(Self.guidance(for: error))
        } catch {
            phase = .failed("Unexpected error: \(error.localizedDescription)")
        }
    }

    private func reportProgress(_ fraction: Double) {
        if case .uploading = phase { phase = .uploading(fraction: fraction) }
    }

    static func summary(_ result: ImageResult) -> Summary {
        switch result.status {
        case .success:
            let level = result.riskLevel?.rawValue ?? "unknown"
            let score = result.riskScore.map { String(format: "%.1f", $0) } ?? "-"
            return Summary(
                title: "Risk: \(level)",
                detail: "Score \(score) of 10. \(result.message)",
                transactionID: result.uniqueTrxID
            )
        case .rejected:
            return Summary(title: "Not analyzed", detail: result.message, transactionID: result.uniqueTrxID)
        case .unknown:
            return Summary(
                title: "Unrecognized result",
                detail: "Update the SDK to read status \"\(result.originalStatus)\".",
                transactionID: result.uniqueTrxID
            )
        }
    }

    static func summary(_ result: VideoResult) -> Summary {
        switch result.status {
        case .success:
            let video = result.videoRiskLevel?.rawValue ?? "unknown"
            let audio = result.hasAudio ? (result.audioRiskLevel?.rawValue ?? "unknown") : "no audio"
            return Summary(
                title: "Video risk: \(video)",
                detail: "Audio: \(audio). \(result.videoMessage)",
                transactionID: result.uniqueTrxID
            )
        case .rejected:
            return Summary(title: "Not analyzed", detail: result.videoMessage, transactionID: result.uniqueTrxID)
        case .unknown:
            return Summary(
                title: "Unrecognized result",
                detail: "Update the SDK to read status \"\(result.originalStatus)\".",
                transactionID: result.uniqueTrxID
            )
        }
    }

    static func guidance(for error: NeuroVerifyError) -> String {
        switch error {
        case .validation(_, let message):
            return message
        case .authentication:
            return "The API key was rejected. Check that it is valid for this environment."
        case .scope:
            return "This API key cannot use this endpoint."
        case .rateLimit(_, let info):
            let wait = info.retryAfter.map { " Try again in \(Int($0)) seconds." } ?? ""
            return "Too many requests.\(wait)"
        case .server, .http, .protocol:
            let reference = error.requestID.map { " Reference: \($0)." } ?? ""
            return "The service could not process the request.\(reference)"
        case .timeout:
            return "The upload took too long. Check the connection and try again."
        case .network:
            return "No connection to the service."
        case .cancelled:
            return "Cancelled."
        }
    }
}
