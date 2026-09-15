/// Chooses the assembly, once, at launch.
///
/// This is the only place the build configuration or the launch environment decides anything.
/// Features receive the resulting model and never ask which assembly produced it.
@MainActor
enum CompositionRoot {
    enum AssemblyKind: Equatable {
        case production
        case demo
        case test
    }

    /// In Debug, the test assembly when hosted by tests and demo otherwise. Always production in
    /// Release: the launch environment is outside the build's control, so it must not be able to
    /// put scripted adapters into a Release build.
    static func assemblyKind(environment: [String: String]) -> AssemblyKind {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
        {
            return .test
        }
        return .demo
        #else
        return .production
        #endif
    }

    static func assembly(for kind: AssemblyKind) -> any ApplicationAssembly {
        switch kind {
        case .production:
            return ProductionAssembly()
        case .test, .demo:
            #if DEBUG
            return kind == .test ? TestAssembly() : DemoAssembly()
            #else
            // Neither is selectable in Release; see `assemblyKind(environment:)`.
            return ProductionAssembly()
            #endif
        }
    }

    static func makeApplicationModel(environment: [String: String]) -> AppModel {
        AppModel(startup: assembly(for: assemblyKind(environment: environment)).makeStartup())
    }
}
