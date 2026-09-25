import Foundation
import SwiftUI

enum RiceLimits {
    static let archiveBytes = 50 * 1024 * 1024
    static let expandedBytes = 150 * 1024 * 1024
    static let entries = 512
    static let entryBytes = 20 * 1024 * 1024
    static let manifestBytes = 1024 * 1024
    static let nodes = 512
    static let depth = 24
}

struct RiceAsset: Codable, Identifiable, Equatable {
    var id: String
    var path: String
    var mimeType: String
    var length: Int
    var sha256: String
    var license: String
}

struct RiceNode: Codable, Equatable {
    var type: String
    var text: String? = nil
    var token: String? = nil
    var asset: String? = nil
    var axis: String? = nil
    var alignment: String? = nil
    var spacing: Double? = nil
    var fontSize: Double? = nil
    var radius: Double? = nil
    var x: Double? = nil
    var y: Double? = nil
    var width: Double? = nil
    var height: Double? = nil
    var children: [RiceNode]? = nil
}

struct RiceComponent: Codable, Identifiable, Equatable {
    var id: String
    var kind: String
    var name: String
    var root: RiceNode
    var privacy: String
    var families: [String]
    var background: String?
}

struct RiceSlotSuggestion: Codable, Equatable {
    var role: String
    var component: String
    var surface: String
}

struct RiceManifest: Codable, Identifiable, Equatable {
    var schemaVersion: Int
    var id: String
    var name: String
    var version: String
    var author: String
    var license: String
    var requires: [String]
    var tokens: [String: String]
    var assets: [RiceAsset]
    var components: [RiceComponent]
    var slots: [RiceSlotSuggestion]
}

enum RiceValidationError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return "Invalid theme"
    }
}

enum RiceValidator {
    static func validate(_ theme: RiceManifest) throws {
        guard theme.schemaVersion == 1 else { throw RiceValidationError.invalid("Unsupported schema version") }
        guard validID(theme.id), (1...80).contains(theme.name.count), (1...80).contains(theme.author.count) else { throw RiceValidationError.invalid("Invalid theme identity") }
        guard theme.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else { throw RiceValidationError.invalid("Invalid version") }
        guard theme.requires.isEmpty else { throw RiceValidationError.invalid("Unknown required capability") }
        guard (1...64).contains(theme.tokens.count), (1...64).contains(theme.components.count), theme.assets.count <= 128 else { throw RiceValidationError.invalid("Theme size exceeds limit") }
        for (key, value) in theme.tokens {
            guard validID(key), Color(hex: value) != nil else { throw RiceValidationError.invalid("Invalid color token") }
        }
        let componentIDs = Set(theme.components.map(\.id))
        guard componentIDs.count == theme.components.count else { throw RiceValidationError.invalid("Duplicate component ID") }
        let assetIDs = Set(theme.assets.map(\.id))
        guard assetIDs.count == theme.assets.count else { throw RiceValidationError.invalid("Duplicate asset ID") }
        for asset in theme.assets {
            guard validID(asset.id), asset.path.hasPrefix("assets/"), safePath(asset.path),
                  ["image/png", "image/jpeg", "image/webp"].contains(asset.mimeType),
                  (0...RiceLimits.entryBytes).contains(asset.length), asset.sha256.count == 64,
                  asset.sha256.allSatisfy({ $0.isHexDigit }), safePath(asset.license), asset.license.hasPrefix("LICENSES/")
            else { throw RiceValidationError.invalid("Invalid asset declaration") }
        }
        for component in theme.components {
            guard validID(component.id), ["widget", "wallpaper", "icon"].contains(component.kind),
                  (1...80).contains(component.name.count), component.privacy == "public",
                  component.background.map({ theme.tokens[$0] != nil }) ?? true,
                  component.families.allSatisfy({ ["systemSmall", "systemMedium", "systemLarge", "accessoryRectangular"].contains($0) })
            else { throw RiceValidationError.invalid("Invalid component") }
            var count = 0
            try validateNode(component.root, theme: theme, depth: 0, count: &count)
            guard RiceImages.referencedIDs(in: component.root).count <= 8 else { throw RiceValidationError.invalid("Too many images in one component") }
        }
        for slot in theme.slots {
            guard validID(slot.role), componentIDs.contains(slot.component),
                  theme.components.first(where: { $0.id == slot.component })?.kind == "widget",
                  ["home", "lock"].contains(slot.surface) else { throw RiceValidationError.invalid("Invalid slot suggestion") }
        }
    }

    private static func validateNode(_ node: RiceNode, theme: RiceManifest, depth: Int, count: inout Int) throws {
        count += 1
        guard depth < RiceLimits.depth, count <= RiceLimits.nodes else { throw RiceValidationError.invalid("Scene is too large") }
        guard ["stack", "canvas", "text", "clock", "shape", "gradient", "image", "spacer"].contains(node.type),
              node.token.map({ theme.tokens[$0] != nil }) ?? true,
              node.asset.map({ id in theme.assets.contains(where: { $0.id == id }) }) ?? true,
              (node.spacing ?? 0).isFinite, (0...80).contains(node.spacing ?? 0),
              (node.fontSize ?? 20).isFinite, (8...120).contains(node.fontSize ?? 20),
              (node.radius ?? 0).isFinite, (0...100).contains(node.radius ?? 0),
              (node.x ?? 0.5).isFinite, (0...1).contains(node.x ?? 0.5),
              (node.y ?? 0.5).isFinite, (0...1).contains(node.y ?? 0.5),
              (node.width ?? 0.8).isFinite, (0.05...1).contains(node.width ?? 0.8),
              (node.height ?? 0.2).isFinite, (0.05...1).contains(node.height ?? 0.2)
        else { throw RiceValidationError.invalid("Unsupported or invalid scene node") }
        switch node.type {
        case "stack": guard ["horizontal", "vertical", "overlay"].contains(node.axis ?? ""), (node.children?.count ?? 0) <= 32 else { throw RiceValidationError.invalid("Invalid stack") }
        case "canvas": guard (node.children?.count ?? 0) <= 32 else { throw RiceValidationError.invalid("Too many canvas elements") }
        case "text": guard let text = node.text, text.count <= 500 else { throw RiceValidationError.invalid("Invalid text") }
        case "clock": guard ["time", "date", "weekday"].contains(node.text ?? "") else { throw RiceValidationError.invalid("Invalid clock") }
        case "image": guard node.asset != nil else { throw RiceValidationError.invalid("Image asset missing") }
        default: break
        }
        for child in node.children ?? [] { try validateNode(child, theme: theme, depth: depth + 1, count: &count) }
    }

    static func validID(_ value: String) -> Bool {
        (1...64).contains(value.count) && value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    static func safePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("\\") && !value.contains(":") &&
        !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) &&
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

extension Color {
    init?(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}

struct RiceSlot: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var role: String
    var pinned: Bool
    var themeID: String
    var componentID: String
}

struct RiceState: Codable {
    var themes: [RiceManifest]
    var activeThemeID: String
    var slots: [RiceSlot]
    var completedSetupSteps: [String]
    var lastRefreshRequested: Date?
    var lastWidgetRead: Date?
}
