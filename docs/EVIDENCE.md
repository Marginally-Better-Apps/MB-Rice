# Capability and test evidence

Updated 2026-09-25. "Compiled" means the source compiled with Xcode 26.5 and iOS 26.5 SDK. It does not mean iOS 27 behavior was tested.

| Capability | Source | SDK compile | Simulator | Physical iPhone | Release enabled |
| --- | --- | --- | --- | --- | --- |
| Native app and saved-theme Library | Implemented | Yes | Launched on iPhone 17 Pro Max simulator, iOS 26.5; save and reload checked | Pending | No |
| Freeform widget canvas | Implemented | Yes | Canvas validation and saved artwork tests passed; add, select, and save checked in Maestro; symbol and typography round trip passed | Pending | No |
| App Group state round trip | Implemented with local app fallback and migration | Yes | Ad hoc signed simulator install created App Group state with existing saved themes; storage migration and widget selection tests passed | User reports Shared widget storage **Unavailable** on an iOS 27 Autoloader install | No |
| Home and rectangular Lock widgets | Implemented | Yes | Pending placement test | Pending | No |
| Stable slot binding and reload request | Implemented | Yes | Shared-state slot selection test passed; visual timing test pending | Pending | No |
| Ricepack import and export | Implemented for stored ZIP | Yes | Sixteen unit tests passed on iOS 26.5, including saved canvas artwork, three sample packs, and hostile fixtures | Pending | No |
| Procedural and photo wallpaper, icon PNG export | Implemented | Yes | Procedural export unit test passed; wallpaper and icon editor screens captured; photo picker and iOS setup pending | Pending setup test | No |
| iOS 27 widget families and activity APIs | Not selected | No iOS 27 SDK | No | No | No |
| Live Activities, AlarmKit, controls, Focus | Not implemented | No | No | No | No |

Apple documents WidgetKit timeline reload requests and system scheduling in [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/). Rice records the request time and the widget extension's later data-read time. Neither timestamp proves the system displayed the new pixels. Apple documents [configurable widgets](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget) using App Entities; Rice uses a stable local slot entity. [UTType declarations](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app) describe the project-owned file type.

The P0 device gate is open. A signed iPhone test must show a real imported component in Home and Lock Screen widgets, a slot change observed after a reload request, App Group sharing, wallpaper setup, and shortcut launcher behavior. The P1 offline round trip and accessibility matrix are also open. When App Group access fails, the app saves to Documents so its editor and library remain usable; a placed widget shows a setup message. An ad hoc signed simulator installation demonstrated that a shared container can be created and populated, but Maestro stalled during its later launch flow, so this is not a visual Home Screen update test.

The user's iOS 27 Autoloader install reported **Shared widget storage: Unavailable**; its exact Rice build has not been confirmed. The installed signature or provisioning profile has not been extracted, so the exact on-phone entitlement is unverified. The local `KPAFTUKTFY.*` development profile has no App Group and fails `tools/check_widget_profiles.py` for both Rice bundle IDs. Xcode automatic signing with that team failed because this Mac has no Apple Developer account in Xcode and no explicit Rice profiles. The current Autoloader signing wrapper passes one profile for the app bundle; Rice and its widget need separate explicit profiles. This is a signing and distribution gate, not a theme-rendering test failure.

The redesigned simulator captures show [Library](captures/redesign/library-redesign.png), [Create](captures/redesign/create-redesign.png), [Widgets](captures/redesign/widgets-redesign.png), [selected and moved widget text](captures/redesign/widget-selected-redesign.png), [Wallpaper](captures/redesign/wallpaper-redesign.png), and [Icon](captures/redesign/icon-redesign.png). They show the app screens, not widget placement. Sixteen unit tests passed with `xcodebuild test` after temporarily setting deployment to 26.5 for the simulator, then restoring 27.0 in the project. The earlier Maestro save flow and editor navigation flow ran on iPhone 17 Pro Max with iOS 26.5.

The original brief included three sample pack recipes and a Python verifier as companion files, but those files were not attached. The repository contains eight original Swift presets and a new development format description. This is not a claim of parity with the missing verifier.
