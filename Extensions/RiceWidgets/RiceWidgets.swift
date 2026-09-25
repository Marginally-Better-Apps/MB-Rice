import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct SlotEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rice slot")
    static let defaultQuery = SlotQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct SlotQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SlotEntity] {
        slots().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [SlotEntity] { slots() }
    func defaultResult() async -> SlotEntity? { slots().first }
    private func slots() -> [SlotEntity] {
        let stored = (try? RiceStore.shared().read().slots) ?? RiceStore.initialState().slots
        return stored.map { SlotEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectSlotIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Rice slot"
    static let description = IntentDescription("Keep a widget in place when its theme changes.")
    @Parameter(title: "Slot") var slot: SlotEntity?
}

struct RiceEntry: TimelineEntry {
    let date: Date
    let theme: RiceManifest
    let component: RiceComponent
    let images: [String: UIImage]
}

struct RiceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RiceEntry { fallback() }
    func snapshot(for configuration: SelectSlotIntent, in context: Context) async -> RiceEntry { load(configuration.slot?.id) }
    func timeline(for configuration: SelectSlotIntent, in context: Context) async -> Timeline<RiceEntry> {
        Timeline(entries: [load(configuration.slot?.id)], policy: .after(Date.now.addingTimeInterval(3600)))
    }
    private func load(_ slotID: String?) -> RiceEntry {
        guard let store = try? RiceStore.shared(),
              let content = try? store.widgetContent(slotID: slotID ?? "main-clock") else { return setupNeeded() }
        let images = RiceImages.load(component: content.component, theme: content.theme) { asset in
            try? Data(contentsOf: store.assetURL(themeID: content.theme.id, path: asset.path))
        }
        return RiceEntry(date: .now, theme: content.theme, component: content.component, images: images)
    }
    private func fallback() -> RiceEntry {
        let theme = RicePresets.all[0]
        return RiceEntry(date: .now, theme: theme, component: theme.components[0], images: [:])
    }

    private func setupNeeded() -> RiceEntry {
        var theme = RicePresets.all[0]
        theme.components[0].root = RiceNode(type: "stack", axis: "vertical", spacing: 6, children: [
            RiceNode(type: "text", text: "Open Rice", token: "foreground", fontSize: 20),
            RiceNode(type: "text", text: "Finish widget setup", token: "accent", fontSize: 14)
        ])
        return RiceEntry(date: .now, theme: theme, component: theme.components[0], images: [:])
    }
}

struct RiceWidget: Widget {
    let kind = "RiceSlotWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectSlotIntent.self, provider: RiceProvider()) { entry in
            RiceComponentView(component: entry.component, theme: entry.theme, images: entry.images)
                .containerBackground(for: .widget) {
                    Color(hex: entry.theme.tokens[entry.component.background ?? "background"] ?? "#000000") ?? .black
                }
        }
        .configurationDisplayName("Rice slot")
        .description("A theme component that can follow your chosen slot.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

@main struct RiceWidgetBundle: WidgetBundle {
    var body: some Widget { RiceWidget() }
}
