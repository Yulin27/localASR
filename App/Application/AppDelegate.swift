import AppKit

/// Owns the application's lifetime. The composition root is wired in once it exists.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {}
