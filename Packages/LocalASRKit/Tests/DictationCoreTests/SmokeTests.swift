import DictationCore
import Testing

@Test("The DictationCore module is reachable from its test target")
func dictationCoreModuleIsReachable() {
    _ = DictationCoreModule.self
}
