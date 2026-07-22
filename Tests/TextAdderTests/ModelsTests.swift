import AppKit
import Testing

@testable import TextAdder

@Suite struct ColorHexTests {
    @Test func roundTrip() throws {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let back = try #require(NSColor(hexString: color.hexString))
        let srgb = try #require(back.usingColorSpace(.sRGB))
        #expect(abs(srgb.redComponent - 0.2) < 0.01)
        #expect(abs(srgb.greenComponent - 0.4) < 0.01)
        #expect(abs(srgb.blueComponent - 0.6) < 0.01)
        #expect(abs(back.alphaComponent - 0.8) < 0.01)
    }

    @Test func knownValues() throws {
        #expect(NSColor.black.hexString == "#000000FF")
        #expect(NSColor.white.usingColorSpace(.sRGB)!.hexString == "#FFFFFFFF")
        let red = try #require(NSColor(hexString: "#FF0000FF"))
        #expect(abs(red.usingColorSpace(.sRGB)!.redComponent - 1.0) < 0.001)
    }

    @Test func invalidHexReturnsNil() {
        #expect(NSColor(hexString: "nope") == nil)
        #expect(NSColor(hexString: "#FFF") == nil)
        #expect(NSColor(hexString: "#GGGGGGGG") == nil)
        #expect(NSColor(hexString: "") == nil)
    }
}

@Suite struct TextAlignTests {
    @Test func nsAlignmentMapping() {
        #expect(TextAlign.left.ns == .left)
        #expect(TextAlign.center.ns == .center)
        #expect(TextAlign.right.ns == .right)
        #expect(TextAlign.left.id == "left")
        #expect(TextAlign.allCases.count == 3)
    }
}

@Suite struct OverlayItemAttributedTests {
    private func attributes(of item: OverlayItem, text: String? = nil)
        -> [NSAttributedString.Key: Any]
    {
        item.attributed(text ?? item.text).attributes(at: 0, effectiveRange: nil)
    }

    @Test func borderProducesStrokeAttributes() throws {
        var item = OverlayItem()
        item.fontSize = 64
        item.borderWidth = 2
        let attrs = attributes(of: item)
        let strokeWidth = try #require(attrs[.strokeWidth] as? Double)
        // Negative (stroke+fill), 2pt of 64pt font = 3.125%.
        #expect(abs(strokeWidth - (-3.125)) < 0.001)
        #expect(attrs[.strokeColor] != nil)
    }

    @Test func zeroBorderHasNoStroke() {
        var item = OverlayItem()
        item.borderWidth = 0
        let attrs = attributes(of: item)
        #expect(attrs[.strokeWidth] == nil)
        #expect(attrs[.strokeColor] == nil)
    }

    @Test func shadowToggle() {
        var item = OverlayItem()
        item.shadowEnabled = true
        #expect(attributes(of: item)[.shadow] != nil)
        item.shadowEnabled = false
        #expect(attributes(of: item)[.shadow] == nil)
    }

    @Test func emptyTextRendersAsSpace() {
        let item = OverlayItem()
        #expect(item.attributed("").string == " ")
        #expect(item.attributed("hi").string == "hi")
    }

    @Test func alignmentReachesParagraphStyle() {
        var item = OverlayItem()
        item.alignment = .right
        let style = attributes(of: item)[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.alignment == .right)
    }

    @Test func unknownFontFallsBackToSystem() throws {
        var item = OverlayItem()
        item.fontFamily = "No Such Font Family 123"
        let font = try #require(attributes(of: item)[.font] as? NSFont)
        #expect(abs(font.pointSize - item.fontSize) < 0.001)
    }

    @Test func boldTrait() throws {
        var item = OverlayItem()
        item.fontFamily = "Helvetica Neue"
        item.isBold = true
        let bold = try #require(attributes(of: item)[.font] as? NSFont)
        #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))

        item.isBold = false
        let regular = try #require(attributes(of: item)[.font] as? NSFont)
        #expect(!NSFontManager.shared.traits(of: regular).contains(.boldFontMask))
    }
}

@Suite struct StylePresetTests {
    @Test func capturesAndAppliesAllStyleFields() {
        var source = OverlayItem()
        source.fontFamily = "Georgia"
        source.fontSize = 88
        source.isBold = false
        source.textColorHex = "#01020304"
        source.borderWidth = 7
        source.borderColorHex = "#05060708"
        source.opacity = 0.5
        source.shadowEnabled = true
        source.boxEnabled = true
        source.boxColorHex = "#090A0B0C"

        let preset = StylePreset(name: "Test", from: source)
        var target = OverlayItem()
        target.text = "unchanged"
        preset.apply(to: &target)

        #expect(target.fontFamily == "Georgia")
        #expect(target.fontSize == 88)
        #expect(target.isBold == false)
        #expect(target.textColorHex == "#01020304")
        #expect(target.borderWidth == 7)
        #expect(target.borderColorHex == "#05060708")
        #expect(target.opacity == 0.5)
        #expect(target.shadowEnabled == true)
        #expect(target.boxEnabled == true)
        #expect(target.boxColorHex == "#090A0B0C")
        #expect(target.text == "unchanged")
    }
}

@Suite struct SnapPositionTests {
    private let frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
    private let size = NSSize(width: 100, height: 50)

    @Test func allNinePositions() {
        let expected: [SnapPosition: NSPoint] = [
            .topLeft: NSPoint(x: 24, y: 526),
            .topCenter: NSPoint(x: 450, y: 526),
            .topRight: NSPoint(x: 876, y: 526),
            .middleLeft: NSPoint(x: 24, y: 275),
            .middleCenter: NSPoint(x: 450, y: 275),
            .middleRight: NSPoint(x: 876, y: 275),
            .bottomLeft: NSPoint(x: 24, y: 24),
            .bottomCenter: NSPoint(x: 450, y: 24),
            .bottomRight: NSPoint(x: 876, y: 24),
        ]
        for (position, point) in expected {
            let origin = position.origin(for: size, in: frame)
            #expect(origin.x == point.x, "\(position) x")
            #expect(origin.y == point.y, "\(position) y")
        }
    }

    @Test func bottomThird() {
        let origin = SnapPosition.bottomThird.origin(for: size, in: frame)
        #expect(origin.x == 450)
        #expect(origin.y == 175)  // minY + height/3 - size/2
    }

    @Test func offsetFrame() {
        let offset = NSRect(x: 100, y: 200, width: 1000, height: 600)
        let origin = SnapPosition.topLeft.origin(for: size, in: offset)
        #expect(origin.x == 124)
        #expect(origin.y == 726)
    }

    @Test func allCasesEnumerated() {
        #expect(SnapPosition.allCases.count == 10)
        #expect(SnapPosition.topLeft.id == "topLeft")
    }
}

@Suite struct CodableTests {
    @Test func hotKeyComboRoundTrip() throws {
        let combo = HotKeyCombo(keyCode: 17, modifiers: 4096, display: "⌃T")
        let data = try JSONEncoder().encode(combo)
        let back = try JSONDecoder().decode(HotKeyCombo.self, from: data)
        #expect(back == combo)
    }

    @Test func overlayItemRoundTrip() throws {
        var item = OverlayItem()
        item.text = "line one\nline two"
        item.originX = 12.5
        item.originY = 800
        item.autoHideSeconds = 42
        let data = try JSONEncoder().encode(item)
        let back = try JSONDecoder().decode(OverlayItem.self, from: data)
        #expect(back == item)
    }
}
