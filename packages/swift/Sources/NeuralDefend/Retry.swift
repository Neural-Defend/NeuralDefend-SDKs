import Foundation

/// Replaceable timing and randomness, so retry tests run instantly and deterministically.
struct ClientRuntime: Sendable {
    var sleep: @Sendable (TimeInterval) async throws -> Void
    var random: @Sendable () -> Double
    var now: @Sendable () -> Date

    static let live = ClientRuntime(
        sleep: { seconds in
            guard seconds > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        random: { Double.random(in: 0..<1) },
        now: { Date() }
    )
}

/// HTTP statuses retried automatically. Timeouts and network errors are not retried, because
/// the server may already have accepted a billable request.
func isRetryable(_ statusCode: Int) -> Bool {
    statusCode == 429 || statusCode == 500 || statusCode == 503
}

/// Delay before retry number `attempt + 1`: 1, 2, then 4 seconds plus up to 25% jitter. A
/// 429 honors `Retry-After` (capped) and otherwise waits the base delay without jitter.
func retryDelay(
    statusCode: Int,
    retryAfterHeader: String?,
    attempt: Int,
    retryAfterCap: TimeInterval,
    runtime: ClientRuntime
) -> TimeInterval {
    let base = min(pow(2.0, Double(attempt)), 4.0)
    if statusCode == 429 {
        if let retryAfter = parseRetryAfter(retryAfterHeader, cap: retryAfterCap, now: runtime.now()) {
            return retryAfter
        }
        return min(base, retryAfterCap)
    }
    let jitter = min(max(runtime.random(), 0), 1) * base * 0.25
    return base + jitter
}

/// Parses `Retry-After` as delta seconds or an HTTP date, clamped to `0...cap`.
func parseRetryAfter(_ value: String?, cap: TimeInterval, now: Date) -> TimeInterval? {
    let trimmed = value?.trimmingCharacters(in: .whitespaces) ?? ""
    guard !trimmed.isEmpty else { return nil }
    let seconds: TimeInterval
    if let number = Double(trimmed) {
        guard number.isFinite else { return nil }
        seconds = number
    } else if let date = parseHTTPDate(trimmed) {
        seconds = date.timeIntervalSince(now)
    } else {
        return nil
    }
    return min(max(seconds, 0), cap)
}

/// Parses the three HTTP-date formats of RFC 9110 section 5.6.7.
func parseHTTPDate(_ value: String) -> Date? {
    let formats = [
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        "EEEE, dd-MMM-yy HH:mm:ss 'GMT'",
        "EEE MMM d HH:mm:ss yyyy",
    ]
    // asctime pads single-digit days with a second space.
    let normalized = value.split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    for format in formats {
        formatter.dateFormat = format
        if let date = formatter.date(from: normalized) { return date }
    }
    return nil
}
