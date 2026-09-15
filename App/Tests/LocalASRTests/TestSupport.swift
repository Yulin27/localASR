import DictationCore
import DictationDemo
import Foundation

@testable import LocalASR

struct ConditionNeverHeld: Error, CustomStringConvertible {
    let condition: String
    var description: String { "Timed out waiting until \(condition)" }
}

/// Moves a manual clock in small steps, letting the coordinator and the main actor run between
/// them, until `holds` is true.
@MainActor
func advance(
    _ clock: ManualClock,
    until condition: String,
    attempts: Int = 5_000,
    _ holds: () -> Bool
) async throws {
    for _ in 0..<attempts {
        if holds() { return }
        clock.advance(by: .milliseconds(50))
        for _ in 0..<4 {
            await Task.yield()
        }
    }
    throw ConditionNeverHeld(condition: condition)
}

extension StartupResult {
    var services: ReadyServices? {
        if case .ready(let services) = self { return services }
        return nil
    }
}
