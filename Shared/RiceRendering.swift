import SwiftUI
import UIKit

struct RiceSceneView: View {
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    let node: RiceNode
    let theme: RiceManifest
    let images: [String: UIImage]

    var body: some View {
        scene
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var scene: some View {
        switch node.type {
        case "canvas":
            GeometryReader { geometry in
                ZStack {
                    ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                        RiceSceneView(node: child, theme: theme, images: images)
                            .frame(width: geometry.size.width * (child.width ?? 0.8),
                                   height: geometry.size.height * (child.height ?? 0.2))
                            .position(x: geometry.size.width * (child.x ?? 0.5),
                                      y: geometry.size.height * (child.y ?? 0.5))
                    }
                }
            }
        case "stack":
            let children = Array((node.children ?? []).enumerated())
            if node.axis == "horizontal" {
                HStack(spacing: node.spacing ?? 4) {
                    ForEach(children, id: \.offset) { child in RiceSceneView(node: child.element, theme: theme, images: images) }
                }
            } else if node.axis == "overlay" {
                ZStack {
                    ForEach(children, id: \.offset) { child in RiceSceneView(node: child.element, theme: theme, images: images) }
                }
            } else {
                VStack(alignment: .leading, spacing: node.spacing ?? 4) {
                    ForEach(children, id: \.offset) { child in RiceSceneView(node: child.element, theme: theme, images: images) }
                }
            }
        case "text":
            Text(node.text ?? "").font(.system(size: (node.fontSize ?? 18) * typeScale, weight: .medium)).foregroundStyle(color(node.token)).lineLimit(3).minimumScaleFactor(0.7)
        case "clock":
            if node.text == "time" {
                Text(Date.now, style: .time).font(.system(size: (node.fontSize ?? 32) * typeScale, weight: .semibold, design: .rounded)).foregroundStyle(color(node.token)).lineLimit(1).minimumScaleFactor(0.6)
            } else if node.text == "weekday" {
                Text(Date.now, format: .dateTime.weekday(.wide)).font(.system(size: (node.fontSize ?? 16) * typeScale)).foregroundStyle(color(node.token)).lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text(Date.now, style: .date).font(.system(size: (node.fontSize ?? 16) * typeScale)).foregroundStyle(color(node.token)).lineLimit(1).minimumScaleFactor(0.6)
            }
        case "shape":
            RoundedRectangle(cornerRadius: node.radius ?? 8).fill(color(node.token)).frame(minHeight: 12)
        case "gradient":
            LinearGradient(colors: [color(node.token), color("background")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "image":
            if let assetID = node.asset, let image = images[assetID] {
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
    let images: [String: UIImage]

    var body: some View {
        RiceSceneView(node: component.root, theme: theme, images: images)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(hex: theme.tokens[component.background ?? "background"] ?? "#000000") ?? .black)
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
