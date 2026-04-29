#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders a 1024x1024 macOS-style app icon for recmeet:
//   • dark rounded-rect background with a subtle vertical gradient
//   • thin white ring (the “recording disc” cue)
//   • red record dot in the centre with a soft radial highlight
//
// Usage:  swift make-icon.swift <output.png>

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let size: CGFloat = 1024
let cornerRadius: CGFloat = 225
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("CGContext creation failed\n", stderr)
    exit(1)
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let center = CGPoint(x: size / 2, y: size / 2)

// 1. Background: rounded rect filled with a dark vertical gradient.
let bgPath = CGMutablePath()
bgPath.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

let bgColors = [
    CGColor(srgbRed: 0.173, green: 0.173, blue: 0.184, alpha: 1.0), // top  #2C2C2F
    CGColor(srgbRed: 0.039, green: 0.039, blue: 0.047, alpha: 1.0), // bottom #0A0A0C
] as CFArray
let bgGradient = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
)
ctx.restoreGState()

// 2. Outer white ring.
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
ctx.setLineWidth(28)
ctx.addArc(center: center, radius: 360, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// 3. Red record dot with radial highlight.
let dotRadius: CGFloat = 200
ctx.saveGState()
ctx.addArc(center: center, radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.clip()

let redColors = [
    CGColor(srgbRed: 1.00, green: 0.42, blue: 0.38, alpha: 1.0), // highlight
    CGColor(srgbRed: 0.92, green: 0.22, blue: 0.20, alpha: 1.0), // body
    CGColor(srgbRed: 0.65, green: 0.08, blue: 0.08, alpha: 1.0), // edge shadow
] as CFArray
let redGradient = CGGradient(colorsSpace: cs, colors: redColors, locations: [0, 0.55, 1])!
ctx.drawRadialGradient(
    redGradient,
    startCenter: CGPoint(x: center.x - 70, y: center.y + 70),
    startRadius: 0,
    endCenter: center,
    endRadius: dotRadius,
    options: []
)
ctx.restoreGState()

// Soft glow halo just inside the ring, behind the dot — adds depth.
ctx.saveGState()
ctx.addArc(center: center, radius: 340, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.20, blue: 0.20, alpha: 0.10))
ctx.setLineWidth(48)
ctx.strokePath()
ctx.restoreGState()

// 4. Encode and save PNG.
guard let cgImage = ctx.makeImage() else {
    fputs("makeImage failed\n", stderr)
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("PNG encoding failed\n", stderr)
    exit(1)
}
try png.write(to: outputURL)
print("Wrote \(outputURL.path)")
