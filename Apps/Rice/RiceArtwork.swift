import UIKit

enum RiceArtwork {
    static func render(theme: RiceManifest, size: CGSize, icon: Bool) -> UIImage {
        let background = UIColor(hex: theme.tokens["background"] ?? "#000000")
        let accent = UIColor(hex: theme.tokens["accent"] ?? "#FFFFFF")
        let secondary = UIColor(hex: theme.tokens["secondary"] ?? "#444444")
        let foreground = UIColor(hex: theme.tokens["foreground"] ?? "#FFFFFF")
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            background.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            let unit = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: icon ? size.height / 2 : size.height * 0.55)
            secondary.setFill()
            for ring in 0..<5 {
                let diameter = unit * (0.15 + CGFloat(ring) * 0.16)
                let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                cg.setLineWidth(unit * 0.005)
                cg.setStrokeColor(accent.cgColor)
                cg.strokeEllipse(in: rect)
            }
            let mark = CGRect(x: center.x - unit * 0.12, y: center.y - unit * 0.12, width: unit * 0.24, height: unit * 0.24)
            cg.fillEllipse(in: mark)
            if icon {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 86, weight: .bold), .foregroundColor: foreground, .paragraphStyle: paragraph]
                ("R" as NSString).draw(in: CGRect(x: 0, y: center.y - 70, width: size.width, height: 110), withAttributes: attributes)
            }
        }
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let n = UInt32(value, radix: 16) ?? 0
        self.init(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
}
