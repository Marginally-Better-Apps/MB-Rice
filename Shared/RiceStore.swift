import Foundation

enum RiceStorageError: Error, LocalizedError {
    case unavailable
    var errorDescription: String? { "Shared storage is unavailable. Check App Group signing." }
}

struct RiceStore {
    static let groupID = "group.app.marginallybetter.rice"
    let root: URL

    static func shared() throws -> RiceStore {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { throw RiceStorageError.unavailable }
        return RiceStore(root: root)
    }

    static func localApp() -> RiceStore {
        RiceStore(root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Rice"))
    }

    private var stateURL: URL { root.appending(path: "state.json") }
    private var widgetReadURL: URL { root.appending(path: "widget-read.txt") }

    func read() throws -> RiceState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return Self.initialState() }
        return try JSONDecoder().decode(RiceState.self, from: Data(contentsOf: stateURL))
    }

    func write(_ state: RiceState) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    func recordWidgetRead(_ date: Date) {
        try? Data(String(date.timeIntervalSince1970).utf8).write(to: widgetReadURL, options: .atomic)
    }

    func lastWidgetRead() -> Date? {
        guard let data = try? Data(contentsOf: widgetReadURL), let text = String(data: data, encoding: .utf8), let seconds = Double(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func initialState() -> RiceState {
        let theme = RicePresets.all[0]
        let slots = [
            RiceSlot(id: "main-clock", name: "Main Clock", role: "main-clock", pinned: false, themeID: theme.id, componentID: "main"),
            RiceSlot(id: "daily-card", name: "Daily Card", role: "daily-card", pinned: false, themeID: theme.id, componentID: "note")
        ]
        return RiceState(themes: RicePresets.all, activeThemeID: theme.id, slots: slots, completedSetupSteps: [], lastRefreshRequested: nil, lastWidgetRead: nil)
    }

    func assetURL(themeID: String, path: String) -> URL {
        root.appending(path: "themes").appending(path: themeID).appending(path: path)
    }

    func install(_ manifest: RiceManifest, files: [String: Data]) throws {
        try RiceValidator.validate(manifest)
        var state = try read()
        guard !state.themes.contains(where: { $0.id == manifest.id }) else { throw RiceValidationError.invalid("Theme ID already exists. Duplicate the theme with a new ID before importing.") }
        let themesRoot = root.appending(path: "themes")
        let revision = themesRoot.appending(path: manifest.id)
        guard !FileManager.default.fileExists(atPath: revision.path) else { throw RiceValidationError.invalid("Theme files already exist") }
        let staging = themesRoot.appending(path: ".incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for asset in manifest.assets {
            guard let data = files[asset.path] else { throw RiceValidationError.invalid("Asset missing") }
            let destination = staging.appending(path: asset.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        for license in Set([manifest.license] + manifest.assets.map(\.license)) {
            guard RiceValidator.safePath(license), let data = files[license] else { throw RiceValidationError.invalid("License file missing") }
            let destination = staging.appending(path: license)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        try FileManager.default.moveItem(at: staging, to: revision)
        state.themes.append(manifest)
        try write(state)
    }
}
