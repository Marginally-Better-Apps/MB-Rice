import Foundation

enum RicePresets {
    static let all: [RiceManifest] = [
        make(id: "paper", name: "Paper", background: "#F4F0E8", foreground: "#24231F", accent: "#B69D73", secondary: "#D7CEC0", caption: "A quieter day", style: "serif"),
        make(id: "amber", name: "Amber Terminal", background: "#151A16", foreground: "#F1B94B", accent: "#C47D25", secondary: "#2F3B2C", caption: "READY FOR TODAY", style: "monospaced"),
        make(id: "dusk", name: "Soft Dusk", background: "#352D4D", foreground: "#F7E9E3", accent: "#E9A6A0", secondary: "#6D607E", caption: "Slow down a little", style: "rounded"),
        make(id: "minimal", name: "Bright Minimal", background: "#FCFCF8", foreground: "#171A1C", accent: "#5267F5", secondary: "#DDE1F7", caption: "Make room for more", style: "default"),
        make(id: "geometry", name: "Dark Geometry", background: "#101923", foreground: "#F2F6F7", accent: "#44C5B5", secondary: "#254655", caption: "Find your angle", style: "default"),
        make(id: "wood", name: "Warm Grain", background: "#33241D", foreground: "#FFF0D8", accent: "#DB965E", secondary: "#78523D", caption: "Good things take time", style: "serif"),
        make(id: "pixel", name: "Pixel Day", background: "#302946", foreground: "#FCF9D4", accent: "#F8C05A", secondary: "#715C85", caption: "LEVEL UP", style: "monospaced"),
        make(id: "contrast", name: "High Contrast", background: "#000000", foreground: "#FFFFFF", accent: "#FFFF00", secondary: "#383838", caption: "CLEAR AND SIMPLE", style: "default")
    ]

    static func make(id: String, name: String, background: String, foreground: String, accent: String, secondary: String, caption: String, style: String) -> RiceManifest {
        let main = RiceComponent(id: "main", kind: "widget", name: "Main Clock", root: RiceNode(type: "stack", axis: "vertical", spacing: 5, children: [
            RiceNode(type: "text", text: caption, token: "accent", fontSize: 12),
            RiceNode(type: "clock", text: "time", token: "foreground", fontSize: 42),
            RiceNode(type: "clock", text: "date", token: "foreground", fontSize: 15)
        ]), privacy: "public", families: ["systemSmall", "systemMedium", "systemLarge", "accessoryRectangular"], background: "background")
        let note = RiceComponent(id: "note", kind: "widget", name: "Daily Card", root: RiceNode(type: "stack", axis: "vertical", spacing: 8, children: [
            RiceNode(type: "text", text: name.uppercased(), token: "accent", fontSize: 13),
            RiceNode(type: "text", text: caption, token: "foreground", fontSize: 26),
            RiceNode(type: "clock", text: "weekday", token: "foreground", fontSize: 14)
        ]), privacy: "public", families: ["systemSmall", "systemMedium", "systemLarge", "accessoryRectangular"], background: "background")
        return RiceManifest(schemaVersion: 1, id: id, name: name, version: "0.1.0", author: "Marginally Better Apps", license: "LICENSES/MIT.txt", requires: [], tokens: ["background": background, "foreground": foreground, "accent": accent, "secondary": secondary], assets: [], components: [main, note], slots: [RiceSlotSuggestion(role: "main-clock", component: "main", surface: "home"), RiceSlotSuggestion(role: "daily-card", component: "note", surface: "home")])
    }
}
