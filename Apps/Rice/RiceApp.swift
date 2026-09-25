import SwiftUI
import WidgetKit
import UniformTypeIdentifiers
import UIKit
import ImageIO
import CryptoKit

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
    @Published var draftTheme: RiceManifest
    @Published var error: String?
    @Published var pendingImport: RicePack?
    @Published var shareItem: ShareItem?
    @Published var appGroupAvailable: Bool
    @Published var placedWidgetCount: Int?
    @Published var lastWidgetRead: Date?
    @Published var wallpaperPattern: RicePattern
    @Published var wallpaperPhoto: UIImage?
    @Published var previewImages: [String: [String: UIImage]] = [:]
    @Published var pendingImages: [String: UIImage] = [:]
    @Published var focalX: Double
    @Published var focalY: Double
    private var undoStack: [RiceManifest] = []
    private var redoStack: [RiceManifest] = []
    private var draftAssetFiles: [String: Data] = [:]
    private let store: RiceStore

    init() {
        let local = RiceStore.localApp()
        let shared = try? RiceStore.shared()
        if let shared, (try? shared.migrateIfEmpty(from: local)) != nil,
           (try? shared.initializeIfNeeded()) != nil {
            store = shared
            appGroupAvailable = true
        } else {
            store = local
            appGroupAvailable = false
        }
        let loadedState = (try? store.read()) ?? RiceStore.initialState()
        state = loadedState
        draftTheme = loadedState.themes.first(where: { $0.id == loadedState.activeThemeID }) ?? RicePresets.all[0]
        placedWidgetCount = nil
        lastWidgetRead = store.lastWidgetRead()
        wallpaperPattern = RicePattern(rawValue: UserDefaults.standard.string(forKey: "wallpaperPattern") ?? "Rings") ?? .rings
        focalX = UserDefaults.standard.object(forKey: "focalX") as? Double ?? 0.5
        focalY = UserDefaults.standard.object(forKey: "focalY") as? Double ?? 0.5
        wallpaperPhoto = UIImage(contentsOfFile: Self.photoURL.path)
        if let first = draftTheme.components.first {
            loadPreviewImages(for: first)
        }
        refreshWidgetStatus()
    }

    var activeTheme: RiceManifest { state.themes.first(where: { $0.id == state.activeThemeID }) ?? RicePresets.all[0] }
    var savedThemes: [RiceManifest] { state.themes.filter { $0.id.hasPrefix("custom-") } }
    var importedThemes: [RiceManifest] { state.themes.filter { theme in !RicePresets.all.contains(where: { $0.id == theme.id }) && !theme.id.hasPrefix("custom-") } }
    var draftIsSaved: Bool { state.themes.first(where: { $0.id == draftTheme.id }) == draftTheme && draftTheme.id.hasPrefix("custom-") }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @discardableResult func save() -> Bool {
        let previousRefresh = state.lastRefreshRequested
        if appGroupAvailable { state.lastRefreshRequested = .now }
        do { try store.write(state) }
        catch {
            state.lastRefreshRequested = previousRefresh
            self.error = error.localizedDescription
            return false
        }
        if appGroupAvailable { WidgetCenter.shared.reloadTimelines(ofKind: "RiceSlotWidget") }
        refreshWidgetStatus()
        return true
    }

    func refreshWidgetStatus() {
        lastWidgetRead = store.lastWidgetRead()
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            let count = try? result.get().filter { $0.kind == "RiceSlotWidget" }.count
            Task { @MainActor [weak self] in
                self?.placedWidgetCount = count
                self?.lastWidgetRead = self?.store.lastWidgetRead()
            }
        }
    }

    func activate(_ id: String) {
        guard state.themes.contains(where: { $0.id == id }) else { return }
        let previous = state
        state.activeThemeID = id
        let theme = activeTheme
        for index in state.slots.indices where !state.slots[index].pinned {
            if let suggested = theme.slots.first(where: { $0.role == state.slots[index].role }) {
                state.slots[index].themeID = theme.id
                state.slots[index].componentID = suggested.component
            }
        }
        if !save() { state = previous; return }
        if !appGroupAvailable {
            error = "Your theme is saved, but this installation cannot update Home Screen widgets. Open Set Up to see what needs fixing."
        }
    }

    func editToken(_ key: String, color: Color) {
        var theme = draftTheme
        undoStack.append(theme)
        redoStack.removeAll()
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        theme.tokens[key] = String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        replace(theme)
    }

    func editText(_ text: String) {
        var theme = draftTheme
        guard let component = theme.components.firstIndex(where: { $0.id == "main" }),
              var children = theme.components[component].root.children, !children.isEmpty else { return }
        undoStack.append(theme)
        redoStack.removeAll()
        children[0].text = String(text.prefix(500))
        theme.components[component].root.children = children
        replace(theme)
    }

    func editNode(componentID: String, path: [Int], change: (inout RiceNode) -> Void) {
        var theme = draftTheme
        guard let index = theme.components.firstIndex(where: { $0.id == componentID }) else { return }
        var root = theme.components[index].root
        guard Self.applyChange(&root, path: path, change: change) else { return }
        theme.components[index].root = root
        do { try RiceValidator.validate(theme) }
        catch { self.error = error.localizedDescription; return }
        undoStack.append(draftTheme)
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
        redoStack.append(draftTheme)
        replace(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(draftTheme)
        replace(next)
    }

    func duplicate() {
        loadDraft(activeTheme.id)
        saveDraft(name: "\(activeTheme.name) Copy")
    }

    private func replace(_ theme: RiceManifest) {
        draftTheme = theme
    }

    func loadDraft(_ id: String) {
        guard let theme = state.themes.first(where: { $0.id == id }) else { return }
        draftTheme = theme
        undoStack.removeAll()
        redoStack.removeAll()
        draftAssetFiles.removeAll()
        previewImages.removeAll()
        if let first = theme.components.first { loadPreviewImages(for: first) }
    }

    func saveDraft(name: String? = nil) {
        do {
            var theme = draftTheme
            if let name { theme.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
            guard !theme.name.isEmpty else { throw RiceValidationError.invalid("Give your theme a name.") }
            let isExistingCopy = theme.id.hasPrefix("custom-") && state.themes.contains(where: { $0.id == theme.id })
            if !isExistingCopy {
                if name == nil { theme.name = String("My \(theme.name)".prefix(80)) }
                let source = state.themes.first(where: { $0.id == draftTheme.id }) ?? draftTheme
                var files = try store.files(for: source)
                files.merge(draftAssetFiles) { _, new in new }
                theme.id = "custom-\(UUID().uuidString.lowercased())"
                if RicePresets.all.contains(where: { $0.id == draftTheme.id }) { theme.author = "You" }
                try RiceValidator.validate(theme)
                try store.install(theme, files: files)
                state = try store.read()
            } else {
                try RiceValidator.validate(theme)
                try store.writeFiles(themeID: theme.id, files: draftAssetFiles)
                guard let index = state.themes.firstIndex(where: { $0.id == theme.id }) else { return }
                let previous = state
                state.themes[index] = theme
                guard save() else { state = previous; return }
            }
            draftTheme = theme
            draftAssetFiles.removeAll()
        } catch { self.error = error.localizedDescription }
    }

    func applyDraft() {
        if state.themes.first(where: { $0.id == draftTheme.id }) != draftTheme {
            if !draftIsSaved { saveDraft() }
            guard draftIsSaved else { return }
        }
        activate(draftTheme.id)
    }

    func makeCanvas(componentID: String) {
        guard let component = draftTheme.components.first(where: { $0.id == componentID }), component.root.type != "canvas" else { return }
        var leaves: [RiceNode] = []
        func collect(_ node: RiceNode) {
            if node.type == "stack" {
                for child in node.children ?? [] { collect(child) }
            } else if node.type != "spacer" { leaves.append(node) }
        }
        collect(component.root)
        let initial = leaves.count <= 32 ? leaves : (component.root.children ?? [component.root])
        editNode(componentID: componentID, path: []) { root in
            root = RiceNode(type: "canvas", children: initial.enumerated().map { index, original in
                var child = original
                child.x = 0.5
                child.y = min(0.16 + Double(index) * (0.72 / Double(max(initial.count - 1, 1))), 0.88)
                child.width = child.type == "clock" ? 0.84 : 0.7
                child.height = initial.count > 4 ? 0.14 : 0.22
                return child
            })
        }
    }

    func addWidgetPhoto(_ data: Data, componentID: String) async {
        do {
            guard data.count <= RiceLimits.archiveBytes else { throw RiceValidationError.invalid("Photo is too large") }
            guard let sanitized = await Task.detached(priority: .userInitiated, operation: { Self.sanitizePhoto(data) }).value else {
                throw RiceValidationError.invalid("Could not use this photo")
            }
            let id = "photo-\(UUID().uuidString.lowercased())"
            let path = "assets/\(id).jpg"
            let license = "LICENSES/User-Photo.txt"
            let hash = SHA256.hash(data: sanitized).map { String(format: "%02x", $0) }.joined()
            var theme = draftTheme
            guard let componentIndex = theme.components.firstIndex(where: { $0.id == componentID }),
                  theme.components[componentIndex].root.type == "canvas" else { return }
            theme.assets.append(RiceAsset(id: id, path: path, mimeType: "image/jpeg", length: sanitized.count,
                                          sha256: hash, license: license))
            var imageNode = RiceNode(type: "image", asset: id, x: 0.5, y: 0.5, width: 0.65, height: 0.55)
            imageNode.radius = 0
            theme.components[componentIndex].root.children = (theme.components[componentIndex].root.children ?? []) + [imageNode]
            try RiceValidator.validate(theme)
            undoStack.append(draftTheme)
            redoStack.removeAll()
            draftAssetFiles[path] = sanitized
            draftAssetFiles[license] = Data("Photo supplied by the theme creator. Rights remain with its owner.\n".utf8)
            draftTheme = theme
            previewImages[componentID, default: [:]][id] = UIImage(data: sanitized)
        } catch { self.error = error.localizedDescription }
    }

    func addElement(componentID: String, type: String) {
        let count = draftTheme.components.first(where: { $0.id == componentID })?.root.children?.count ?? 0
        guard count < 32 else { error = "This widget has too many elements."; return }
        editNode(componentID: componentID, path: []) { root in
            guard root.type == "canvas" else { return }
            var node = RiceNode(type: type, token: "foreground", x: 0.5, y: 0.5, width: 0.52, height: 0.22)
            if type == "text" { node.text = "Your text"; node.fontSize = 24 }
            if type == "clock" { node.text = "time"; node.fontSize = 40; node.width = 0.72 }
            if type == "shape" { node.token = "accent"; node.radius = 16; node.height = 0.18 }
            if type == "symbol" { node.text = "star.fill"; node.token = "accent"; node.fontSize = 44; node.width = 0.3; node.height = 0.28 }
            if type == "gradient" { node.token = "accent"; node.width = 0.7; node.height = 0.5 }
            root.children = (root.children ?? []) + [node]
        }
    }

    func removeElement(componentID: String, index: Int) {
        editNode(componentID: componentID, path: []) { root in
            guard root.type == "canvas", root.children?.indices.contains(index) == true else { return }
            root.children?.remove(at: index)
        }
    }

    func moveElement(componentID: String, index: Int, x: Double, y: Double) {
        editNode(componentID: componentID, path: [index]) { node in
            let halfWidth = (node.width ?? 0.8) / 2
            let halfHeight = (node.height ?? 0.2) / 2
            node.x = min(max(x, halfWidth), 1 - halfWidth)
            node.y = min(max(y, halfHeight), 1 - halfHeight)
        }
    }

    func reorderElement(componentID: String, index: Int, direction: Int) {
        editNode(componentID: componentID, path: []) { root in
            guard var children = root.children, children.indices.contains(index),
                  children.indices.contains(index + direction) else { return }
            children.swapAt(index, index + direction)
            root.children = children
        }
    }

    func images(for theme: RiceManifest, component: RiceComponent) -> [String: UIImage] {
        RiceImages.load(component: component, theme: theme) { asset in
            try? Data(contentsOf: store.assetURL(themeID: theme.id, path: asset.path))
        }
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
        let theme = draftTheme
        previewImages[component.id] = RiceImages.load(component: component, theme: theme) { asset in
            draftAssetFiles[asset.path] ?? (try? Data(contentsOf: store.assetURL(themeID: theme.id, path: asset.path)))
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
            let image = RiceArtwork.render(theme: draftTheme, size: size, icon: icon,
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
