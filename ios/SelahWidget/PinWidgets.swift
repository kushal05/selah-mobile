import SwiftUI
import WidgetKit

// MARK: - Pinned note / prayer widgets
//
// SCAFFOLD NOTE: This shows the most-recently-updated note/prayer from the
// published index. The Android counterpart lets the user pick WHICH item via a
// config screen. To reach parity on iOS, convert these to
// `AppIntentConfiguration` (iOS 17+) with an `AppEntity` + `EntityQuery` that
// reads `WidgetStore.items(...)`. See README_SETUP.md.

private struct PinEntry: TimelineEntry {
    let date: Date
    let item: IndexItem?
    let emptyText: String
    let detailPath: String   // "note" | "prayer"
    let listPath: String     // "notes" | "prayers"
}

private struct PinProvider: TimelineProvider {
    let indexKey: String
    let bodyKey: String
    let emptyText: String
    let detailPath: String
    let listPath: String

    private func makeEntry() -> PinEntry {
        let items = WidgetStore.items(indexKey, bodyKey: bodyKey)
        return PinEntry(
            date: Date(),
            item: items.first,
            emptyText: emptyText,
            detailPath: detailPath,
            listPath: listPath
        )
    }

    func placeholder(in context: Context) -> PinEntry { makeEntry() }
    func getSnapshot(in context: Context, completion: @escaping (PinEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PinEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }
}

private struct PinView: View {
    let entry: PinEntry
    let systemImage: String
    let eyebrow: String

    private func detailURL(_ id: String) -> URL? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? id
        return URL(string: "selah://widget/\(entry.detailPath)?id=\(encoded)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.selahAccentSoft)
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.selahAccent)
            }
            .frame(width: 26, height: 26)

            Text(eyebrow)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.selahAccent)
            Spacer()
        }
    }

    var body: some View {
        if let item = entry.item {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .padding(.top, 10)
                Text(item.body)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(8)
                    .padding(.top, 5)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .widgetURL(detailURL(item.id))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer()
                Text(entry.emptyText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .widgetURL(URL(string: "selah://widget/\(entry.listPath)"))
        }
    }
}

struct NotePinWidget: Widget {
    let kind = "NotePinWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: PinProvider(
                indexKey: WidgetStore.keyNotesIndex,
                bodyKey: "preview",
                emptyText: "No notes yet",
                detailPath: "note",
                listPath: "notes"
            )
        ) { entry in
            PinView(entry: entry, systemImage: "doc.text.fill", eyebrow: "NOTE")
        }
        .configurationDisplayName("Pinned note")
        .description("Keep one note on your home screen")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PrayerPinWidget: Widget {
    let kind = "PrayerPinWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: PinProvider(
                indexKey: WidgetStore.keyPrayersIndex,
                bodyKey: "content",
                emptyText: "No prayers yet",
                detailPath: "prayer",
                listPath: "prayers"
            )
        ) { entry in
            PinView(entry: entry, systemImage: "heart.fill", eyebrow: "PRAYER")
        }
        .configurationDisplayName("Pinned prayer")
        .description("Keep one prayer on your home screen")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
