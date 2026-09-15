import Foundation

/// The application that was frontmost when recording started.
public struct ActiveApplication: Sendable, Equatable, Hashable, Codable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let localizedName: String?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String? = nil,
        localizedName: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

/// The frozen insertion destination.
public struct InsertionTarget: Sendable, Equatable, Hashable, Codable {
    public let application: ActiveApplication

    /// An opaque, adapter-owned identity for the focused element. `DictationCore` never
    /// interprets it; it exists so the insertion adapter can tell whether the caret is still
    /// where the session started.
    public let elementToken: String?

    public init(application: ActiveApplication, elementToken: String? = nil) {
        self.application = application
        self.elementToken = elementToken
    }
}

/// Why no insertion destination could be resolved.
public enum TargetUnavailableReason: String, Sendable, Equatable, Codable {
    case accessibilityPermissionDenied
    case noFocusedElement
    case secureTextField
    case secureInputEnabled
    case unsupported
}

/// What capturing the active application and the insertion destination produced.
public struct TargetCaptureResult: Sendable, Equatable {
    public enum Destination: Sendable, Equatable {
        case captured(InsertionTarget)
        /// Delivery degrades to copy-only. Recording still proceeds: a missing permission
        /// or a password field must not cost the user their dictation.
        case unavailable(TargetUnavailableReason)
    }

    /// The frontmost application. Usually known even when Accessibility permission is
    /// missing or the focused element is unusable, because reading it needs no permission.
    public let application: ActiveApplication?
    public let destination: Destination

    public init(application: ActiveApplication?, destination: Destination) {
        self.application = application
        self.destination = destination
    }

    /// A captured destination. The application is taken from the target so the two can
    /// never disagree.
    public static func captured(_ target: InsertionTarget) -> TargetCaptureResult {
        TargetCaptureResult(application: target.application, destination: .captured(target))
    }

    public static func unavailable(
        _ reason: TargetUnavailableReason,
        application: ActiveApplication? = nil
    ) -> TargetCaptureResult {
        TargetCaptureResult(application: application, destination: .unavailable(reason))
    }

    public var insertionTarget: InsertionTarget? {
        if case .captured(let target) = destination { return target }
        return nil
    }

    public var unavailableReason: TargetUnavailableReason? {
        if case .unavailable(let reason) = destination { return reason }
        return nil
    }
}

/// Everything about a session that is decided once, at start, and never changes.
///
/// Focus, preferences, and per-application rules can all change while the pipeline runs, so
/// the destination, the language hint, and the refinement policy are frozen here. A session
/// must not change its meaning halfway through.
public struct SessionContext: Sendable, Equatable {
    public let id: SessionID
    public let startedAt: Date
    public let target: TargetCaptureResult
    public let languageHint: LanguageHint

    /// The written form this session's destination wants. Always resolved, even when the
    /// model stage is switched off, because deterministic processing is mode-dependent.
    public let mode: RefinementMode

    /// Whether the local refiner runs for this session.
    public let isRefinementEnabled: Bool

    public init(
        id: SessionID,
        startedAt: Date,
        target: TargetCaptureResult,
        languageHint: LanguageHint,
        mode: RefinementMode,
        isRefinementEnabled: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.target = target
        self.languageHint = languageHint
        self.mode = mode
        self.isRefinementEnabled = isRefinementEnabled
    }

    /// The source application, for history and for per-application reporting.
    public var application: ActiveApplication? { target.application }

    public var insertionTarget: InsertionTarget? { target.insertionTarget }
}
