import Foundation
import CoreGraphics
import ImageIO

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let width = size
let height = size

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Unable to create graphics context\n", stderr)
    exit(1)
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

let bounds = CGRect(x: 0, y: 0, width: width, height: height)

// Background with rounded corners.
let backgroundPath = CGPath(
    roundedRect: bounds.insetBy(dx: 18, dy: 18),
    cornerWidth: 220,
    cornerHeight: 220,
    transform: nil
)
context.saveGState()
context.addPath(backgroundPath)
context.clip()
let backgroundGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0.035, 0.055, 0.10), color(0.045, 0.16, 0.24)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 120, y: 900),
    end: CGPoint(x: 900, y: 80),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0.10, 0.65, 0.70, 0.35), color(0.10, 0.65, 0.70, 0)] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 300, y: 760),
    startRadius: 0,
    endCenter: CGPoint(x: 300, y: 760),
    endRadius: 520,
    options: []
)
context.restoreGState()

// Subtle inner border.
context.addPath(CGPath(
    roundedRect: bounds.insetBy(dx: 18, dy: 18),
    cornerWidth: 220,
    cornerHeight: 220,
    transform: nil
))
context.setStrokeColor(color(1, 1, 1, 0.10))
context.setLineWidth(4)
context.strokePath()

let center = CGPoint(x: 512, y: 500)
let radius: CGFloat = 292
let startAngle = CGFloat.pi * 20.0 / 180.0
let endAngle = CGFloat.pi * 160.0 / 180.0

// Gauge track.
context.setLineCap(.round)
context.setStrokeColor(color(1, 1, 1, 0.13))
context.setLineWidth(46)
context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
context.strokePath()

// Gauge progress (~38%).
let progressEnd = startAngle + (endAngle - startAngle) * 0.38
let progressGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0.20, 0.85, 0.85), color(0.35, 0.65, 1.0)] as CFArray,
    locations: [0, 1]
)!
context.saveGState()
context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: progressEnd, clockwise: false)
context.setLineWidth(46)
context.setLineCap(.round)
context.replacePathWithStrokedPath()
context.clip()
context.drawLinearGradient(
    progressGradient,
    start: CGPoint(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle)),
    end: CGPoint(x: center.x + radius * cos(progressEnd), y: center.y + radius * sin(progressEnd)),
    options: []
)
context.restoreGState()

// Tick marks.
for step in 0...7 {
    let angle = startAngle + (endAngle - startAngle) * CGFloat(step) / 7
    let inner = CGPoint(
        x: center.x + (radius - 44) * cos(angle),
        y: center.y + (radius - 44) * sin(angle)
    )
    let outer = CGPoint(
        x: center.x + (radius + 46) * cos(angle),
        y: center.y + (radius + 46) * sin(angle)
    )
    context.setStrokeColor(color(1, 1, 1, step == 2 ? 0.82 : 0.28))
    context.setLineWidth(step == 2 ? 14 : 8)
    context.setLineCap(.round)
    context.move(to: inner)
    context.addLine(to: outer)
    context.strokePath()
}

// Needle.
let needleAngle = startAngle + (endAngle - startAngle) * 0.38
let needleLength: CGFloat = 225
let needleTip = CGPoint(
    x: center.x + needleLength * cos(needleAngle),
    y: center.y + needleLength * sin(needleAngle)
)
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0, 0, 0, 0.45))
context.setStrokeColor(color(1.0, 0.62, 0.25))
context.setLineWidth(32)
context.setLineCap(.round)
context.move(to: center)
context.addLine(to: needleTip)
context.strokePath()
context.setShadow(offset: .zero, blur: 0, color: nil)

// Hub.
context.setFillColor(color(0.07, 0.12, 0.18))
context.fillEllipse(in: CGRect(x: center.x - 68, y: center.y - 68, width: 136, height: 136))
context.setFillColor(color(1.0, 0.62, 0.25))
context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))

// Small status LEDs.
let ledY: CGFloat = 238
for (index, ledColor) in [
    color(0.22, 0.82, 0.50),
    color(0.35, 0.65, 1.0),
    color(0.90, 0.45, 0.90)
].enumerated() {
    let x = center.x - 54 + CGFloat(index) * 54
    context.setFillColor(ledColor)
    context.fillEllipse(in: CGRect(x: x - 11, y: ledY - 11, width: 22, height: 22))
}

guard let image = context.makeImage() else {
    fputs("Unable to create image\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("Unable to create image destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write PNG\n", stderr)
    exit(1)
}
print("Wrote \(url.path)")
