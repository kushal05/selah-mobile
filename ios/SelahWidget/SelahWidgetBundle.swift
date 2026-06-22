import SwiftUI
import WidgetKit

/// Entry point for the Selah WidgetKit extension. Lists every widget the
/// extension provides. The `kind` strings here match the `iOSName` values used
/// in `WidgetDataPublisher.updateWidget(...)` on the Dart side.
@main
struct SelahWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        CreateNoteWidget()
        CreatePrayerWidget()
        SongsShortcutWidget()
        NotePinWidget()
        PrayerPinWidget()
        PrayTodayWidget()
    }
}
