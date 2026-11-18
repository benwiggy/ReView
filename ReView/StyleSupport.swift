//
//  StoredColor.swift
//  ReView
//
//  Created by Ben on 01/11/2026.
//


import AppKit
import SwiftUI

/// Colours kept in UserDefaults as "RRGGBBAA" text, and conversions to and from SwiftUI's colour picker.
enum StoredColor {
    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        func byte(_ value: CGFloat) -> String {
            let n = Int((min(max(value, 0), 1) * 255).rounded())
            return (n < 16 ? "0" : "") + String(n, radix: 16, uppercase: true)
        }
        return byte(c.redComponent) + byte(c.greenComponent) + byte(c.blueComponent) + byte(c.alphaComponent)
    }

    static func color(_ hex: String?, fallback: NSColor) -> NSColor {
        guard let hex, hex.count == 8, let value = UInt32(hex, radix: 16) else { return fallback }
        return NSColor(srgbRed: CGFloat((value >> 24) & 255) / 255, green: CGFloat((value >> 16) & 255) / 255,
                       blue: CGFloat((value >> 8) & 255) / 255, alpha: CGFloat(value & 255) / 255)
    }

    static func ns(_ color: Color) -> NSColor {
        let c = NSColor(color)
        return c.usingColorSpace(.sRGB) ?? c
    }
}

extension TextFonts {
    static func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return NSFontManager.shared.font(withFamily: family, traits: traits, weight: 5, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    static func isBold(_ font: NSFont?) -> Bool {
        font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
    }

    static func isItalic(_ font: NSFont?) -> Bool {
        font.map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } ?? false
    }
}