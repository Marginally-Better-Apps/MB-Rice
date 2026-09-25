# Capability and test evidence

Updated 2026-09-25. "Compiled" means the source compiled with Xcode 26.5 and iOS 26.5 SDK. It does not mean iOS 27 behavior was tested.

| Capability | Source | SDK compile | Simulator | Physical iPhone | Release enabled |
| --- | --- | --- | --- | --- | --- |
| Native app and Library screen | Implemented | Yes | Launched and captured on iPhone 17 Pro simulator, iOS 26.5 | Pending | No |
| Scene-tree editor and contrast warning | Implemented | Yes | Studio captured; contrast unit test and Maestro UI flow passed | Pending | No |
| App Group state round trip | Implemented with local app fallback | Yes | App Group unavailable unsigned | Pending signing | No |
| Home and rectangular Lock widgets | Implemented | Yes | Pending placement test | Pending | No |
| Stable slot binding and reload request | Implemented | Yes | Pending visual timing test | Pending | No |
| Ricepack import and export | Implemented for stored ZIP | Yes | Ten unit tests passed on iOS 26.5, including three sample packs and hostile fixtures | Pending | No |
| Procedural and photo wallpaper, icon PNG export | Implemented | Yes | Procedural export unit test and Studio UI flow passed; photo picker and iOS setup pending | Pending setup test | No |
| iOS 27 widget families and activity APIs | Not selected | No iOS 27 SDK | No | No | No |
| Live Activities, AlarmKit, controls, Focus | Not implemented | No | No | No | No |

Apple documents WidgetKit timeline reload requests and system scheduling in [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/). Rice records the request time and the widget extension's later data-read time. Neither timestamp proves the system displayed the new pixels. Apple documents [configurable widgets](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget) using App Entities; Rice uses a stable local slot entity. [UTType declarations](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app) describe the project-owned file type.

The P0 device gate is open. A signed iPhone test must show a real imported component in Home and Lock Screen widgets, a slot change observed after a reload request, App Group sharing, wallpaper setup, and shortcut launcher behavior. The P1 offline round trip and accessibility matrix are also open. In an unsigned simulator build, the app saves to Documents so its editor and library remain usable; the widget shows a sample until App Group access works.

The simulator captures are [Library](captures/library-iphone17pro-ios26.5.png), [Studio](captures/studio-iphone17pro-ios26.5.png), and [wallpaper Studio](captures/wallpaper-studio-iphone17pro-ios26.5.png). They show the actual app, not widget placement. Ten unit tests passed with `xcodebuild test` after temporarily setting deployment to 26.5 for the simulator, then restoring 27.0 in the project. `maestro test --udid 58B7BF9D-29F4-4AD1-B139-903D96254038 Tests/UI/studio.yaml` passed through Studio and Setup on the iPhone 17 Pro simulator.

The original brief included three sample pack recipes and a Python verifier as companion files, but those files were not attached. The repository contains eight original Swift presets and a new development format description. This is not a claim of parity with the missing verifier.
