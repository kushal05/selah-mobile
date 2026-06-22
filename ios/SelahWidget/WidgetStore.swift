import Foundation

/// Reads the data the Flutter app publishes via the `home_widget` plugin into
/// the shared App Group `UserDefaults`. Keys mirror `WidgetDataPublisher` on
/// the Dart side.
///
/// IMPORTANT: `appGroupId` must match the App Group capability on BOTH the
/// Runner target and this widget extension target, and the value passed to
/// `HomeWidget.setAppGroupId(...)` in `home_widget_service.dart`.
enum WidgetStore {
    static let appGroupId = "group.in.selahapp.app"

    // Published keys (see WidgetDataPublisher).
    static let keyTodayPrayers = "today_prayers"
    static let keyNotesIndex = "notes_index"
    static let keyPrayersIndex = "prayers_index"

    private static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func string(_ key: String) -> String? {
        defaults()?.string(forKey: key)
    }

    /// Decodes a published JSON array of objects into `IndexItem`s. [bodyKey]
    /// is "preview" for notes, "content" for prayers, and unused for the
    /// today's-prayers list.
    static func items(_ key: String, bodyKey: String) -> [IndexItem] {
        guard let raw = string(key),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { obj in
            guard let id = obj["id"] as? String, !id.isEmpty else { return nil }
            let title = obj["title"] as? String ?? ""
            let body = obj[bodyKey] as? String ?? ""
            return IndexItem(id: id, title: title, body: body)
        }
    }
}

/// One published note/prayer row.
struct IndexItem: Identifiable {
    let id: String
    let title: String
    let body: String
}
