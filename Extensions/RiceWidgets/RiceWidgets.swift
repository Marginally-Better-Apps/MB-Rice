import AppIntents
import SwiftUI
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
    let assetRoot: URL?
}

struct RiceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RiceEntry { fallback() }
    func snapshot(for configuration: SelectSlotIntent, in context: Context) async -> RiceEntry { load(configuration.slot?.id) }
    func timeline(for configuration: SelectSlotIntent, in context: Context) async -> Timeline<RiceEntry> {
        Timeline(entries: [load(configuration.slot?.id)], policy: .after(Date.now.addingTimeInterval(3600)))
    }
    private func load(_ slotID: String?) -> RiceEntry {
        guard let store = try? RiceStore.shared(), let state = try? store.read(),
              let slot = state.slots.first(where: { $0.id == (slotID ?? "main-clock") }),
              let theme = state.themes.first(where: { $0.id == slot.themeID }),
              let component = theme.components.first(where: { $0.id == slot.componentID }) else { return fallback() }
        store.recordWidgetRead(.now)
        return RiceEntry(date: .now, theme: theme, component: component, assetRoot: store.root.appending(path: "themes").appending(path: theme.id))
    }
    private func fallback() -> RiceEntry {
        let theme = RicePresets.all[0]
        return RiceEntry(date: .now, theme: theme, component: theme.components[0], assetRoot: nil)
    }
}

struct RiceWidget: Widget {
    let kind = "RiceSlotWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectSlotIntent.self, provider: RiceProvider()) { entry in
            RiceComponentView(component: entry.component, theme: entry.theme, assetRoot: entry.assetRoot)
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
