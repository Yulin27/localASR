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

    /// The test assembly when hosted by tests, otherwise demo in Debug and production in Release.
    static func assemblyKind(environment: [String: String]) -> AssemblyKind {
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
        {
            return .test
        }
        #if DEBUG
        return .demo
        #else
        return .production
        #endif
    }

    static func assembly(for kind: AssemblyKind) -> any ApplicationAssembly {
        switch kind {
        case .production:
            return ProductionAssembly()
        case .test:
            return TestAssembly()
        case .demo:
            #if DEBUG
            return DemoAssembly()
            #else
            // Not selectable in Release; see `assemblyKind(environment:)`.
            return ProductionAssembly()
            #endif
        }
    }

    static func makeApplicationModel(environment: [String: String]) -> AppModel {
        AppModel(startup: assembly(for: assemblyKind(environment: environment)).makeStartup())
    }
}
