import Foundation

/// Resolves a written form from the source application's bundle identifier.
///
/// The bindings are typed data supplied at construction. Phase 1 ships no bindings, so every
/// application resolves to the user's default — the shape is here so per-application
/// behaviour does not require changing the coordinator, and the table itself is filled in
/// once there are real destinations to observe.
public struct BundleIDModeResolver: ModeResolving {
    private let bindings: [String: RefinementMode]

    public init(bindings: [String: RefinementMode] = [:]) {
        self.bindings = bindings
    }

    public func resolveMode(
        for application: ActiveApplication?,
        default defaultMode: RefinementMode
    ) -> RefinementMode {
        guard let bundleID = application?.bundleIdentifier else { return defaultMode }
        return bindings[bundleID] ?? defaultMode
    }
}
