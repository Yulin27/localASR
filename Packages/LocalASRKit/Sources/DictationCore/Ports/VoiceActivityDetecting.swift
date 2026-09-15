import Foundation

/// The result of checking a recording for speech.
public enum VoiceActivityOutcome: Sendable, Equatable {
    /// Transcribe this frame range of the clip. The clip itself is unchanged.
    case speech(AudioSegment)
    /// No speech worth transcribing was found.
    case noSpeech
}

/// Trims silence, rejects empty captures, and may help segment long audio.
///
/// It never ends the primary recording interaction. The user stops dictation by pressing the
/// shortcut a second time; a detector that ends it for them would cut off a speaker who
/// paused to think.
public protocol VoiceActivityDetecting: Sendable {
    /// Returns the frame range worth transcribing, or ``VoiceActivityOutcome/noSpeech``.
    ///
    /// Throwing is non-fatal to the session: the coordinator transcribes the untrimmed clip
    /// and records ``FallbackReason/voiceActivityUnavailable``.
    func trim(_ audio: any AudioClip) async throws -> VoiceActivityOutcome
}
