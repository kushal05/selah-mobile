# Selah iOS Widget — Xcode setup

These Swift sources, the `Info.plist`, and the entitlements are a **scaffold**.
A WidgetKit extension target cannot be added safely by editing `project.pbxproj`
by hand, so the steps below must be run **once on a Mac with Xcode**. After that,
the widgets build and run alongside the Flutter app and read the data the Dart
`WidgetDataPublisher` writes to the shared App Group.

## What's already done (cross-platform, committed)

- Dart `HomeWidgetService` calls `HomeWidget.setAppGroupId("group.in.selahapp.app")`
  and routes `selah://widget/...` taps to GoRouter.
- `WidgetDataPublisher` writes `today_prayers`, `notes_index`, `prayers_index`
  and calls `HomeWidget.updateWidget(iOSName: …)` for `NotePinWidget`,
  `PrayerPinWidget`, `PrayTodayWidget`.
- `ios/Runner/Runner.entitlements` declares App Group `group.in.selahapp.app`.
- `ios/Runner/Info.plist` registers the `selah` URL scheme.
- `home_widget` is in `pubspec.yaml` (its iOS pod is added by `pod install`).

## Steps in Xcode

1. **Open the workspace:** `open ios/Runner.xcworkspace` (run `flutter pub get`
   first so the `home_widget` pod is available).
2. **Add the target:** File ▸ New ▸ Target ▸ **Widget Extension**.
   - Product Name: `SelahWidget`.
   - Uncheck "Include Configuration Intent" (the scaffold uses
     `StaticConfiguration`).
   - Activate the scheme when prompted.
3. **Replace the generated files** with the ones in this folder. Delete the
   auto-generated `SelahWidget.swift` / bundle / `Info.plist`, then **Add Files
   to "Runner"…** and select every file in `ios/SelahWidget/`
   (`SelahWidgetBundle.swift`, `ActionWidgets.swift`, `PinWidgets.swift`,
   `PrayTodayWidget.swift`, `WidgetStore.swift`, `WidgetTheme.swift`,
   `Info.plist`, `SelahWidget.entitlements`) with **target = SelahWidget only**.
4. **Deployment target:** set the SelahWidget target's iOS Deployment Target to
   **14.0** (or higher) — WidgetKit requires it.
5. **App Group capability:** select the SelahWidget target ▸ Signing &
   Capabilities ▸ **+ Capability ▸ App Groups** ▸ enable
   `group.in.selahapp.app`. Confirm the **Runner** target has the same App Group
   enabled (its `Runner.entitlements` already lists it — just make sure the
   capability is toggled on so Xcode wires the entitlement file).
   - In Build Settings, set `CODE_SIGN_ENTITLEMENTS` for SelahWidget to
     `SelahWidget/SelahWidget.entitlements`.
6. **Build & run** the `SelahWidget` scheme on a simulator/device, then long-press
   the home screen ▸ **+** ▸ search "Selah" to add each widget.

## Verify

- Action widgets (New note / New prayer / Songs) open the right screen.
- After logging into the app once (so data is published), the Pinned and
  Pray Today widgets show content; tapping opens the entity / today screen.
- Tapping a widget cold-starts and warm-starts the app to the correct route
  (handled by `HomeWidgetService.widgetUriToAppPath`).

## Known scaffold limitation — pinned widget selection

`NotePinWidget` / `PrayerPinWidget` currently show the **most recently updated**
note/prayer (the Android versions let the user pick which one via a config
screen). To reach parity on iOS, convert them to **`AppIntentConfiguration`**
(iOS 17+): add an `AppEntity` + `EntityQuery` whose `suggestedEntities()` reads
`WidgetStore.items(WidgetStore.keyNotesIndex, bodyKey: "preview")`, and use the
selected entity's id in `widgetURL`. The data plumbing
(`notes_index` / `prayers_index`) is already published for this.
