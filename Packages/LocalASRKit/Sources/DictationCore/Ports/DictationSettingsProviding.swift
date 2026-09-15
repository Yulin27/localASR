import Foundation

/// Supplies the preferences a session freezes at start.
///
/// `DictationCore` never reads `UserDefaults`, the environment, or any other global, so the
/// settings a session needs arrive through this port and are copied into
/// ``SessionContext``.
public protocol DictationSettingsProviding: Sendable {
    /// The settings to freeze into a starting session.
    ///
    /// Never throws. If stored preferences cannot be read, an implementation should return
    /// ``DictationSettings/standard`` rather than prevent dictation.
    func currentSettings() async -> DictationSettings
}

/// Always reports the standard settings.
public struct StaticSettingsProvider: DictationSettingsProviding {
    private let settings: DictationSettings

    public init(_ settings: DictationSettings = .standard) {
        self.settings = settings
    }

    public func currentSettings() async -> DictationSettings { settings }
}
