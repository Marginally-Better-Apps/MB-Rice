import SwiftUI
import WidgetKit
import UniformTypeIdentifiers
import UIKit

extension UTType {
    static let ricepack = UTType(exportedAs: "app.marginallybetter.ricepack", conformingTo: .zip)
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let item: ShareItem
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@MainActor final class RiceAppModel: ObservableObject {
    @Published var state: RiceState
    @Published var error: String?
    @Published var pendingImport: RicePack?
    @Published var shareItem: ShareItem?
    @Published var appGroupAvailable: Bool
    private var undoStack: [RiceManifest] = []
    private var redoStack: [RiceManifest] = []
    private let store: RiceStore

    init() {
        let shared = try? RiceStore.shared()
        appGroupAvailable = shared != nil
        store = shared ?? RiceStore.localApp()
        state = (try? store.read()) ?? RiceStore.initialState()
    }

    var activeTheme: RiceManifest { state.themes.first(where: { $0.id == state.activeThemeID }) ?? RicePresets.all[0] }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func save() {
        state.lastRefreshRequested = .now
        do { try store.write(state) } catch { self.error = error.localizedDescription }
        WidgetCenter.shared.reloadTimelines(ofKind: "RiceSlotWidget")
    }

    func activate(_ id: String) {
        guard state.themes.contains(where: { $0.id == id }) else { return }
        state.activeThemeID = id
        let theme = activeTheme
        for index in state.slots.indices where !state.slots[index].pinned {
            if let suggested = theme.slots.first(where: { $0.role == state.slots[index].role }) {
                state.slots[index].themeID = theme.id
                state.slots[index].componentID = suggested.component
            }
        }
        save()
    }

    func editToken(_ key: String, color: Color) {
        var theme = activeTheme
        undoStack.append(theme)
        redoStack.removeAll()
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        theme.tokens[key] = String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        replace(theme)
    }

    func editText(_ text: String) {
        var theme = activeTheme
        guard let component = theme.components.firstIndex(where: { $0.id == "main" }),
              var children = theme.components[component].root.children, !children.isEmpty else { return }
        undoStack.append(theme)
        redoStack.removeAll()
        children[0].text = String(text.prefix(500))
        theme.components[component].root.children = children
        replace(theme)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(activeTheme)
        replace(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(activeTheme)
        replace(next)
    }

    func duplicate() {
        var theme = activeTheme
        theme.id = "custom-\(UUID().uuidString.lowercased())"
        theme.name += " Copy"
        theme.author = "You"
        state.themes.append(theme)
        activate(theme.id)
    }

    private func replace(_ theme: RiceManifest) {
        guard let index = state.themes.firstIndex(where: { $0.id == theme.id }) else { return }
        state.themes[index] = theme
        save()
    }

    func prepareImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { pendingImport = try RicePack.read(Data(contentsOf: url)) }
        catch { self.error = error.localizedDescription }
    }

    func confirmImport() {
        guard let pack = pendingImport else { return }
        do {
            try store.install(pack.manifest, files: pack.files)
            state = try store.read()
            pendingImport = nil
        } catch { self.error = error.localizedDescription }
    }

    func exportTheme() {
        do {
            let theme = activeTheme
            var files: [String: Data] = [:]
            for asset in theme.assets {
                let url = store.assetURL(themeID: theme.id, path: asset.path)
                files[asset.path] = try Data(contentsOf: url)
            }
            if theme.license == "LICENSES/MIT.txt" { files[theme.license] = Data(RicePack.licenseText.utf8) }
            else { files[theme.license] = try Data(contentsOf: store.assetURL(themeID: theme.id, path: theme.license)) }
            let data = try RicePack(manifest: theme, files: files).archive()
            let url = FileManager.default.temporaryDirectory.appending(path: "\(theme.id).ricepack")
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch { self.error = error.localizedDescription }
    }

    func exportArtwork(icon: Bool) {
        do {
            let size = icon ? CGSize(width: 1024, height: 1024) : CGSize(width: 1179, height: 2556)
            let image = RiceArtwork.render(theme: activeTheme, size: size, icon: icon)
            guard let data = image.pngData() else { throw RiceValidationError.invalid("Image export failed") }
            let url = FileManager.default.temporaryDirectory.appending(path: icon ? "rice-icon.png" : "rice-wallpaper.png")
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch { self.error = error.localizedDescription }
    }

    func setSetupStep(_ id: String, done: Bool) {
        state.completedSetupSteps.removeAll(where: { $0 == id })
        if done { state.completedSetupSteps.append(id) }
        save()
    }
}

@main struct RiceApp: App {
    @StateObject private var model = RiceAppModel()
    var body: some Scene {
        WindowGroup {
            RiceRootView().environmentObject(model)
        }
    }
}
