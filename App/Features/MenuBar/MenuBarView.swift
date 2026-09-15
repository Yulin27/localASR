import AppKit
import DictationDemo
import SwiftUI

/// The status-item icon. Status-only, so it carries an accessibility label.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let presentation = model.presentation
        Image(systemName: presentation.symbolName)
            .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// The menu shown from the status item.
///
/// Receives the model and sends actions; it constructs nothing and decides nothing. Which
/// commands are enabled comes from the presentation, and the demo section appears only when the
/// assembly runs demo scenarios.
struct MenuBarContent: View {
    let model: AppModel

    var body: some View {
        let presentation = model.presentation

        Text(presentation.statusText)
            .accessibilityLabel(presentation.accessibilityLabel)
        ForEach(presentation.details, id: \.self) { detail in
            Text(detail)
        }

        if !presentation.commands.isEmpty {
            Divider()
            ForEach(presentation.commands) { command in
                Button(command.title) {
                    model.send(command.action)
                }
                .disabled(!command.isEnabled)
                .accessibilityLabel(command.accessibilityLabel)
            }
        }

        if let scenario = model.demoScenario {
            Divider()
            Picker(
                "Demo Scenario",
                selection: Binding(
                    get: { scenario },
                    set: { model.selectDemoScenario($0) }
                )
            ) {
                ForEach(DemoScenario.allCases, id: \.self) { scenario in
                    Text(scenario.menuTitle).tag(scenario)
                }
            }
            .accessibilityLabel("Demo scenario for the next dictation")
        }

        Divider()
        Button("Quit LocalASR") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .accessibilityLabel("Quit LocalASR")
    }
}

extension DemoScenario {
    var menuTitle: String {
        switch self {
        case .success: "Success"
        case .refinementFallback: "Refinement Fallback"
        case .copiedOnly: "Copied Only"
        case .recognitionFailure: "Recognition Failure"
        case .noSpeech: "No Speech"
        }
    }
}
