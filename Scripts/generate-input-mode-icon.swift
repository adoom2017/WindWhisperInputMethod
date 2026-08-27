#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-input-mode-icon.swift OUTPUT_PATH\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
if FileManager.default.fileExists(atPath: outputURL.path) {
    try FileManager.default.removeItem(at: outputURL)
}
// Match the 22×16 pt canvas used by macOS input-source badges such as
// Squirrel's bundled menu icon. A square 32×32 page is rendered too large and
// sits differently in the menu's fixed icon column.
var mediaBox = CGRect(x: 0, y: 0, width: 22, height: 16)

guard let consumer = CGDataConsumer(url: outputURL as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    fputs("Unable to create PDF at \(outputURL.path)\n", stderr)
    exit(1)
}

context.beginPDFPage(nil)
// Draw a black rounded input-source badge and punch the glyph out of its alpha
// mask. It therefore reads as black-on-white normally and remains legible when
// macOS tints the badge for a selected menu row.
let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 32, nil)
let characters: [UniChar] = Array("风".utf16)
var glyphs = [CGGlyph](repeating: 0, count: characters.count)
guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count),
      let glyph = glyphs.first,
      let outline = CTFontCreatePathForGlyph(font, glyph, nil) else {
    fputs("Unable to create the windwhisper menu glyph.\n", stderr)
    exit(1)
}

let bounds = outline.boundingBoxOfPath
let targetDimension: CGFloat = 10.5
let scale = min(targetDimension / bounds.width, targetDimension / bounds.height)
var transform = CGAffineTransform(
    a: scale,
    b: 0,
    c: 0,
    d: scale,
    tx: mediaBox.midX - bounds.midX * scale,
    ty: mediaBox.midY - bounds.midY * scale
)
guard let centeredOutline = outline.copy(using: &transform) else {
    fputs("Unable to center the windwhisper menu glyph.\n", stderr)
    exit(1)
}

context.setFillColor(gray: 0, alpha: 1)
context.addPath(
    CGPath(
        roundedRect: mediaBox,
        cornerWidth: 4,
        cornerHeight: 4,
        transform: nil
    )
)
context.addPath(centeredOutline)
context.drawPath(using: .eoFill)

context.endPDFPage()
context.closePDF()
