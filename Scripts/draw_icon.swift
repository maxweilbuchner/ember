// draw_icon.swift — renders the Ember botanical-flame app icon (1024x1024 PNG)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    )!
}

// MARK: Background — warm charcoal with a soft ember glow low-center
ctx.setFillColor(color(0x1F1B16))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let glow = CGGradient(
    colorsSpace: space,
    colors: [color(0xE8863A, 0.22), color(0xE8863A, 0.0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 512, y: 400), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 400), endRadius: 460,
    options: []
)

// MARK: Flame silhouette (CG coords: y-up). Tip top ~y=860, base bottom ~y=190.
let flame = CGMutablePath()
flame.move(to: CGPoint(x: 512, y: 862))                                   // tip
flame.addCurve(to: CGPoint(x: 726, y: 400),
               control1: CGPoint(x: 564, y: 742), control2: CGPoint(x: 726, y: 560))
flame.addCurve(to: CGPoint(x: 512, y: 186),
               control1: CGPoint(x: 726, y: 268), control2: CGPoint(x: 646, y: 186))
flame.addCurve(to: CGPoint(x: 298, y: 400),
               control1: CGPoint(x: 378, y: 186), control2: CGPoint(x: 298, y: 268))
flame.addCurve(to: CGPoint(x: 468, y: 700),
               control1: CGPoint(x: 298, y: 536), control2: CGPoint(x: 418, y: 622))
flame.addCurve(to: CGPoint(x: 512, y: 862),
               control1: CGPoint(x: 498, y: 748), control2: CGPoint(x: 486, y: 800))
flame.closeSubpath()

// MARK: Leaf cutout — pointed oval, its tip echoing the flame tip; short stem.
let leaf = CGMutablePath()
leaf.move(to: CGPoint(x: 512, y: 660))                                    // leaf tip
leaf.addCurve(to: CGPoint(x: 512, y: 320),
              control1: CGPoint(x: 634, y: 566), control2: CGPoint(x: 608, y: 372))
leaf.addCurve(to: CGPoint(x: 512, y: 660),
              control1: CGPoint(x: 416, y: 372), control2: CGPoint(x: 390, y: 566))
leaf.closeSubpath()
// stem
leaf.addRect(CGRect(x: 503, y: 252, width: 18, height: 84))

// MARK: Fill flame-minus-leaf with amber→terracotta gradient (even-odd clip)
ctx.saveGState()
let combined = CGMutablePath()
combined.addPath(flame)
combined.addPath(leaf)
ctx.addPath(combined)
ctx.clip(using: .evenOdd)

let fill = CGGradient(
    colorsSpace: space,
    colors: [color(0xF2B052), color(0xE8863A), color(0xC75B39)] as CFArray,
    locations: [0, 0.45, 1]
)!
ctx.drawLinearGradient(
    fill,
    start: CGPoint(x: 512, y: 880), end: CGPoint(x: 512, y: 170),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

// MARK: Write PNG
let image = ctx.makeImage()!
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"
let url = URL(fileURLWithPath: outPath) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fatalError("failed to write png")
}
print("wrote \(outPath)")
