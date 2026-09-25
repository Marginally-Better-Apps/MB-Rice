import UIKit

enum RicePattern: String, CaseIterable, Identifiable {
    case rings = "Rings"
    case gradient = "Gradient"
    case checker = "Checker"
    case halftone = "Halftone"
    case photo = "Photo"
    var id: String { rawValue }
}

enum RiceArtwork {
    static func render(theme: RiceManifest, size: CGSize, icon: Bool, pattern: RicePattern = .rings, photo: UIImage? = nil, focalPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> UIImage {
        let background = UIColor(hex: theme.tokens["background"] ?? "#000000")
        let accent = UIColor(hex: theme.tokens["accent"] ?? "#FFFFFF")
        let secondary = UIColor(hex: theme.tokens["secondary"] ?? "#444444")
        let foreground = UIColor(hex: theme.tokens["foreground"] ?? "#FFFFFF")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            background.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            let unit = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: icon ? size.height / 2 : size.height * 0.55)
            if pattern == .photo, let photo {
                let scale = max(size.width / photo.size.width, size.height / photo.size.height)
                let width = photo.size.width * scale
                let height = photo.size.height * scale
                let x = -(width - size.width) * min(max(focalPoint.x, 0), 1)
                let y = -(height - size.height) * min(max(focalPoint.y, 0), 1)
                photo.draw(in: CGRect(x: x, y: y, width: width, height: height))
            } else if pattern == .gradient {
                let colors = [background.cgColor, secondary.cgColor, accent.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.62, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
            } else if pattern == .checker {
                let step = unit / 9
                secondary.setFill()
                for row in 0...Int(size.height / step) {
                    for column in 0...Int(size.width / step) where (row + column).isMultiple(of: 2) {
                        cg.fill(CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step))
                    }
                }
            } else if pattern == .halftone {
                let step = unit / 13
                accent.setFill()
                for row in 0...Int(size.height / step) {
                    for column in 0...Int(size.width / step) {
                        let dx = CGFloat(column) * step - center.x
                        let dy = CGFloat(row) * step - center.y
                        let distance = min(1, hypot(dx, dy) / (unit * 0.8))
                        let diameter = step * (0.12 + 0.48 * (1 - distance))
                        cg.fillEllipse(in: CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: diameter, height: diameter))
                    }
                }
            } else {
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
            }
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
