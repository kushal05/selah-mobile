import SwiftUI
import WidgetKit

// MARK: - Today's prayers widget
//
// Lists the prayers due today (published under `today_prayers`). Header opens
// /prayers/today; each row opens that prayer.

private struct PrayTodayEntry: TimelineEntry {
    let date: Date
    let items: [IndexItem]
}

private struct PrayTodayProvider: TimelineProvider {
    private func makeEntry() -> PrayTodayEntry {
        PrayTodayEntry(
            date: Date(),
            items: WidgetStore.items(WidgetStore.keyTodayPrayers, bodyKey: "title")
        )
    }

    func placeholder(in context: Context) -> PrayTodayEntry { makeEntry() }
    func getSnapshot(in context: Context, completion: @escaping (PrayTodayEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayTodayEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }
}

private struct PrayTodayView: View {
    let entry: PrayTodayEntry

    private func prayerURL(_ id: String) -> URL? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? id
        return URL(string: "selah://widget/prayer?id=\(encoded)")
    }

    private func logURL(_ id: String) -> URL? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? id
        return URL(string: "selah://widget/log-prayer?id=\(encoded)")
    }

    // How many rows fit by family is handled by SwiftUI truncation; cap to keep
    // the layout tidy.
    private var visibleItems: [IndexItem] { Array(entry.items.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Link(destination: URL(string: "selah://widget/pray-today")!) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.selahAccentSoft)
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.selahAccent)
                    }
                    .frame(width: 26, height: 26)

                    Text("Pray Today")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if !entry.items.isEmpty {
                        Text("\(entry.items.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.selahAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.selahAccentSoft))
                    }
                }
            }
            .padding(.bottom, 10)

            if visibleItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30))
                        .foregroundColor(.selahAccent.opacity(0.35))
                    Text("No prayers for today")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(visibleItems) { item in
                    HStack(spacing: 8) {
                        Link(destination: prayerURL(item.id) ?? URL(string: "selah://widget/pray-today")!) {
                            HStack(spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        Link(destination: logURL(item.id) ?? URL(string: "selah://widget/pray-today")!) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.selahAccent)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.selahAccentSoft))
                        }
                    }
                    .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}

struct PrayTodayWidget: Widget {
    let kind = "PrayTodayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayTodayProvider()) { entry in
            PrayTodayView(entry: entry)
        }
        .configurationDisplayName("Pray Today")
        .description("Today's prayers at a glance")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
