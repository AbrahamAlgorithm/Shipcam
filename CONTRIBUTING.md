# Contributing to Shipcam

Thanks for your interest! Shipcam is in early development, so the code changes quickly. If you plan something bigger than a small fix, open an issue first so we can agree on the approach.

## What you need

- A Mac running macOS 26, ideally with Apple silicon. The app itself will support macOS 14 and later.
- Xcode 26 (CI uses Xcode 26.6).
- SwiftLint 0.65.1: `brew install swiftlint`. CI pins this exact version.

swift-format ships with Xcode as `swift format`, so there's nothing extra to install for it.

## Repository layout

```
Packages/ShipcamKit/     Swift package with every module except the app target
  Sources/<Module>/      one folder per module
  Tests/<Module>Tests/   tests, using Swift Testing
scripts/                 format.sh and lint.sh
.github/workflows/       CI
```

The macOS app target is coming next.

## Module rules

The modules form two layers, declared in [`Packages/ShipcamKit/Package.swift`](Packages/ShipcamKit/Package.swift):

- **Pure modules** (`ProjectModel`, `TimeMapping`, `CursorEngine`, `ZoomEngine`) may import only Foundation, simd and each other. They hold most of the logic and must be fully testable without a screen, GPU or permissions.
- **Platform modules** (`RecorderCore`, `Compositor`, `AudioEngine`, `Captions`, `Exporter`, `EditorUI`) wrap Apple's capture, rendering, audio and UI frameworks.

A pure module never depends on a platform module. Two checks enforce this in CI:
- SwiftPM's explicit import check, for imports between our own modules;
- a SwiftLint rule, for Apple frameworks.

If you need a new dependency between modules, add it to `Package.swift` and explain why in your pull request.

## Build and test

```sh
cd Packages/ShipcamKit
swift build --explicit-target-dependency-import-check error
swift test --explicit-target-dependency-import-check error
```

Write tests for any logic you add to a pure module, ideally before the code.

## Code style

```sh
scripts/format.sh   # rewrite files to match the style
scripts/lint.sh     # check style, the same check CI runs
```

swift-format decides layout. SwiftLint checks code quality, for example no force-unwraps and no `print` in source files. CI also runs the formatter and fails if it changes anything, so run `scripts/format.sh` before you commit.

## Commits and pull requests

- Keep each commit small and working: it builds and its tests pass.
- Write commit messages as [Conventional Commits](https://www.conventionalcommits.org): `feat: …`, `fix: …`, `test: …`, `docs: …`, `ci: …`, `chore: …`.
- One feature or fix per pull request. Say what changed and why.
- CI must be green before a pull request is merged.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `swift test` fails with `no such module 'Testing'` | Only the Command Line Tools are active. Install Xcode, then run `sudo xcode-select -s /Applications/Xcode.app`. |
| SwiftLint crashes with `Loading sourcekitdInProc.framework … failed` | SwiftLint can't find Xcode's SourceKit. Install Xcode, or set `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools`. |
| CI's "Check formatting" step fails | A file wasn't formatted. Run `scripts/format.sh` and commit the result. |

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
