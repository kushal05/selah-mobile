import SwiftUI
import WidgetKit

// MARK: - Action widgets
//
// Stateless launch buttons. Tapping opens the app at a `selah://widget/...`
// URL, which `HomeWidgetService.widgetUriToAppPath` maps to a GoRouter path.

private struct ActionEntry: TimelineEntry {
    let date: Date
}

private struct ActionProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActionEntry { ActionEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (ActionEntry) -> Void) {
        completion(ActionEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActionEntry>) -> Void) {
        completion(Timeline(entries: [ActionEntry(date: Date())], policy: .never))
    }
}

private struct ActionWidgetView: View {
    let systemImage: String
    let eyebrow: String
    let label: String
    let gradient: LinearGradient
    let url: URL

    var body: some View {
        ZStack {
            gradient
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.22))
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.9))
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .widgetURL(url)
    }
}

struct CreateNoteWidget: Widget {
    let kind = "CreateNoteWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActionProvider()) { _ in
            ActionWidgetView(
                systemImage: "square.and.pencil",
                eyebrow: "CREATE",
                label: "Note",
                gradient: WidgetGradients.note,
                url: URL(string: "selah://widget/notes/new")!
            )
        }
        .configurationDisplayName("New note")
        .description("Quickly start a new note")
        .supportedFamilies([.systemSmall])
    }
}

struct CreatePrayerWidget: Widget {
    let kind = "CreatePrayerWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActionProvider()) { _ in
            ActionWidgetView(
                systemImage: "heart.fill",
                eyebrow: "CREATE",
                label: "Prayer",
                gradient: WidgetGradients.prayer,
                url: URL(string: "selah://widget/prayers/new")!
            )
        }
        .configurationDisplayName("New prayer")
        .description("Quickly add a new prayer")
        .supportedFamilies([.systemSmall])
    }
}

struct SongsShortcutWidget: Widget {
    let kind = "SongsShortcutWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActionProvider()) { _ in
            ActionWidgetView(
                systemImage: "music.note.list",
                eyebrow: "OPEN",
                label: "Songs",
                gradient: WidgetGradients.songs,
                url: URL(string: "selah://widget/songs")!
            )
        }
        .configurationDisplayName("Songs")
        .description("Open the Songs book")
        .supportedFamilies([.systemSmall])
    }
}
