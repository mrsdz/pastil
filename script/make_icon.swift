#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Renders the Pastil app icon (1024×1024) to the PNG path given as argv[1].
// A warm liquid-glass squircle with a fanned stack of "clip" cards.

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "pastil_icon_1024.png"
let size: CGFloat = 1024

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fatalError("Could not create bitmap context")
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// ---- Tile (squircle) ----
let margin: CGFloat = 86
let tileRect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let tileRadius = tileRect.width * 0.2237
let tilePath = roundedRect(tileRect, tileRadius)

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// Warm sunset gradient (top → bottom).
let bg = CGGradient(
    colorsSpace: space,
    colors: [rgb(1.0, 0.80, 0.36), rgb(1.0, 0.52, 0.33), rgb(0.96, 0.34, 0.43)] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// Top glass highlight.
let sheen = CGGradient(
    colorsSpace: space,
    colors: [rgb(1, 1, 1, 0.34), rgb(1, 1, 1, 0)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: size * 0.52), options: [])
ctx.restoreGState()

// ---- Stacked clip cards ----
func drawCard(center: CGPoint, fill: CGColor, withLines: Bool) {
    let w: CGFloat = 332, h: CGFloat = 404, radius: CGFloat = 56
    let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 38, color: rgb(0, 0, 0, 0.20))
    ctx.addPath(roundedRect(rect, radius))
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()

    if withLines {
        ctx.setFillColor(rgb(0.45, 0.49, 0.57, 0.55))
        let inset: CGFloat = 50
        let lineX = rect.minX + inset
        let fullW = w - inset * 2
        let lines: [(CGFloat, CGFloat)] = [
            (rect.maxY - 104, fullW),
            (rect.maxY - 184, fullW),
            (rect.maxY - 264, fullW * 0.6)
        ]
        for (y, lw) in lines {
            ctx.addPath(roundedRect(CGRect(x: lineX, y: y, width: lw, height: 28), 14))
            ctx.fillPath()
        }
    }
}

let mid = CGPoint(x: size / 2, y: size / 2)
drawCard(center: CGPoint(x: mid.x + 48, y: mid.y + 50), fill: rgb(1, 1, 1, 0.42), withLines: false)
drawCard(center: CGPoint(x: mid.x + 16, y: mid.y + 14), fill: rgb(1, 1, 1, 0.72), withLines: false)
drawCard(center: CGPoint(x: mid.x - 26, y: mid.y - 28), fill: rgb(1, 1, 1, 0.98), withLines: true)

// ---- Export ----
guard let image = ctx.makeImage() else { fatalError("Could not render image") }
let url = URL(fileURLWithPath: outPath) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write PNG") }
print("Wrote \(outPath)")
