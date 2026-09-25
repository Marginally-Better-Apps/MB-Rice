import SwiftUI
import UIKit

struct RiceSceneView: View {
    let node: RiceNode
    let theme: RiceManifest
    let assetRoot: URL?

    var body: some View {
        scene
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var scene: some View {
        switch node.type {
        case "stack":
            let children = Array((node.children ?? []).enumerated())
            if node.axis == "horizontal" {
                HStack(spacing: node.spacing ?? 4) {
                    ForEach(children, id: \.offset) { child in RiceSceneView(node: child.element, theme: theme, assetRoot: assetRoot) }
                }
            } else if node.axis == "overlay" {
                ZStack {
                    ForEach(children, id: \.offset) { child in RiceSceneView(node: child.element, theme: theme, assetRoot: assetRoot) }
                }
            } else {
                VStack(alignment: .leading, spacing: node.spacing ?? 4) {
                    ForEach(children, id: \.offset) { child in RiceSceneView(node: child.element, theme: theme, assetRoot: assetRoot) }
                }
            }
        case "text":
            Text(node.text ?? "").font(.system(size: node.fontSize ?? 18, weight: .medium)).foregroundStyle(color(node.token))
        case "clock":
            if node.text == "time" {
                Text(Date.now, style: .time).font(.system(size: node.fontSize ?? 32, weight: .semibold, design: .rounded)).foregroundStyle(color(node.token))
            } else if node.text == "weekday" {
                Text(Date.now, format: .dateTime.weekday(.wide)).font(.system(size: node.fontSize ?? 16)).foregroundStyle(color(node.token))
            } else {
                Text(Date.now, style: .date).font(.system(size: node.fontSize ?? 16)).foregroundStyle(color(node.token))
            }
        case "shape":
            RoundedRectangle(cornerRadius: node.radius ?? 8).fill(color(node.token)).frame(minHeight: 12)
        case "gradient":
            LinearGradient(colors: [color(node.token), color("background")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "image":
            if let assetID = node.asset, let asset = theme.assets.first(where: { $0.id == assetID }), let assetRoot,
               let image = UIImage(contentsOfFile: assetRoot.appending(path: asset.path).path) {
                Image(uiImage: image).resizable().scaledToFill().clipped()
            } else {
                Image(systemName: "photo").foregroundStyle(color("accent"))
            }
        case "spacer": Spacer(minLength: node.spacing ?? 4)
        default: EmptyView()
        }
    }

    private func color(_ key: String?) -> Color {
        Color(hex: theme.tokens[key ?? "foreground"] ?? "#FFFFFF") ?? .white
    }
}

struct RiceComponentView: View {
    let component: RiceComponent
    let theme: RiceManifest
    let assetRoot: URL?

    var body: some View {
        RiceSceneView(node: component.root, theme: theme, assetRoot: assetRoot)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(hex: theme.tokens[component.background ?? "background"] ?? "#000000") ?? .black)
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
