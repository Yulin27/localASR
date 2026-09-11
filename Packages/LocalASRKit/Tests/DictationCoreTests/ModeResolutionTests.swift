import Foundation
import Testing

@testable import DictationCore

@Suite("Mode resolution")
struct ModeResolutionTests {
    private let resolver = BundleIDModeResolver(bindings: [
        "com.tinyspeck.slackmacgap": .message,
        "com.apple.mail": .email,
    ])

    @Test("A bound destination resolves to its bound mode")
    func boundDestinationResolves() {
        #expect(resolve(bundleID: "com.tinyspeck.slackmacgap") == .message)
        #expect(resolve(bundleID: "com.apple.mail") == .email)
    }

    @Test("An unbound destination falls back to the user's default")
    func unboundDestinationFallsBack() {
        #expect(resolve(bundleID: "com.example.unknown") == .structured)
    }

    @Test("No destination falls back to the user's default")
    func noDestinationFallsBack() {
        #expect(resolver.resolveMode(for: nil, default: .structured) == .structured)
    }

    @Test("A destination without a bundle identifier falls back to the default")
    func destinationWithoutBundleIDFallsBack() {
        let target = InsertionTarget(
            application: ActiveApplication(processIdentifier: 42, bundleIdentifier: nil)
        )
        #expect(resolver.resolveMode(for: target, default: .email) == .email)
    }

    @Test("Resolution is pure and stable across repeated calls")
    func resolutionIsStable() {
        let target = InsertionTarget(
            application: ActiveApplication(
                processIdentifier: 7,
                bundleIdentifier: "com.tinyspeck.slackmacgap"
            )
        )
        let results = (0..<5).map { _ in resolver.resolveMode(for: target, default: .note) }
        #expect(Set(results) == [.message])
    }

    @Test("With no bindings, every destination uses the user's default")
    func emptyResolverUsesDefault() {
        let empty = BundleIDModeResolver()
        #expect(empty.resolveMode(for: nil, default: .note) == .note)
        #expect(resolve(bundleID: "com.tinyspeck.slackmacgap", with: empty) == .structured)
    }

    private func resolve(
        bundleID: String,
        with resolver: BundleIDModeResolver? = nil
    ) -> RefinementMode {
        let target = InsertionTarget(
            application: ActiveApplication(processIdentifier: 1, bundleIdentifier: bundleID)
        )
        return (resolver ?? self.resolver).resolveMode(for: target, default: .structured)
    }
}
