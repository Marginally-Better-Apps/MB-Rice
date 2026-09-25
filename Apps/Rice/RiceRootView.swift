import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

private struct RiceLayerRow: Identifiable {
    let path: [Int]
    let node: RiceNode
    let level: Int
    var id: String { path.map { String($0) }.joined(separator: ".") }
}

struct RiceRootView: View {
    @EnvironmentObject private var model: RiceAppModel
    @State private var importing = false
    @State private var showingExportAudit = false
    @State private var selectedWallpaperPhoto: PhotosPickerItem?
    @State private var selectedComponentID = "main"
    @State private var selectedNodePath: [Int] = []
    @State private var librarySearch = ""

    var body: some View {
        TabView {
            NavigationStack { library }.tabItem { Label("Library", systemImage: "square.grid.2x2") }
            NavigationStack { studio }.tabItem { Label("Studio", systemImage: "paintpalette") }
            NavigationStack { setup }.tabItem { Label("Setup", systemImage: "checklist") }
            NavigationStack { settings }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.ricepack, .zip], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { model.prepareImport(url) }
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .sheet(isPresented: Binding(get: { model.pendingImport != nil }, set: { if !$0 { model.pendingImport = nil } })) { importPreview }
        .sheet(item: $model.shareItem) { ShareSheet(item: $0) }
        .confirmationDialog("Share this theme?", isPresented: $showingExportAudit) {
            Button("Export ricepack") { model.exportTheme() }
        } message: {
            Text("Includes \(model.activeTheme.components.count) public components, \(model.activeTheme.assets.count) declared assets, palette colors and license text. Review captions before sharing. No device bindings or credentials are included.")
        }
        .alert("Rice", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: selectedWallpaperPhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw RiceValidationError.invalid("Could not read the selected photo") }
                    await model.importWallpaperPhoto(data)
                } catch { model.error = error.localizedDescription }
            }
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your iPhone, your way").font(.largeTitle.bold())
                    Text("Create and share matching themes offline.").foregroundStyle(.secondary)
                }
                preview(theme: model.activeTheme, component: model.activeTheme.components[0], images: model.previewImages[model.activeTheme.components[0].id] ?? [:], height: 210)
                HStack {
                    Button("Import theme", systemImage: "square.and.arrow.down") { importing = true }
                    Spacer()
                    Button("Share theme", systemImage: "square.and.arrow.up") { showingExportAudit = true }
                }.buttonStyle(.bordered)
                Text("Themes").font(.title2.bold())
                ForEach(model.state.themes.filter { librarySearch.isEmpty || $0.name.localizedCaseInsensitiveContains(librarySearch) || $0.author.localizedCaseInsensitiveContains(librarySearch) }) { theme in
                    Button { model.activate(theme.id) } label: {
                        HStack {
                            Circle().fill(Color(hex: theme.tokens["accent"] ?? "#FFFFFF") ?? .white).frame(width: 28, height: 28)
                            VStack(alignment: .leading) {
                                Text(theme.name).foregroundStyle(.primary)
                                Text("by \(theme.author)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.state.activeThemeID == theme.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                    }.accessibilityLabel("Activate \(theme.name)")
                    Divider()
                }
            }.padding()
        }.navigationTitle("Rice").searchable(text: $librarySearch, prompt: "Find themes")
    }

    private var studio: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(model.activeTheme.name) preview").font(.title2.bold())
                preview(theme: model.activeTheme, component: studioComponent, images: model.previewImages[studioComponent.id] ?? [:], height: 200)
                HStack {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo)
                    Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo)
                    Spacer()
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate() }
                }.buttonStyle(.bordered)
                Text("Palette").font(.headline)
                ForEach(["background", "foreground", "accent", "secondary"], id: \.self) { key in
                    ColorPicker(key.capitalized, selection: Binding(get: {
                        Color(hex: model.activeTheme.tokens[key] ?? "#FFFFFF") ?? .white
                    }, set: { model.editToken(key, color: $0) }))
                }
                if let ratio = RiceContrast.ratio(model.activeTheme.tokens["foreground"] ?? "", model.activeTheme.tokens["background"] ?? ""), ratio < 4.5 {
                    Label(String(format: "Text contrast is %.1f:1. Aim for at least 4.5:1.", ratio), systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("Widget layers").font(.headline)
                Picker("Component", selection: $selectedComponentID) {
                    ForEach(model.activeTheme.components.filter { $0.kind == "widget" }) { component in
                        Text(component.name).tag(component.id)
                    }
                }.pickerStyle(.menu)
                ForEach(studioLayers) { layer in
                    Button { selectedNodePath = layer.path } label: {
                        HStack {
                            Image(systemName: layer.node.type == "stack" ? "square.stack.3d.up" : layer.node.type == "clock" ? "clock" : "text.alignleft")
                            Text(layer.node.type.capitalized)
                            if let text = layer.node.text { Text(text).lineLimit(1).foregroundStyle(.secondary) }
                            Spacer()
                            if selectedNodePath == layer.path { Image(systemName: "checkmark") }
                        }.padding(.vertical, 6).padding(.leading, CGFloat(layer.level) * 16)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Select \(layer.node.type) layer \(layer.node.text ?? "")")
                }
                if let node = selectedNode { nodeInspector(node) }
                Text("Artwork").font(.headline)
                wallpaperStudio
                Button("Export icon image", systemImage: "app") { model.exportArtwork(icon: true) }.buttonStyle(.bordered)
                Text("The icon export matches the theme palette. iOS shortcut icons and wallpaper placement are completed in Setup.").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Studio")
            .onChange(of: model.activeTheme.id) { _, _ in
                selectedComponentID = model.activeTheme.components.first?.id ?? "main"
                selectedNodePath = []
            }
            .onChange(of: selectedComponentID) { _, _ in model.loadPreviewImages(for: studioComponent) }
    }

    private var studioComponent: RiceComponent {
        model.activeTheme.components.first(where: { $0.id == selectedComponentID }) ?? model.activeTheme.components[0]
    }

    private var selectedNode: RiceNode? {
        var node = studioComponent.root
        for index in selectedNodePath {
            guard let children = node.children, children.indices.contains(index) else { return nil }
            node = children[index]
        }
        return node
    }

    private var studioLayers: [RiceLayerRow] {
        var rows: [RiceLayerRow] = []
        func visit(_ node: RiceNode, path: [Int], level: Int) {
            rows.append(RiceLayerRow(path: path, node: node, level: level))
            for (index, child) in (node.children ?? []).enumerated() {
                visit(child, path: path + [index], level: level + 1)
            }
        }
        visit(studioComponent.root, path: [], level: 0)
        return rows
    }

    private func nodeInspector(_ node: RiceNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected layer").font(.headline)
            if node.type == "text" {
                TextField("Text", text: Binding(get: { selectedNode?.text ?? "" }, set: { value in
                    model.editNode(componentID: studioComponent.id, path: selectedNodePath) { $0.text = value }
                })).textFieldStyle(.roundedBorder)
            }
            if node.type == "clock" {
                Picker("Display", selection: Binding(get: { selectedNode?.text ?? "time" }, set: { value in
                    model.editNode(componentID: studioComponent.id, path: selectedNodePath) { $0.text = value }
                })) {
                    Text("Time").tag("time")
                    Text("Date").tag("date")
                    Text("Weekday").tag("weekday")
                }.pickerStyle(.segmented)
            }
            if node.type == "stack" {
                Picker("Layout", selection: Binding(get: { selectedNode?.axis ?? "vertical" }, set: { value in
                    model.editNode(componentID: studioComponent.id, path: selectedNodePath) { $0.axis = value }
                })) {
                    Text("Vertical").tag("vertical")
                    Text("Horizontal").tag("horizontal")
                    Text("Overlay").tag("overlay")
                }.pickerStyle(.menu)
                Slider(value: Binding(get: { selectedNode?.spacing ?? 4 }, set: { value in
                    model.editNode(componentID: studioComponent.id, path: selectedNodePath) { $0.spacing = value }
                }), in: 0...40) { Text("Spacing") }
            }
            if ["text", "clock", "shape", "gradient"].contains(node.type) {
                Picker("Color token", selection: Binding(get: { selectedNode?.token ?? "foreground" }, set: { value in
                    model.editNode(componentID: studioComponent.id, path: selectedNodePath) { $0.token = value }
                })) {
                    ForEach(model.activeTheme.tokens.keys.sorted(), id: \.self) { token in Text(token.capitalized).tag(token) }
                }.pickerStyle(.menu)
            }
            if ["text", "clock"].contains(node.type) {
                Slider(value: Binding(get: { selectedNode?.fontSize ?? 20 }, set: { value in
                    model.editNode(componentID: studioComponent.id, path: selectedNodePath) { $0.fontSize = value }
                }), in: 8...80) { Text("Text size") }
            }
        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var wallpaperStudio: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Wallpaper style", selection: Binding(get: { model.wallpaperPattern }, set: { model.setWallpaperPattern($0) })) {
                ForEach(RicePattern.allCases) { pattern in Text(pattern.rawValue).tag(pattern) }
            }.pickerStyle(.menu)
            HStack {
                PhotosPicker(selection: $selectedWallpaperPhoto, matching: .images) { Label("Choose photo", systemImage: "photo.on.rectangle") }
                if model.wallpaperPhoto != nil { Button("Remove photo", role: .destructive) { model.removeWallpaperPhoto() } }
            }.buttonStyle(.bordered)
            if model.wallpaperPattern == .photo && model.wallpaperPhoto != nil {
                VStack {
                    Slider(value: Binding(get: { model.focalX }, set: { model.setFocalPoint(x: $0) }), in: 0...1) { Text("Horizontal focus") }
                    Slider(value: Binding(get: { model.focalY }, set: { model.setFocalPoint(y: $0) }), in: 0...1) { Text("Vertical focus") }
                }
            }
            HStack {
                Spacer()
                Image(uiImage: RiceArtwork.render(theme: model.activeTheme, size: CGSize(width: 280, height: 600), icon: false,
                    pattern: model.wallpaperPattern, photo: model.wallpaperPhoto,
                    focalPoint: CGPoint(x: model.focalX, y: model.focalY)))
                    .resizable().scaledToFill().frame(width: 210, height: 450).clipped()
                    .overlay(alignment: .top) {
                        VStack(spacing: 2) {
                            Text("Preview").font(.caption2.bold())
                            Text("9:41").font(.system(size: 42, weight: .semibold, design: .rounded))
                            Text("Monday, June 1").font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 25)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .accessibilityLabel("Wallpaper preview with sample clock overlay")
                Spacer()
            }
            Button("Export wallpaper image", systemImage: "square.and.arrow.up") { model.exportArtwork(icon: false) }
                .buttonStyle(.borderedProminent)
            Text("The sample clock appears only in the preview. Selected photos stay in app storage and are excluded from ricepack exports.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var setup: some View {
        List {
            Section {
                Text("Active: \(model.activeTheme.name)")
                Text("Rice updates its own slot bindings. iOS owns widget placement, wallpaper selection and Home Screen shortcuts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Widget slots") {
                ForEach(model.state.slots) { slot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(slot.name)
                            Text(slot.pinned ? "Pinned to \(slot.themeID)" : "Follows active theme").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Pin", isOn: Binding(get: { model.state.slots.first(where: { $0.id == slot.id })?.pinned ?? false }, set: { value in
                            if let index = model.state.slots.firstIndex(where: { $0.id == slot.id }) {
                                model.state.slots[index].pinned = value
                                if value { model.save() } else { model.activate(model.state.activeThemeID) }
                            }
                        })).labelsHidden()
                    }
                }
            }
            Section("Finish in iOS") {
                setupRow(id: "widget", title: "Add a Rice widget", detail: "Long press the Home Screen, tap Edit, then Add Widget. Pick Rice and choose a slot.")
                setupRow(id: "wallpaper", title: "Set your wallpaper", detail: "Export in Studio, save the image, then use Settings > Wallpaper > Add New Wallpaper.")
                setupRow(id: "icon", title: "Create an icon shortcut", detail: "Export the icon. In Shortcuts, create Open App for your chosen app, then Add to Home Screen with the image. This launcher is separate from the app's native icon and badges.")
            }
            Section {
                Text("Checked steps are your report. Rice cannot verify Home Screen changes made by iOS.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Set up theme")
    }

    private func setupRow(id: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(title, isOn: Binding(get: { model.state.completedSetupSteps.contains(id) }, set: { model.setSetupStep(id, done: $0) }))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }

    private var settings: some View {
        List {
            Section("Privacy") {
                Text("Rice works offline. It has no account, analytics or network provider in this build.")
                Text("Imported packs are checked locally. Import and preview do not make network requests.")
            }
            Section("Format") {
                Text("Ricepack schema 1, development revision 0.1")
                Text("ZIP entries must be stored without compression. PNG, JPEG and static WebP artwork is accepted when declared and hashed.")
            }
            Section("Diagnostics") {
                Text(model.appGroupAvailable ? "App Group storage: available" : "App Group storage: unavailable. The app saves locally; widgets use a sample until signed App Group access works.")
                Text("Last widget refresh request: \(model.state.lastRefreshRequested?.formatted() ?? "none")")
                Text("Last widget data read: \(((try? RiceStore.shared().lastWidgetRead()) ?? nil)?.formatted() ?? "none")")
                Text("A request does not prove the system displayed a new widget.")
                Button("Export diagnostics", systemImage: "square.and.arrow.up") { model.exportDiagnostics() }
            }
            Section("About") {
                Link("Source code", destination: URL(string: "https://github.com/Marginally-Better-Apps/MB-Rice")!)
                Text("Code and built-in artwork: MIT")
            }
        }.navigationTitle("Settings")
    }

    private var importPreview: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let pack = model.pendingImport {
                    Text(pack.manifest.name).font(.title.bold())
                    Text("by \(pack.manifest.author)")
                    Text("\(pack.manifest.components.count) components • \(pack.manifest.assets.count) assets")
                    Text("License: \(pack.manifest.license)")
                    Text("No permissions or network access are needed to preview this pack.").font(.footnote)
                    if let component = pack.manifest.components.first { preview(theme: pack.manifest, component: component, images: model.pendingImages, height: 190) }
                    Spacer()
                    Button("Import theme") { model.confirmImport() }.buttonStyle(.borderedProminent)
                }
            }.padding().navigationTitle("Review import")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { model.pendingImport = nil } } }
        }
    }

    private func preview(theme: RiceManifest, component: RiceComponent, images: [String: UIImage], height: CGFloat) -> some View {
        RiceComponentView(component: component, theme: theme, images: images)
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                Text("Preview").font(.caption2.bold()).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(10)
            }
            .accessibilityLabel("Preview of \(theme.name) \(component.name)")
    }
}
