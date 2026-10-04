#!/usr/bin/env swift
// Renders the WindWhisper app icon (see docs/DESIGN_SYSTEM.md, “图标”).
//
// Usage: generate-brand-icon.swift MASTER_PNG MACOS_ICONSET_DIR IOS_ICON_PNG
//
// Every size is drawn directly instead of downscaled from the master, so the
// 16/32px variants can use fewer, heavier strokes and stay legible.

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fputs("Usage: generate-brand-icon.swift MASTER_PNG MACOS_ICONSET_DIR IOS_ICON_PNG\n", stderr)
    exit(64)
}

let accent = CGColor(srgbRed: 0x2F / 255, green: 0x6B / 255, blue: 0x8A / 255, alpha: 1)
let stroke = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

/// A point on the unit tile, y pointing down.
typealias UnitPoint = (x: CGFloat, y: CGFloat)

/// Appends an arc as sampled points so the curl direction is explicit.
func arc(center: UnitPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat) -> [UnitPoint] {
    let steps = 48
    return (1...steps).map { step in
        let angle = (start + (end - start) * CGFloat(step) / CGFloat(steps)) * .pi / 180
        return (center.x + radius * cos(angle), center.y + radius * sin(angle))
    }
}

/// Three staggered gusts; the top one curls up, the bottom one curls down.
let fullStrokes: [[UnitPoint]] = [
    [(0.20, 0.38), (0.62, 0.38)] + arc(center: (0.62, 0.295), radius: 0.085, from: 90, to: -150),
    [(0.30, 0.52), (0.80, 0.52)],
    [(0.20, 0.66), (0.54, 0.66)] + arc(center: (0.54, 0.735), radius: 0.075, from: -90, to: 150),
]

/// Small sizes keep two straight gusts so they survive pixel snapping.
let compactStrokes: [[UnitPoint]] = [
    [(0.22, 0.40), (0.70, 0.40)],
    [(0.34, 0.60), (0.80, 0.60)],
]

enum Shape {
    /// macOS: rounded tile inside the 1024 grid (824pt body) with a soft shadow.
    case macTile
    /// iOS: full-bleed square; the system applies the mask.
    case fullBleed
}

func render(pixels: Int, shape: Shape) -> Data {
    let size = CGFloat(pixels)
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        // The App Store rejects iOS icons with an alpha channel.
        bitmapInfo: shape == .fullBleed
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    let tile: CGRect
    switch shape {
    case .macTile:
        let inset = size * 100 / 1024
        tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = tile.width * 0.225
        let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        if pixels >= 64 {
            context.setShadow(
                offset: CGSize(width: 0, height: size * 0.01),
                blur: size * 0.02,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22)
            )
        }
        context.addPath(path)
        context.setFillColor(accent)
        context.fillPath()
        context.restoreGState()
    case .fullBleed:
        tile = CGRect(x: 0, y: 0, width: size, height: size)
        context.setFillColor(accent)
        context.fill(tile)
    }

    let compact = tile.width < 40
    let strokes = compact ? compactStrokes : fullStrokes
    context.setStrokeColor(stroke)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(tile.width * (compact ? 0.11 : 0.068))
    for points in strokes {
        guard let first = points.first else { continue }
        context.beginPath()
        context.move(to: CGPoint(x: tile.minX + first.x * tile.width, y: tile.minY + first.y * tile.height))
        for point in points.dropFirst() {
            context.addLine(to: CGPoint(x: tile.minX + point.x * tile.width, y: tile.minY + point.y * tile.height))
        }
        context.strokePath()
    }

    let image = context.makeImage()!
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: pixels, height: pixels)
    return representation.representation(using: .png, properties: [:])!
}

func write(_ data: Data, to path: String) {
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        fputs("Could not write \(path): \(error.localizedDescription)\n", stderr)
        exit(73)
    }
}

let masterPath = arguments[1]
let iconsetPath = arguments[2]
let iosPath = arguments[3]

write(render(pixels: 1024, shape: .macTile), to: masterPath)
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    write(render(pixels: points, shape: .macTile), to: "\(iconsetPath)/icon_\(points)x\(points).png")
    write(render(pixels: points * 2, shape: .macTile), to: "\(iconsetPath)/icon_\(points)x\(points)@2x.png")
}
write(render(pixels: 1024, shape: .fullBleed), to: iosPath)
print(masterPath)
