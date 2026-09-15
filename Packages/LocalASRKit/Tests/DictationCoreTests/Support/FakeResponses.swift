import Foundation
import Synchronization

@testable import DictationCore

/// An error a fake throws to stand in for an unmapped provider failure.
struct UnmappedProviderError: Error {}

/// What a fake port should do when its method is called.
enum FakeResponse<Value: Sendable>: Sendable {
    case value(Value)
    /// Throws a typed domain failure, as a well-behaved adapter would.
    case failure(DictationFailure)
    /// Throws `CancellationError`. In a cancelled session this is an adapter honouring the
    /// cancellation; in a live one it is an adapter whose own internal cancellation escaped,
    /// such as a refiner enforcing a deadline on a child task.
    case cancelled
    /// Throws an error that was never mapped to a domain failure.
    case unmappedFailure

    func resolve() throws -> Value {
        switch self {
        case .value(let value): return value
        case .failure(let failure): throw failure
        case .cancelled: throw CancellationError()
        case .unmappedFailure: throw UnmappedProviderError()
        }
    }
}

extension FakeResponse where Value == Void {
    static var ok: FakeResponse<Void> { .value(()) }
}

/// A deterministic clock.
///
/// Every read advances the clock by a fixed step, so stage durations are exact and
/// reproducible instead of depending on real elapsed time.
final class FakeTimeSource: TimeSource, Sendable {
    /// How far the clock moves on each read.
    static let step: Duration = .milliseconds(250)

    private struct State {
        var date: Date
        var uptime: TimeInterval
    }

    private let state: Mutex<State>

    init(
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        uptime: TimeInterval = 0
    ) {
        state = Mutex(State(date: start, uptime: uptime))
    }

    func now() -> Timestamp {
        state.withLock { state in
            let reading = Timestamp(date: state.date, uptime: state.uptime)
            state.uptime += Self.step.seconds
            state.date = state.date.addingTimeInterval(Self.step.seconds)
            return reading
        }
    }
}

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}

/// Records session summaries, and can be made to fail.
///
/// `MetricsRecording.record` is synchronous by contract, so the fake guards its storage with a
/// mutex rather than being an actor.
final class FakeMetricsRecorder: MetricsRecording, Sendable {
    private let recorded = Mutex<[SessionMetrics]>([])

    func record(_ metrics: SessionMetrics) {
        recorded.withLock { $0.append(metrics) }
    }

    var all: [SessionMetrics] { recorded.withLock { $0 } }

    var last: SessionMetrics? { all.last }
}
