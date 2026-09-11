import Foundation

/// A moment in time, carrying a wall-clock reading and a monotonic one together.
///
/// Stage timing must not be distorted by a clock adjustment, and a history record needs a
/// real date, so both readings are taken at once rather than from two sources that could
/// disagree.
public struct Timestamp: Sendable, Equatable, Comparable {
    /// Wall-clock time, for records a human reads later.
    public let date: Date

    /// A monotonically non-decreasing reading in seconds. Only differences are meaningful;
    /// the origin is arbitrary.
    public let uptime: TimeInterval

    public init(date: Date, uptime: TimeInterval) {
        self.date = date
        self.uptime = uptime
    }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        lhs.uptime < rhs.uptime
    }

    /// The time elapsed since an earlier reading. Never negative.
    public func elapsed(since earlier: Timestamp) -> Duration {
        .seconds(max(0, uptime - earlier.uptime))
    }
}

/// Supplies the current time.
///
/// Injected so that tests assert exact stage durations without sleeping, and so that
/// `DictationCore` never reads the clock itself.
public protocol TimeSource: Sendable {
    func now() -> Timestamp
}
