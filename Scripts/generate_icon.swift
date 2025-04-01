#!/usr/bin/env swift

import AppKit
import Foundation

// Generates the checked-in application icon with only Apple frameworks. Run from
// the repository root:
//
//   swift Scripts/generate_icon.swift
//   iconutil -c icns build/AppIcon.iconset -o MuonDetectorSimulator/Resources/AppIcon.icns
//
// The master artwork is 1024 x 1024 pixels and uses the standard macOS rounded
// square silhouette. The three horizontal GM tubes and diagonal particle track
// remain legible at Dock and Finder sizes.

let canvasSize = 1024.0
let outputDirectory = "build/icon"
let iconsetDirectory = "build/AppIcon.iconset"

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    return NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

func drawRoundedBackground() {
    let bounds = NSRect(x: 56, y: 56, width: 912, height: 912)
    let silhouette = NSBezierPath(roundedRect: bounds, xRadius: 196, yRadius: 196)

    NSGraphicsContext.saveGraphicsState()
    silhouette.addClip()

    let background = NSGradient(colorsAndLocations:
        (color(16, 42, 58), 0.0),
        (color(23, 73, 94), 0.46),
        (color(42, 104, 122), 1.0))!
    background.draw(in: silhouette, angle: -72)

    let glow = NSGradient(colors: [
        color(63, 202, 185, 0.32),
        color(63, 202, 185, 0.0),
    ])!
        glow.draw(in: NSRect(x: 300, y: 330, width: 620, height: 620),
                  relativeCenterPosition: NSPoint(x: 0.18, y: 0.22))

    // A quiet technical grid gives the icon depth without adding visual noise.
    NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.052).setStroke()
    for offset in stride(from: 146.0, through: 878.0, by: 52.0) {
        let horizontal = NSBezierPath()
        horizontal.move(to: NSPoint(x: 96, y: offset))
        horizontal.line(to: NSPoint(x: 928, y: offset))
        horizontal.lineWidth = 1
        horizontal.stroke()

        let vertical = NSBezierPath()
        vertical.move(to: NSPoint(x: offset, y: 96))
        vertical.line(to: NSPoint(x: offset, y: 928))
        vertical.lineWidth = 1
        vertical.stroke()
    }

    let topLight = NSGradient(colors: [
        color(255, 255, 255, 0.16),
        color(255, 255, 255, 0.0),
    ])!
    topLight.draw(in: NSRect(x: 56, y: 610, width: 912, height: 358), angle: 90)

    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.16).setStroke()
    silhouette.lineWidth = 4
    silhouette.stroke()
}

func drawTube(centerY: CGFloat, index: Int) {
    let bodyRect = NSRect(x: 174, y: centerY - 55, width: 676, height: 110)
    let body = NSBezierPath(roundedRect: bodyRect, xRadius: 55, yRadius: 55)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 10, 18, 0.42)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(74, 96, 108).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    let metal = NSGradient(colorsAndLocations:
        (color(245, 250, 252), 0.0),
        (color(213, 226, 233), 0.20),
        (color(139, 161, 173), 0.50),
        (color(83, 108, 122), 0.78),
        (color(186, 204, 213), 1.0))!
    metal.draw(in: body, angle: 90)

    // The translucent active gas volume is visible through the shell.
    let gasRect = NSRect(x: 214, y: centerY - 27, width: 596, height: 54)
    let gas = NSBezierPath(roundedRect: gasRect, xRadius: 27, yRadius: 27)
    let gasGradient = NSGradient(colorsAndLocations:
        (color(42, 199, 199, 0.20), 0.0),
        (color(57, 225, 198, 0.92), 0.50),
        (color(25, 158, 173, 0.20), 1.0))!
    gasGradient.draw(in: gas, angle: 90)
    color(150, 255, 236, 0.55).setStroke()
    gas.lineWidth = 2
    gas.stroke()

    let highlight = NSBezierPath(roundedRect:
        NSRect(x: 205, y: centerY + 23, width: 614, height: 17),
        xRadius: 8, yRadius: 8)
    color(255, 255, 255, 0.44).setFill()
    highlight.fill()
    NSGraphicsContext.restoreGraphicsState()

    color(26, 55, 68, 0.75).setStroke()
    body.lineWidth = 3
    body.stroke()

    // Dark ceramic end caps and their electrode collars.
    for x in [166.0, 812.0] {
        let capRect = NSRect(x: x, y: centerY - 63, width: 46, height: 126)
        let cap = NSBezierPath(roundedRect: capRect, xRadius: 17, yRadius: 17)
        let capGradient = NSGradient(colors: [
            color(49, 63, 71),
            color(109, 126, 134),
            color(30, 43, 51),
        ])!
        capGradient.draw(in: cap, angle: 90)
        color(12, 30, 38, 0.8).setStroke()
        cap.lineWidth = 2
        cap.stroke()

        let collar = NSBezierPath(roundedRect:
            NSRect(x: x + 38, y: centerY - 30, width: 16, height: 60),
            xRadius: 5, yRadius: 5)
        color(226, 238, 243, 0.78).setFill()
        collar.fill()
    }

    // Tiny ordinal marks make the stack read as three separate instruments.
    let label = "\(index)" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .semibold),
        .foregroundColor: color(255, 255, 255, 0.78),
    ]
    let labelSize = label.size(withAttributes: attributes)
    label.draw(at: NSPoint(x: 512 - labelSize.width / 2,
                           y: centerY - labelSize.height / 2 + 1),
               withAttributes: attributes)
}

func drawParticleTrack() {
    let start = NSPoint(x: 254, y: 892)
    let end = NSPoint(x: 774, y: 132)
    let track = NSBezierPath()
    track.move(to: start)
    track.line(to: end)

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(61, 255, 154, 0.72)
    glow.shadowBlurRadius = 30
    glow.shadowOffset = .zero
    glow.set()
    color(94, 255, 171, 0.95).setStroke()
    track.lineWidth = 10
    track.lineCapStyle = .round
    track.stroke()
    NSGraphicsContext.restoreGraphicsState()

    color(216, 255, 228, 0.92).setStroke()
    let core = NSBezierPath()
    core.move(to: start)
    core.line(to: end)
    core.lineWidth = 3.2
    core.lineCapStyle = .round
    core.stroke()

    // Bright crossings suggest pulses in each active volume.
    for y in [354.0, 512.0, 670.0] as [CGFloat] {
        let t = (y - start.y) / (end.y - start.y)
        let x = start.x + (end.x - start.x) * t
        let haloRect = NSRect(x: x - 31, y: y - 31, width: 62, height: 62)
        let halo = NSBezierPath(ovalIn: haloRect)
        color(62, 255, 184, 0.20).setFill()
        halo.fill()

        let dot = NSBezierPath(ovalIn:
            NSRect(x: x - 11, y: y - 11, width: 22, height: 22))
        color(225, 255, 236, 0.96).setFill()
        dot.fill()
        color(55, 218, 153, 0.95).setStroke()
        dot.lineWidth = 3
        dot.stroke()
    }
}

func renderMaster() -> NSImage {
    let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

    drawRoundedBackground()
    drawTube(centerY: 354, index: 3)
    drawTube(centerY: 512, index: 2)
    drawTube(centerY: 670, index: 1)
    drawParticleTrack()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String, pixelSize: Int) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: outputDirectory,
                                 withIntermediateDirectories: true)
try? fileManager.removeItem(atPath: iconsetDirectory)
try fileManager.createDirectory(atPath: iconsetDirectory,
                                withIntermediateDirectories: true)

let image = renderMaster()
let masterPath = "\(outputDirectory)/AppIcon-1024.png"
try writePNG(image, to: masterPath, pixelSize: 1024)

let entries: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixelSize, name) in entries {
    let destination = "\(iconsetDirectory)/\(name)"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(pixelSize)", "\(pixelSize)",
                         masterPath, "--out", destination]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "IconGenerator", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "sips failed for \(name)"])
    }
}

print("Wrote \(masterPath) and \(iconsetDirectory)")






