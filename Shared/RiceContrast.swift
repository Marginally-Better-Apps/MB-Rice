import Foundation

enum RiceContrast {
    static func ratio(_ first: String, _ second: String) -> Double? {
        guard let a = luminance(first), let b = luminance(second) else { return nil }
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ hex: String) -> Double? {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        let channels = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)]
        let linear = channels.map { channel -> Double in
            let scaled = channel / 255
            return scaled <= 0.04045 ? scaled / 12.92 : pow((scaled + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
