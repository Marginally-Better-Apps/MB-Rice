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

The IPA includes the widget extension. It has no signing identity or provisioning profile. The current toolchain is Xcode 26.5 with iOS 26.5 SDK, so it cannot validate iOS 27 runtime or new APIs. An Xcode 27 build and signed device checks are required before release.

## Device signing for widgets

The app and extension need separate, explicit App IDs under the same Apple Developer team:

- `app.marginallybetter.rice`
- `app.marginallybetter.rice.widgets`

Register `group.app.marginallybetter.rice` and enable it for both App IDs. Create a device-installable provisioning profile for each App ID with that group. [Apple's App Group guide](https://developer.apple.com/documentation/xcode/configuring-app-groups) describes the shared container and registration. The available wildcard profile does not grant the group. Check the profiles before signing:

```sh
python3 tools/check_widget_profiles.py Rice.mobileprovision RiceWidgets.mobileprovision --device-id YOUR_IPHONE_UDID
```

The checker prints only profile names and failed requirements. It does not read a signing key. With a signed build, inspect both executable entitlements and embedded profiles before installation, then verify **Settings → Diagnostics → Shared widget storage** on the iPhone.

Autoloader currently passes one provisioning profile to its Zsign Swift wrapper when it signs a whole IPA. That path cannot provide distinct explicit profiles for Rice and Rice Widgets. Until Autoloader supports extension profiles, use an Xcode-signed install with both profiles. Do not uninstall Rice to retry an unchanged IPA; that risks deleting saved themes and cannot grant a missing App Group.
