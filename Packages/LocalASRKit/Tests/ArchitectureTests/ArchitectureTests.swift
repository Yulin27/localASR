import AudioCapture
import DictationCore
import MacIntegration
import ModelManagement
import Observability
import Persistence
import SpeechEngines
import Testing
import TextProcessing

@Test("All architecture modules are available")
func allModulesAreAvailable() {
    _ = DictationCoreModule.self
    _ = AudioCaptureModule.self
    _ = SpeechEnginesModule.self
    _ = TextProcessingModule.self
    _ = MacIntegrationModule.self
    _ = ModelManagementModule.self
    _ = PersistenceModule.self
    _ = ObservabilityModule.self
}

