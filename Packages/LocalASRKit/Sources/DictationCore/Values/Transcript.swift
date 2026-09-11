import Foundation

/// The text produced by each pipeline stage.
///
/// The stages are separate values on purpose. `rawText` is the recognition output and is
/// never overwritten; `normalizedText` is the deterministic result; `finalText` is either
/// the accepted refinement or the deterministic text it fell back to.
///
/// A later stage can be missing — a session cancelled mid-pipeline has no final text — but
/// an earlier stage is never discarded. That is what lets a refiner failure and an insertion
/// failure both leave the user's words intact.
public struct Transcript: Sendable, Equatable {
    public let rawText: String?
    public let normalizedText: String?
    public let finalText: String?

    public init(
        rawText: String? = nil,
        normalizedText: String? = nil,
        finalText: String? = nil
    ) {
        self.rawText = rawText
        self.normalizedText = normalizedText
        self.finalText = finalText
    }

    public static let empty = Transcript()

    /// The best text available for delivery, or for the user to copy after a failure.
    public var bestAvailableText: String? { finalText ?? normalizedText ?? rawText }
}

/// Deterministic processing output, with the transforms that produced it.
public struct NormalizedText: Sendable, Equatable {
    public let text: String
    public let transforms: [TransformIdentifier]

    public init(text: String, transforms: [TransformIdentifier] = []) {
        self.text = text
        self.transforms = transforms
    }
}

/// Identifies one deterministic transform and the version of its rule set.
public struct TransformIdentifier: Sendable, Equatable, Hashable, Codable {
    public let identifier: String
    public let version: Int

    public init(identifier: String, version: Int) {
        self.identifier = identifier
        self.version = version
    }
}

/// Identifies the exact engine revision that produced a result.
///
/// Stored with every session so a delivered result can always be attributed to the model
/// and version that produced it.
public struct EngineIdentifier: Sendable, Equatable, Hashable, Codable {
    public let name: String
    public let version: String?
    /// The immutable upstream revision, when the engine has one.
    public let revision: String?

    public init(name: String, version: String? = nil, revision: String? = nil) {
        self.name = name
        self.version = version
        self.revision = revision
    }
}
