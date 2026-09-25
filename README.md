# Rice

Rice is a native SwiftUI iPhone customization app by Marginally Better Apps. It has no account, backend, ads, analytics SDK, or runtime package dependencies. The built-in themes, editor, wallpaper and icon exports, and file sharing work offline.

This repository is an early development build. It is not a release candidate. The checked-in project targets iOS 27.0, but the available machine has Xcode 26.5 and the iOS 26.5 SDK. The current code compiles with that SDK; iOS 27 APIs and physical-device behavior still need verification.

## What works in source

- Eight original built-in color themes and two declarative widget components per theme.
- A palette and caption editor with undo, redo and duplication.
- Local `.ricepack` review, import and export. The current importer accepts uncompressed ZIP entries only.
- Three original importable [sample packs](examples/) are included for format testing and remixing.
- A WidgetKit extension with Home Screen small, medium and large families plus Lock Screen rectangular accessory. Widgets refer to stable slot IDs and read the app's App Group state.
- A setup checklist that records user-reported progress, with separate widget refresh request and extension read timestamps.
- Procedural PNG wallpaper and icon artwork exports. iOS applies wallpaper and Shortcuts launchers through its own UI.

The app does not yet have photo import, a layer-tree editor, alternate appearances, Live Activities, controls, AlarmKit, Focus filters, optional providers, community catalog, or full malicious-archive coverage. See [evidence ledger](docs/EVIDENCE.md) for the current test status.

## Build

Install XcodeGen for project regeneration, then run:

```sh
xcodegen generate
xcodebuild -project Rice.xcodeproj -scheme Rice -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The project sets `IPHONEOS_DEPLOYMENT_TARGET=27.0`. With the installed iOS 26.5 SDK, Xcode warns that this target exceeds the SDK. To run the current code in an iOS 26.5 simulator, temporarily change the target in `project.yml` to 26.5 and regenerate. Restore 27.0 before committing. App Group widget sharing on a physical iPhone requires matching signed entitlements for the app and extension.

The unsigned device IPA is built from a Release `iphoneos` build by placing `Rice.app` in a `Payload` directory and zipping it. See [build notes](docs/BUILD.md). Unsigned does not mean installable without a signing workflow.

## Format

The development format is described in [schema/README.md](schema/README.md). Imported packs are declarative data and never execute code or fetch remote references. The importer validates archive names, sizes, CRCs, duplicate JSON keys, scene nodes, token and asset references, image dimensions, and SHA-256 hashes before adding a theme to the library.

## License

Code and original built-in theme artwork are MIT licensed. See [LICENSE](LICENSE).
