import SwiftUI
import UniformTypeIdentifiers

struct RiceRootView: View {
    @EnvironmentObject private var model: RiceAppModel
    @State private var importing = false
    @State private var showingExportAudit = false

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
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your iPhone, your way").font(.largeTitle.bold())
                    Text("Create and share matching themes offline.").foregroundStyle(.secondary)
                }
                preview(theme: model.activeTheme, component: model.activeTheme.components[0], height: 210)
                HStack {
                    Button("Import theme", systemImage: "square.and.arrow.down") { importing = true }
                    Spacer()
                    Button("Share theme", systemImage: "square.and.arrow.up") { showingExportAudit = true }
                }.buttonStyle(.bordered)
                Text("Themes").font(.title2.bold())
                ForEach(model.state.themes) { theme in
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
        }.navigationTitle("Rice")
    }

    private var studio: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(model.activeTheme.name) preview").font(.title2.bold())
                preview(theme: model.activeTheme, component: model.activeTheme.components[0], height: 200)
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
                Text("Main clock caption").font(.headline)
                TextField("Caption", text: Binding(get: {
                    model.activeTheme.components.first(where: { $0.id == "main" })?.root.children?.first?.text ?? ""
                }, set: { model.editText($0) }))
                .textFieldStyle(.roundedBorder)
                Text("Artwork").font(.headline)
                HStack {
                    Button("Export wallpaper", systemImage: "photo") { model.exportArtwork(icon: false) }
                    Button("Export icon", systemImage: "app") { model.exportArtwork(icon: true) }
                }.buttonStyle(.bordered)
                Text("Exports use the current palette. Wallpaper placement and shortcut icons are completed in iOS setup.").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Studio")
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
                            if let index = model.state.slots.firstIndex(where: { $0.id == slot.id }) { model.state.slots[index].pinned = value; model.save() }
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
                    if let component = pack.manifest.components.first { preview(theme: pack.manifest, component: component, height: 190) }
                    Spacer()
                    Button("Import theme") { model.confirmImport() }.buttonStyle(.borderedProminent)
                }
            }.padding().navigationTitle("Review import")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { model.pendingImport = nil } } }
        }
    }

    private func preview(theme: RiceManifest, component: RiceComponent, height: CGFloat) -> some View {
        RiceComponentView(component: component, theme: theme, assetRoot: nil)
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                Text("Preview").font(.caption2.bold()).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(10)
            }
            .accessibilityLabel("Preview of \(theme.name) \(component.name)")
    }
}
