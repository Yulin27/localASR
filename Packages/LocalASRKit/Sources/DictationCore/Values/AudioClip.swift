import Foundation

/// How a clip's samples are stored.
public enum AudioFormat: String, Sendable, Equatable, Codable {
    case float32
    case int16
}

/// Where a clip came from.
///
/// Distinguishes real recordings from fixtures so measurements and metrics cannot quietly
/// mix the two.
public enum CaptureOrigin: String, Sendable, Equatable, Codable {
    case microphone
    case testFixture
}

/// Describes a captured recording without exposing its samples.
public struct AudioClipMetadata: Sendable, Equatable, Hashable, Codable {
    public let sampleRate: Double
    public let frameCount: Int
    public let channelCount: Int
    public let format: AudioFormat
    public let origin: CaptureOrigin

    public init(
        sampleRate: Double,
        frameCount: Int,
        channelCount: Int = 1,
        format: AudioFormat = .float32,
        origin: CaptureOrigin = .microphone
    ) {
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.channelCount = channelCount
        self.format = format
        self.origin = origin
    }

    public var duration: Duration {
        guard sampleRate > 0 else { return .zero }
        return .seconds(Double(frameCount) / sampleRate)
    }
}

/// Mono, deinterleaved samples at a stated rate.
public struct AudioSamples: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var frameCount: Int { samples.count }
}

/// A half-open frame range inside a clip.
public struct AudioSegment: Sendable, Equatable, Hashable {
    public let startFrame: Int
    public let endFrame: Int

    public init(startFrame: Int, endFrame: Int) {
        self.startFrame = startFrame
        self.endFrame = max(startFrame, endFrame)
    }

    public var frameCount: Int { endFrame - startFrame }
    public var isEmpty: Bool { frameCount == 0 }
}

/// A captured recording.
///
/// Deliberately a reference-shaped protocol rather than a value holding samples.
/// `ARCHITECTURE.md` requires capture to stay bounded in memory and to support disk-backed
/// long recordings, and a value type would force such an adapter to materialize every frame
/// it owns.
///
/// The coordinator never calls ``loadSamples()``. Only the adapters that consume audio
/// (voice activity detection and recognition) do, which keeps megabytes of PCM out of the
/// state machine and out of ``SessionSnapshot``.
///
/// A conforming type that is an actor satisfies ``metadata`` with a `nonisolated let`.
public protocol AudioClip: Sendable {
    var metadata: AudioClipMetadata { get }

    /// Reads the whole recording as mono Float32 PCM. Must honour task cancellation.
    func loadSamples() async throws -> AudioSamples

    /// Releases whatever the clip owns. Must be idempotent, and must be safe to call from
    /// the coordinator's cleanup path even when capture produced nothing usable.
    func discard() async
}
