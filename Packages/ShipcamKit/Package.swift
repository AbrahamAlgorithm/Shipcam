// swift-tools-version: 6.0

// ShipcamKit holds every Shipcam module except the app target itself.
//
// The modules form two layers:
// - Pure: ProjectModel, TimeMapping, CursorEngine, ZoomEngine. They import only
//   Foundation and simd, hold most of the app's logic, and test with `swift test`.
// - Platform: RecorderCore, Compositor, AudioEngine, Captions, Exporter, EditorUI.
//   They wrap Apple's capture, GPU, audio and UI frameworks.
//
// A pure module never depends on a platform module.

import PackageDescription

let modules = [
    "ProjectModel", "TimeMapping", "CursorEngine", "ZoomEngine",
    "RecorderCore", "Compositor", "AudioEngine", "Captions", "Exporter", "EditorUI",
]

let package = Package(
    name: "ShipcamKit",
    platforms: [.macOS(.v14)],
    products: modules.map { .library(name: $0, targets: [$0]) },
    targets: [
        // Pure
        .target(name: "ProjectModel"),
        .target(name: "TimeMapping"),
        .target(name: "CursorEngine", dependencies: ["ProjectModel"]),
        .target(name: "ZoomEngine", dependencies: ["ProjectModel"]),

        // Platform
        .target(name: "RecorderCore", dependencies: ["ProjectModel"]),
        .target(name: "Compositor", dependencies: ["ProjectModel", "CursorEngine", "ZoomEngine"]),
        .target(name: "AudioEngine", dependencies: ["ProjectModel", "TimeMapping"]),
        .target(name: "Captions", dependencies: ["ProjectModel"]),
        .target(name: "Exporter", dependencies: ["ProjectModel", "TimeMapping", "Compositor", "AudioEngine"]),
        .target(name: "EditorUI", dependencies: ["ProjectModel", "TimeMapping", "ZoomEngine", "Compositor"]),

        // Tests (pure modules first; platform modules get test targets with their first code)
        .testTarget(name: "ProjectModelTests", dependencies: ["ProjectModel"]),
        .testTarget(name: "TimeMappingTests", dependencies: ["TimeMapping"]),
        .testTarget(name: "CursorEngineTests", dependencies: ["CursorEngine"]),
        .testTarget(name: "ZoomEngineTests", dependencies: ["ZoomEngine"]),
        .testTarget(name: "RecorderCoreTests", dependencies: ["RecorderCore"]),
    ],
    swiftLanguageModes: [.v6]
)
