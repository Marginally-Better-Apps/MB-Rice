# Build and artifact notes

The project uses Swift 6, SwiftUI, WidgetKit and Foundation. XcodeGen is a development tool only. There are no third-party runtime packages.

Generate and compile:

```sh
xcodegen generate
xcodebuild -project Rice.xcodeproj -scheme Rice -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Package the unsigned build:

```sh
mkdir -p artifacts/Payload
cp -R DerivedData/Build/Products/Release-iphoneos/Rice.app artifacts/Payload/
cd artifacts && zip -qry Rice-unsigned.ipa Payload
```

The IPA includes the widget extension. It has no signing identity or provisioning profile. Signed installation needs the app and widget extension to share the `group.app.marginallybetter.rice` App Group entitlement. The current toolchain is Xcode 26.5 with iOS 26.5 SDK, so it cannot validate iOS 27 runtime or new APIs. An Xcode 27 build and signed device checks are required before release.
