import Foundation
import Testing

/// Hosted tests run inside the application, so the main bundle is the application's own.
@Suite("Application bundle")
struct ApplicationBundleTests {
    @Test("The bundle identifier that keys privacy grants and preferences is fixed")
    func bundleIdentifierIsFixed() {
        #expect(Bundle.main.bundleIdentifier == "io.github.yulin27.LocalASR")
    }

    @Test("The application runs as a menu-bar agent with no Dock icon")
    func runsAsAgent() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }
}
