import AppKit

/// Owns the application's lifetime.
///
/// The composition is built once, when the delegate is created, and lives until the application
/// quits. Quitting waits for the coordinator to shut down and for the model to stop observing it.
/// It does not wait for a session in flight to finish its cleanup: shutting down cancels that
/// session, and its release of the device, disposal of the clip, and history write run on after
/// termination has been allowed. Phase 3 adds a bounded wait for them, once real adapters hold
/// real resources.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    /// The initializer `NSApplicationDelegateAdaptor` uses.
    override convenience init() {
        self.init(
            model: CompositionRoot.makeApplicationModel(
                environment: ProcessInfo.processInfo.environment
            )
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Shuts the coordinator down and waits for the model to stop observing it.
    func prepareForTermination() async {
        await model.shutdown()
    }
}
