import AppKit

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? .white
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(c.redComponent * 255)),
            Int(round(c.greenComponent * 255)),
            Int(round(c.blueComponent * 255)),
            Int(round(c.alphaComponent * 255))
        )
    }

    convenience init?(hexString: String) {
        let s = hexString.replacingOccurrences(of: "#", with: "")
        guard s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((v >> 24) & 0xFF) / 255,
            green: CGFloat((v >> 16) & 0xFF) / 255,
            blue: CGFloat((v >> 8) & 0xFF) / 255,
            alpha: CGFloat(v & 0xFF) / 255
        )
    }
}

enum TextAlign: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var ns: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

/// One floating text label with its own style, position, and display.
struct OverlayItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Label"
    var text = "Hello!"
    var fontFamily = "Helvetica Neue"
    var fontSize: Double = 64
    var isBold = true
    var textColorHex = "#FFD60AFF"
    var borderWidth: Double = 2
    var borderColorHex = "#000000FF"
    var alignment = TextAlign.center
    var opacity: Double = 1.0
    var shadowEnabled = false
    var boxEnabled = false
    var boxColorHex = "#000000B3"
    var visible = true
    var screenIndex = 0
    var originX: Double?
    var originY: Double?
    var autoHideSeconds: Double = 5

    /// Attributed rendering of `displayText` (which may be countdown-substituted).
    func attributed(_ displayText: String) -> NSAttributedString {
        var font = NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        if isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment.ns

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(hexString: textColorHex) ?? .systemYellow,
            .paragraphStyle: paragraph,
        ]
        if borderWidth > 0 {
            attrs[.strokeColor] = NSColor(hexString: borderColorHex) ?? .black
            // Negative = stroke AND fill; the attribute is a % of font size.
            attrs[.strokeWidth] = -(borderWidth / fontSize * 100.0)
        }
        if shadowEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 8
            attrs[.shadow] = shadow
        }
        return NSAttributedString(
            string: displayText.isEmpty ? " " : displayText, attributes: attrs)
    }
}

/// A saved appearance (everything except the text/position) that can be
/// applied to any label.
struct StylePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var fontFamily: String
    var fontSize: Double
    var isBold: Bool
    var textColorHex: String
    var borderWidth: Double
    var borderColorHex: String
    var opacity: Double
    var shadowEnabled: Bool
    var boxEnabled: Bool
    var boxColorHex: String

    init(name: String, from item: OverlayItem) {
        self.name = name
        fontFamily = item.fontFamily
        fontSize = item.fontSize
        isBold = item.isBold
        textColorHex = item.textColorHex
        borderWidth = item.borderWidth
        borderColorHex = item.borderColorHex
        opacity = item.opacity
        shadowEnabled = item.shadowEnabled
        boxEnabled = item.boxEnabled
        boxColorHex = item.boxColorHex
    }

    func apply(to item: inout OverlayItem) {
        item.fontFamily = fontFamily
        item.fontSize = fontSize
        item.isBold = isBold
        item.textColorHex = textColorHex
        item.borderWidth = borderWidth
        item.borderColorHex = borderColorHex
        item.opacity = opacity
        item.shadowEnabled = shadowEnabled
        item.boxEnabled = boxEnabled
        item.boxColorHex = boxColorHex
    }
}

/// A recorded global hotkey (Carbon key code + Carbon modifier flags).
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

enum SnapPosition: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight
    case bottomThird

    var id: String { rawValue }

    /// Frame origin that places `size` at this position within `visibleFrame`
    /// (a screen's usable area).
    func origin(for size: NSSize, in f: NSRect) -> NSPoint {
        let margin: CGFloat = 24
        let xs: [CGFloat] = [
            f.minX + margin,
            f.midX - size.width / 2,
            f.maxX - margin - size.width,
        ]
        let ys: [CGFloat] = [
            f.maxY - margin - size.height,
            f.midY - size.height / 2,
            f.minY + margin,
        ]
        switch self {
        case .topLeft: return NSPoint(x: xs[0], y: ys[0])
        case .topCenter: return NSPoint(x: xs[1], y: ys[0])
        case .topRight: return NSPoint(x: xs[2], y: ys[0])
        case .middleLeft: return NSPoint(x: xs[0], y: ys[1])
        case .middleCenter: return NSPoint(x: xs[1], y: ys[1])
        case .middleRight: return NSPoint(x: xs[2], y: ys[1])
        case .bottomLeft: return NSPoint(x: xs[0], y: ys[2])
        case .bottomCenter: return NSPoint(x: xs[1], y: ys[2])
        case .bottomRight: return NSPoint(x: xs[2], y: ys[2])
        case .bottomThird:
            return NSPoint(x: xs[1], y: f.minY + f.height / 3 - size.height / 2)
        }
    }
}
