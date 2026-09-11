// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LocalASRKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "LocalASRKit",
            targets: [
                "DictationCore",
                "AudioCapture",
                "SpeechEngines",
                "TextProcessing",
                "MacIntegration",
                "ModelManagement",
                "Persistence",
                "Observability",
            ]
        )
    ],
    targets: [
        .target(
            name: "DictationCore",
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "Observability",
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "AudioCapture",
            dependencies: ["DictationCore", "Observability"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "ModelManagement",
            dependencies: ["DictationCore", "Observability"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "SpeechEngines",
            dependencies: ["DictationCore", "ModelManagement", "Observability"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "TextProcessing",
            dependencies: ["DictationCore", "ModelManagement", "Observability"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "MacIntegration",
            dependencies: ["DictationCore", "Observability"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "Persistence",
            dependencies: ["DictationCore", "Observability"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .testTarget(
            name: "ArchitectureTests",
            dependencies: [
                "DictationCore",
                "AudioCapture",
                "SpeechEngines",
                "TextProcessing",
                "MacIntegration",
                "ModelManagement",
                "Persistence",
                "Observability",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
