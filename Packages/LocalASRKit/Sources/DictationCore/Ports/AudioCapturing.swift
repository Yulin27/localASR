import Foundation

/// Owns the microphone.
///
/// A conforming type holds mutable device state, so it is an actor in practice. The
/// coordinator owns the *session* lifecycle; this port owns the *device* lifecycle.
///
/// Recording is press-to-start, so a real implementation pays its start-up cost while the
/// user is already speaking. ``prepare()`` exists so that cost can be moved earlier without
/// changing this contract when the capture module is rebuilt on AUHAL.
public protocol AudioCapturing: Sendable {
    /// Warms the capture path without recording.
    ///
    /// Called during the session's `preparing` phase. An implementation with nothing to warm
    /// may do nothing, and one that is already warm should be cheap.
    func prepare() async throws

    /// Begins recording. Returns once the microphone is live and audio is being captured.
    func start() async throws

    /// Stops recording and hands back the captured audio.
    func stop() async throws -> any AudioClip

    /// Aborts recording and releases the device without producing a clip.
    ///
    /// Must be safe to call when recording never started, and must be idempotent.
    func cancel() async
}
