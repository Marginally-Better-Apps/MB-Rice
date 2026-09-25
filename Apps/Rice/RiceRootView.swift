import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

private enum RiceTab: Hashable { case library, create, setup, settings }

struct RiceRootView: View {
    @EnvironmentObject private var model: RiceAppModel
    @State private var tab: RiceTab = .library
    @State private var createStackID = UUID()
    @State private var importing = false
    @State private var showingSaveName = false
    @State private var saveName = ""
    @State private var selectedWallpaperPhoto: PhotosPickerItem?
    @State private var selectedWidgetPhoto: PhotosPickerItem?
    @State private var selectedComponentID = "main"
    @State private var selectedElement: Int?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { library }.tabItem { Label("Library", systemImage: "square.grid.2x2") }.tag(RiceTab.library)
            NavigationStack { create }.id(createStackID).tabItem { Label("Create", systemImage: "slider.horizontal.3") }.tag(RiceTab.create)
            NavigationStack { setup }.tabItem { Label("Set Up", systemImage: "checkmark.circle") }.tag(RiceTab.setup)
            NavigationStack { settings }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(RiceTab.settings)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.ricepack, .zip]) { result in
            if case .success(let url) = result { model.prepareImport(url) }
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .sheet(isPresented: Binding(get: { model.pendingImport != nil }, set: { if !$0 { model.pendingImport = nil } })) { importPreview }
        .sheet(item: $model.shareItem) { ShareSheet(item: $0) }
        .alert("Save to Library", isPresented: $showingSaveName) {
            TextField("Theme name", text: $saveName)
            Button("Save") { model.saveDraft(name: saveName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your theme will appear in My Themes.") }
        .alert("Rice", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: selectedWallpaperPhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw RiceValidationError.invalid("Could not read the photo") }
                    await model.importWallpaperPhoto(data)
                } catch { model.error = error.localizedDescription }
            }
        }
        .onChange(of: selectedWidgetPhoto) { _, item in
            guard let item, let componentID = studioComponent?.id else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw RiceValidationError.invalid("Could not read the photo") }
                    await model.addWidgetPhoto(data, componentID: componentID)
                    selectedElement = (studioComponent?.root.children?.count ?? 1) - 1
                    selectedWidgetPhoto = nil
                } catch { model.error = error.localizedDescription }
            }
        }
    }

    private var library: some View {
        List {
            Section("Current widgets") {
                if let component = model.activeTheme.components.first {
                    RiceComponentView(component: component, theme: model.activeTheme,
                                      images: model.images(for: model.activeTheme, component: component))
                        .frame(height: 182)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .accessibilityLabel("Current theme preview: \(model.activeTheme.name)")
                }
                HStack {
                    Text(model.activeTheme.name).font(.headline)
                    Spacer()
                    Button("Edit") { openEditor(model.activeTheme.id) }
                }
            }
            Section("My Themes") {
                if model.savedThemes.isEmpty {
                    Text("Themes you save will appear here.").foregroundStyle(.secondary)
                }
                ForEach(model.savedThemes) { theme in themeRow(theme) }
            }
            Section("Templates") {
                ForEach(RicePresets.all) { theme in themeRow(theme) }
            }
            if !model.importedThemes.isEmpty {
                Section("Imported") {
                    ForEach(model.importedThemes) { theme in themeRow(theme) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import theme", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Share current theme", systemImage: "square.and.arrow.up") { model.exportTheme() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func themeRow(_ theme: RiceManifest) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: theme.tokens["background"] ?? "#FFFFFF") ?? .white)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Color(hex: theme.tokens["accent"] ?? "#888888") ?? .gray, lineWidth: 4))
            Button { openEditor(theme.id) } label: {
                HStack {
                    Text(theme.name).foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if model.activeTheme.id == theme.id {
                Text("In use").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button("Use") { model.activate(theme.id) }.font(.subheadline)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private func openEditor(_ id: String) {
        model.loadDraft(id)
        selectedComponentID = model.draftTheme.components.first?.id ?? "main"
        selectedElement = nil
        createStackID = UUID()
        tab = .create
    }

    private var create: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.draftTheme.name).font(.title2.bold())
                    Text(model.draftIsSaved ? "Saved in Library" : "Changes to save")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let component = model.draftTheme.components.first {
                    RiceComponentView(component: component, theme: model.draftTheme,
                                      images: model.previewImages[component.id] ?? [:])
                        .frame(height: 190)
                }
                VStack(spacing: 0) {
                    editorLink("Widgets", symbol: "square.on.square", detail: "Move and edit elements", destination: AnyView(widgetEditor))
                    Divider()
                    editorLink("Wallpaper", symbol: "iphone.gen3", detail: "Choose a style or photo", destination: AnyView(wallpaperEditor))
                    Divider()
                    editorLink("Icon", symbol: "app", detail: "Make a matching image", destination: AnyView(iconEditor))
                }
            }
            .padding(20)
        }
        .navigationTitle("Create")
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    private func editorLink(_ title: String, symbol: String, detail: String, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button("Save theme") { saveCurrentTheme() }
                .buttonStyle(.bordered)
            Button("Use for widgets") { model.applyDraft() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func saveCurrentTheme() {
        if model.draftTheme.id.hasPrefix("custom-") { model.saveDraft() }
        else {
            saveName = "My \(model.draftTheme.name)"
            showingSaveName = true
        }
    }

    private var widgetEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Widget", selection: $selectedComponentID) {
                    ForEach(model.draftTheme.components.filter { $0.kind == "widget" }) { component in
                        Text(component.name).tag(component.id)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                if model.canUndo { Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.labelStyle(.iconOnly) }
                if model.canRedo { Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.labelStyle(.iconOnly) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            if let component = studioComponent {
                RiceCanvasEditor(component: component, theme: model.draftTheme,
                                 images: model.previewImages[component.id] ?? [:], selectedIndex: $selectedElement,
                                 onMove: { index, x, y in model.moveElement(componentID: component.id, index: index, x: x, y: y) })
                    .frame(height: 220)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                Divider()
                List {
                    if let index = selectedElement, let node = selectedNode {
                        Section("Selected element") {
                            if node.type == "text" {
                                TextField("Text", text: nodeTextBinding(index))
                            }
                            if node.type == "clock" {
                                Picker("Show", selection: nodeTextBinding(index)) {
                                    Text("Time").tag("time")
                                    Text("Date").tag("date")
                                    Text("Weekday").tag("weekday")
                                }
                            }
                            if ["text", "clock", "shape", "gradient"].contains(node.type) {
                                Picker("Color", selection: nodeTokenBinding(index)) {
                                    ForEach(model.draftTheme.tokens.keys.sorted(), id: \.self) { key in Text(key.capitalized).tag(key) }
                                }
                            }
                            if ["text", "clock"].contains(node.type) {
                                LabeledContent("Text size", value: "\(Int(node.fontSize ?? 20))")
                                Slider(value: nodeNumberBinding(index, \.fontSize, fallback: 20), in: 8...120)
                            }
                            if node.type == "shape" {
                                LabeledContent("Corner roundness", value: "\(Int(node.radius ?? 8))")
                                Slider(value: nodeNumberBinding(index, \.radius, fallback: 8), in: 0...50)
                            }
                            Button("Remove element", role: .destructive) {
                                model.removeElement(componentID: component.id, index: index)
                                selectedElement = nil
                            }
                        }
                        Section {
                            DisclosureGroup("Size and position") {
                                LabeledContent("Width", value: "\(Int((node.width ?? 0.8) * 100))%")
                                Slider(value: nodeNumberBinding(index, \.width, fallback: 0.8), in: 0.1...1)
                                LabeledContent("Height", value: "\(Int((node.height ?? 0.2) * 100))%")
                                Slider(value: nodeNumberBinding(index, \.height, fallback: 0.2), in: 0.05...1)
                                Button("Bring forward") { model.reorderElement(componentID: component.id, index: index, direction: 1); selectedElement = min(index + 1, (studioComponent?.root.children?.count ?? 1) - 1) }
                                Button("Send backward") { model.reorderElement(componentID: component.id, index: index, direction: -1); selectedElement = max(index - 1, 0) }
                            }
                        }
                    } else {
                        Section { Text("Tap an element to edit it. Drag it to move it.").foregroundStyle(.secondary) }
                    }
                    Section {
                        DisclosureGroup("Theme colors") {
                            ForEach(["background", "foreground", "accent", "secondary"], id: \.self) { key in
                                ColorPicker(key.capitalized, selection: Binding(get: {
                                    Color(hex: model.draftTheme.tokens[key] ?? "#FFFFFF") ?? .white
                                }, set: { model.editToken(key, color: $0) }))
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Text", systemImage: "textformat") { addElement("text") }
                    Button("Clock", systemImage: "clock") { addElement("clock") }
                    Button("Shape", systemImage: "square.fill") { addElement("shape") }
                    PhotosPicker(selection: $selectedWidgetPhoto, matching: .images) {
                        Label("Photo", systemImage: "photo")
                    }
                } label: { Label("Add element", systemImage: "plus") }
            }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear { prepareCanvas() }
        .onChange(of: selectedComponentID) { _, _ in prepareCanvas() }
    }

    private var studioComponent: RiceComponent? {
        model.draftTheme.components.first(where: { $0.id == selectedComponentID }) ?? model.draftTheme.components.first(where: { $0.kind == "widget" })
    }

    private var selectedNode: RiceNode? {
        guard let index = selectedElement, let children = studioComponent?.root.children, children.indices.contains(index) else { return nil }
        return children[index]
    }

    private func prepareCanvas() {
        guard let component = studioComponent else { return }
        model.makeCanvas(componentID: component.id)
        model.loadPreviewImages(for: component)
        selectedElement = nil
    }

    private func addElement(_ type: String) {
        guard let component = studioComponent else { return }
        model.addElement(componentID: component.id, type: type)
        selectedElement = (studioComponent?.root.children?.count ?? 1) - 1
    }

    private func nodeTextBinding(_ index: Int) -> Binding<String> {
        Binding(get: { selectedNode?.text ?? "" }, set: { value in
            guard let id = studioComponent?.id else { return }
            model.editNode(componentID: id, path: [index]) { $0.text = String(value.prefix(500)) }
        })
    }

    private func nodeTokenBinding(_ index: Int) -> Binding<String> {
        Binding(get: { selectedNode?.token ?? "foreground" }, set: { value in
            guard let id = studioComponent?.id else { return }
            model.editNode(componentID: id, path: [index]) { $0.token = value }
        })
    }

    private func nodeNumberBinding(_ index: Int, _ key: WritableKeyPath<RiceNode, Double?>, fallback: Double) -> Binding<Double> {
        Binding(get: { selectedNode?[keyPath: key] ?? fallback }, set: { value in
            guard let id = studioComponent?.id else { return }
            model.editNode(componentID: id, path: [index]) { $0[keyPath: key] = value }
        })
    }

    private var wallpaperEditor: some View {
        VStack(spacing: 0) {
            Image(uiImage: RiceArtwork.render(theme: model.draftTheme, size: CGSize(width: 280, height: 600), icon: false,
                pattern: model.wallpaperPattern, photo: model.wallpaperPhoto,
                focalPoint: CGPoint(x: model.focalX, y: model.focalY)))
                .resizable().scaledToFill().frame(width: 132, height: 284).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.vertical, 10)
                .accessibilityLabel("Wallpaper preview")
            Divider()
            List {
                Section("Style") {
                    Picker("Look", selection: Binding(get: { model.wallpaperPattern }, set: { model.setWallpaperPattern($0) })) {
                        ForEach(RicePattern.allCases) { pattern in Text(pattern.rawValue).tag(pattern) }
                    }
                }
                Section("Photo") {
                    PhotosPicker(selection: $selectedWallpaperPhoto, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                    }
                    if model.wallpaperPhoto != nil {
                        Button("Remove photo", role: .destructive) { model.removeWallpaperPhoto() }
                    }
                    if model.wallpaperPattern == .photo && model.wallpaperPhoto != nil {
                        DisclosureGroup("Photo position") {
                            Text("Move the crop horizontally").font(.caption).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { model.focalX }, set: { model.setFocalPoint(x: $0) }), in: 0...1)
                            Text("Move the crop vertically").font(.caption).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { model.focalY }, set: { model.setFocalPoint(y: $0) }), in: 0...1)
                        }
                    }
                }
                Section {
                    Button("Export wallpaper", systemImage: "square.and.arrow.up") { model.exportArtwork(icon: false) }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    private var iconEditor: some View {
        VStack(spacing: 0) {
            Image(uiImage: RiceArtwork.render(theme: model.draftTheme, size: CGSize(width: 512, height: 512), icon: true,
                pattern: .rings, photo: nil, focalPoint: CGPoint(x: 0.5, y: 0.5)))
                .resizable().frame(width: 178, height: 178)
                .clipShape(RoundedRectangle(cornerRadius: 38))
                .padding(.vertical, 26)
                .accessibilityLabel("Icon preview")
            Divider()
            List {
                Section("Colors") {
                    ForEach(["background", "foreground", "accent"], id: \.self) { key in
                        ColorPicker(key.capitalized, selection: Binding(get: {
                            Color(hex: model.draftTheme.tokens[key] ?? "#FFFFFF") ?? .white
                        }, set: { model.editToken(key, color: $0) }))
                    }
                }
                Section {
                    Button("Export icon", systemImage: "square.and.arrow.up") { model.exportArtwork(icon: true) }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    private var setup: some View {
        List {
            Section("Widget theme") { Text(model.activeTheme.name) }
            Section("On your iPhone") {
                setupRow("widget", title: "Add a widget", detail: "Touch and hold the Home Screen. Tap Edit, then Add Widget. Choose Rice and pick a widget.")
                setupRow("wallpaper", title: "Set wallpaper", detail: "Export your wallpaper in Create. Save the image, then open Settings and choose Wallpaper.")
                setupRow("icon", title: "Make an app shortcut", detail: "Export your icon in Create. In Shortcuts, create an Open App shortcut and add it to the Home Screen using your icon image.")
            }
            Section {
                NavigationLink("Widget slots") { slotSettings }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Set Up")
    }

    private func setupRow(_ id: String, title: String, detail: String) -> some View {
        NavigationLink {
            VStack(alignment: .leading, spacing: 22) {
                Text(detail).font(.title3)
                Button(model.state.completedSetupSteps.contains(id) ? "Mark as unfinished" : "Mark as done") {
                    model.setSetupStep(id, done: !model.state.completedSetupSteps.contains(id))
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle(title)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if model.state.completedSetupSteps.contains(id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
    }

    private var slotSettings: some View {
        List {
            ForEach(model.state.slots) { slot in
                Toggle(slot.name, isOn: Binding(get: {
                    model.state.slots.first(where: { $0.id == slot.id })?.pinned ?? false
                }, set: { pinned in
                    guard let index = model.state.slots.firstIndex(where: { $0.id == slot.id }) else { return }
                    model.state.slots[index].pinned = pinned
                    if pinned { model.save() } else { model.activate(model.state.activeThemeID) }
                }))
            }
            Text("Pinned widgets keep their current theme when you switch themes.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Widget Slots")
    }

    private var settings: some View {
        List {
            Section {
                NavigationLink("Diagnostics") { diagnostics }
                Link("Source code", destination: URL(string: "https://github.com/Marginally-Better-Apps/MB-Rice")!)
            }
            Section("Privacy") {
                Text("Your themes and photos stay on this iPhone unless you choose to share them.")
            }
        }
        .listStyle(.plain)
        .navigationTitle("Settings")
    }

    private var diagnostics: some View {
        List {
            LabeledContent("Shared widget storage", value: model.appGroupAvailable ? "Available" : "Unavailable")
            LabeledContent("Last refresh request", value: model.state.lastRefreshRequested?.formatted() ?? "None")
            LabeledContent("Last widget read", value: ((try? RiceStore.shared().lastWidgetRead()) ?? nil)?.formatted() ?? "None")
            Button("Export diagnostics", systemImage: "square.and.arrow.up") { model.exportDiagnostics() }
        }
        .navigationTitle("Diagnostics")
    }

    private var importPreview: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let pack = model.pendingImport {
                    Text(pack.manifest.name).font(.title2.bold())
                    Text("By \(pack.manifest.author)").foregroundStyle(.secondary)
                    if let component = pack.manifest.components.first {
                        RiceComponentView(component: component, theme: pack.manifest, images: model.pendingImages)
                            .frame(height: 200)
                    }
                    Spacer()
                    Button("Add to Library") { model.confirmImport() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("Import Theme")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { model.pendingImport = nil } } }
        }
    }
}

private struct RiceCanvasEditor: View {
    let component: RiceComponent
    let theme: RiceManifest
    let images: [String: UIImage]
    @Binding var selectedIndex: Int?
    let onMove: (Int, Double, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: theme.tokens[component.background ?? "background"] ?? "#000000") ?? .black
                ForEach(Array((component.root.children ?? []).enumerated()), id: \.offset) { index, node in
                    RiceDraggableElement(node: node, theme: theme, images: images,
                                         canvasSize: geometry.size, selected: selectedIndex == index,
                                         onSelect: { selectedIndex = index },
                                         onMove: { x, y in onMove(index, x, y) })
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .accessibilityLabel("Widget canvas. Tap an element to edit. Drag to move.")
    }
}

private struct RiceDraggableElement: View {
    let node: RiceNode
    let theme: RiceManifest
    let images: [String: UIImage]
    let canvasSize: CGSize
    let selected: Bool
    let onSelect: () -> Void
    let onMove: (Double, Double) -> Void
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        RiceSceneView(node: node, theme: theme, images: images)
            .frame(width: canvasSize.width * (node.width ?? 0.8), height: canvasSize.height * (node.height ?? 0.2))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
            .position(x: canvasSize.width * (node.x ?? 0.5) + dragOffset.width,
                      y: canvasSize.height * (node.y ?? 0.5) + dragOffset.height)
            .onTapGesture(perform: onSelect)
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in onSelect(); dragOffset = value.translation }
                .onEnded { value in
                    onMove((node.x ?? 0.5) + value.translation.width / max(canvasSize.width, 1),
                           (node.y ?? 0.5) + value.translation.height / max(canvasSize.height, 1))
                    dragOffset = .zero
                })
            .accessibilityLabel(node.type == "text" ? "Text: \(node.text ?? "")" : node.type.capitalized)
            .accessibilityAddTraits(.isButton)
    }
}
