import Foundation

/// Records privacy-safe session measurements.
///
/// Everything it can receive is already free of transcript text, audio, prompts, clipboard
/// contents, and cursor context — see ``SessionMetrics``.
public protocol MetricsRecording: Sendable {
    /// Records one session's summary. Called exactly once per session, when it reaches a
    /// terminal phase.
    ///
    /// Non-throwing by design: measurements are never worth failing a user's dictation for.
    func record(_ metrics: SessionMetrics)
}

/// Discards everything. For tests and for assemblies with no metrics destination.
public struct NoopMetricsRecorder: MetricsRecording {
    public init() {}

    public func record(_ metrics: SessionMetrics) {}
}

public extension MetricsRecording where Self == NoopMetricsRecorder {
    static var noop: NoopMetricsRecorder { NoopMetricsRecorder() }
}
