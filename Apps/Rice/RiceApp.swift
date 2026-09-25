import SwiftUI
import WidgetKit
import UniformTypeIdentifiers
import UIKit
import ImageIO

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
    @Published var wallpaperPattern: RicePattern
    @Published var wallpaperPhoto: UIImage?
    @Published var previewImages: [String: [String: UIImage]] = [:]
    @Published var pendingImages: [String: UIImage] = [:]
    @Published var focalX: Double
    @Published var focalY: Double
    private var undoStack: [RiceManifest] = []
    private var redoStack: [RiceManifest] = []
    private let store: RiceStore

    init() {
        let shared = try? RiceStore.shared()
        appGroupAvailable = shared != nil
        store = shared ?? RiceStore.localApp()
        state = (try? store.read()) ?? RiceStore.initialState()
        wallpaperPattern = RicePattern(rawValue: UserDefaults.standard.string(forKey: "wallpaperPattern") ?? "Rings") ?? .rings
        focalX = UserDefaults.standard.object(forKey: "focalX") as? Double ?? 0.5
        focalY = UserDefaults.standard.object(forKey: "focalY") as? Double ?? 0.5
        wallpaperPhoto = UIImage(contentsOfFile: Self.photoURL.path)
        if let first = state.themes.first(where: { $0.id == state.activeThemeID })?.components.first {
            loadPreviewImages(for: first)
        }
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
        previewImages.removeAll()
        let theme = activeTheme
        if let first = theme.components.first { loadPreviewImages(for: first) }
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

    func editNode(componentID: String, path: [Int], change: (inout RiceNode) -> Void) {
        var theme = activeTheme
        guard let index = theme.components.firstIndex(where: { $0.id == componentID }) else { return }
        var root = theme.components[index].root
        guard Self.applyChange(&root, path: path, change: change) else { return }
        theme.components[index].root = root
        do { try RiceValidator.validate(theme) }
        catch { self.error = error.localizedDescription; return }
        undoStack.append(activeTheme)
        redoStack.removeAll()
        replace(theme)
    }

    private static func applyChange(_ node: inout RiceNode, path: [Int], change: (inout RiceNode) -> Void) -> Bool {
        guard let index = path.first else { change(&node); return true }
        guard var children = node.children, children.indices.contains(index) else { return false }
        let changed = applyChange(&children[index], path: Array(path.dropFirst()), change: change)
        if changed { node.children = children }
        return changed
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
        do {
            let pack = try RicePack.read(Data(contentsOf: url))
            if let component = pack.manifest.components.first {
                pendingImages = RiceImages.load(component: component, theme: pack.manifest) { pack.files[$0.path] }
            } else { pendingImages = [:] }
            pendingImport = pack
        }
        catch { self.error = error.localizedDescription }
    }

    func confirmImport() {
        guard let pack = pendingImport else { return }
        do {
            try store.install(pack.manifest, files: pack.files)
            state = try store.read()
            pendingImport = nil
            pendingImages = [:]
        } catch { self.error = error.localizedDescription }
    }

    func loadPreviewImages(for component: RiceComponent) {
        guard previewImages[component.id] == nil else { return }
        let theme = activeTheme
        previewImages[component.id] = RiceImages.load(component: component, theme: theme) { asset in
            try? Data(contentsOf: store.assetURL(themeID: theme.id, path: asset.path))
        }
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
            let image = RiceArtwork.render(theme: activeTheme, size: size, icon: icon,
                pattern: icon ? .rings : wallpaperPattern, photo: icon ? nil : wallpaperPhoto,
                focalPoint: CGPoint(x: focalX, y: focalY))
            guard let data = image.pngData() else { throw RiceValidationError.invalid("Image export failed") }
            let url = FileManager.default.temporaryDirectory.appending(path: icon ? "rice-icon.png" : "rice-wallpaper.png")
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch { self.error = error.localizedDescription }
    }

    func setWallpaperPattern(_ pattern: RicePattern) {
        guard pattern != .photo || wallpaperPhoto != nil else {
            error = "Choose a photo before selecting the Photo wallpaper style."
            return
        }
        wallpaperPattern = pattern
        UserDefaults.standard.set(pattern.rawValue, forKey: "wallpaperPattern")
    }

    func setFocalPoint(x: Double? = nil, y: Double? = nil) {
        if let x { focalX = x; UserDefaults.standard.set(x, forKey: "focalX") }
        if let y { focalY = y; UserDefaults.standard.set(y, forKey: "focalY") }
    }

    func importWallpaperPhoto(_ data: Data) async {
        do {
            guard data.count <= RiceLimits.archiveBytes else { throw RiceValidationError.invalid("Photo is too large") }
            guard let sanitized = await Task.detached(priority: .userInitiated, operation: { Self.sanitizePhoto(data) }).value else {
                throw RiceValidationError.invalid("Unsupported photo")
            }
            try FileManager.default.createDirectory(at: Self.photoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sanitized.write(to: Self.photoURL, options: .atomic)
            wallpaperPhoto = UIImage(data: sanitized)
            setWallpaperPattern(.photo)
        } catch { self.error = error.localizedDescription }
    }

    func removeWallpaperPhoto() {
        try? FileManager.default.removeItem(at: Self.photoURL)
        wallpaperPhoto = nil
        setWallpaperPattern(.rings)
    }

    private static var photoURL: URL { RiceStore.localApp().root.appending(path: "artwork/wallpaper.jpg") }

    nonisolated private static func sanitizePhoto(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 4096,
                                       kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width * image.height <= 16_000_000 else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    func setSetupStep(_ id: String, done: Bool) {
        state.completedSetupSteps.removeAll(where: { $0 == id })
        if done { state.completedSetupSteps.append(id) }
        save()
    }

    func exportDiagnostics() {
        do {
            let contents: [String: Any] = [
                "appVersion": "0.1.0",
                "osVersion": UIDevice.current.systemVersion,
                "appGroupAvailable": appGroupAvailable,
                "themeCount": state.themes.count,
                "slotCount": state.slots.count,
                "lastRefreshRequested": state.lastRefreshRequested?.ISO8601Format() ?? "none",
                "lastWidgetDataRead": (try? RiceStore.shared().lastWidgetRead())?.ISO8601Format() ?? "none"
            ]
            let data = try JSONSerialization.data(withJSONObject: contents, options: [.sortedKeys, .prettyPrinted])
            let url = FileManager.default.temporaryDirectory.appending(path: "rice-diagnostics.json")
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch { self.error = error.localizedDescription }
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
