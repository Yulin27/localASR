import AppKit

/// Owns the application's lifetime.
///
/// The composition is built once, when the delegate is created, and lives until the application
/// quits. Quitting waits for the coordinator to shut down, so a session in flight releases what
/// it holds before the process exits.
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
