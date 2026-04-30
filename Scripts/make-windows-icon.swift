#!/usr/bin/env swift
// Renders the recmeet logo at the four sizes Windows expects (16, 32, 48,
// 256) and packs them into a single multi-resolution `.ico` file.
//
// Usage:  swift make-windows-icon.swift <output.ico>
//
// The .ico file format is a tiny header followed by one ICONDIRENTRY per
// embedded image, then the image bytes themselves. Modern Windows accepts
// PNG-encoded entries, so we just embed each PNG directly.

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-windows-icon.swift <output.ico>\n", stderr)
    exit(2)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

// Same visual identity as Scripts/make-icon.swift, parameterised by size.
func renderPNG(size: Int) -> Data {
    let s = CGFloat(size)
    let cornerRadius = s * 225 / 1024
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let center = CGPoint(x: s / 2, y: s / 2)

    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bg = [
        CGColor(srgbRed: 0.173, green: 0.173, blue: 0.184, alpha: 1.0),
        CGColor(srgbRed: 0.039, green: 0.039, blue: 0.047, alpha: 1.0),
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: cs, colors: bg, locations: [0, 1])!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.setLineWidth(s * 28 / 1024)
    ctx.addArc(center: center, radius: s * 360 / 1024,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    let dotR = s * 200 / 1024
    ctx.saveGState()
    ctx.addArc(center: center, radius: dotR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.clip()
    let red = [
        CGColor(srgbRed: 1.00, green: 0.42, blue: 0.38, alpha: 1.0),
        CGColor(srgbRed: 0.92, green: 0.22, blue: 0.20, alpha: 1.0),
        CGColor(srgbRed: 0.65, green: 0.08, blue: 0.08, alpha: 1.0),
    ] as CFArray
    let redGrad = CGGradient(colorsSpace: cs, colors: red, locations: [0, 0.55, 1])!
    let off = s * 70 / 1024
    ctx.drawRadialGradient(
        redGrad,
        startCenter: CGPoint(x: center.x - off, y: center.y + off),
        startRadius: 0,
        endCenter: center,
        endRadius: dotR,
        options: []
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addArc(center: center, radius: s * 340 / 1024,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.20, blue: 0.20, alpha: 0.10))
    ctx.setLineWidth(s * 48 / 1024)
    ctx.strokePath()
    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { exit(1) }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    return png
}

extension Data {
    mutating func appendU16LE(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }
    mutating func appendU32LE(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}

let sizes = [16, 32, 48, 256]
let pngs = sizes.map { renderPNG(size: $0) }

var ico = Data()

// ICONDIR (6 bytes)
ico.appendU16LE(0)                      // reserved
ico.appendU16LE(1)                      // type = 1 (icon)
ico.appendU16LE(UInt16(sizes.count))    // image count

let dirSize = 6 + 16 * sizes.count
var dataOffset = dirSize

// One ICONDIRENTRY (16 bytes) per image.
for (i, size) in sizes.enumerated() {
    let dim: UInt8 = (size >= 256) ? 0 : UInt8(size)
    ico.append(dim)             // width  (0 = 256)
    ico.append(dim)             // height (0 = 256)
    ico.append(0)               // color count (0 for true colour)
    ico.append(0)               // reserved
    ico.appendU16LE(1)          // planes
    ico.appendU16LE(32)         // bits per pixel
    ico.appendU32LE(UInt32(pngs[i].count))
    ico.appendU32LE(UInt32(dataOffset))
    dataOffset += pngs[i].count
}

// Image data, in directory order.
for png in pngs { ico.append(png) }

try ico.write(to: outURL)
print("Wrote \(outURL.path) (\(ico.count) bytes, \(sizes.count) sizes)")
