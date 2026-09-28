import Cocoa
import CoreGraphics

func generateAppIcon() {
    let size = CGSize(width: 1024, height: 1024)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let ctx = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        print("Failed to create CGContext")
        return
    }

    let rect = CGRect(origin: .zero, size: size)

    // Clear context
    ctx.clear(rect)

    // 1. App Icon Rounded Rect (macOS standard squircle corner radius ~ 224 for 1024x1024)
    let iconBounds = rect.insetBy(dx: 90, dy: 90)
    let cornerRadius: CGFloat = 190.0
    let squirclePath = CGPath(roundedRect: iconBounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Vibrant Screens-style blue to deep indigo/purple gradient
    let colors = [
        NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.98, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.28, green: 0.20, blue: 0.85, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.42, green: 0.12, blue: 0.78, alpha: 1.0).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!

    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 934), end: CGPoint(x: 512, y: 90), options: [])

    // Glass sheen / highlight
    let sheenRect = CGRect(x: iconBounds.minX, y: iconBounds.midY, width: iconBounds.width, height: iconBounds.height / 2)
    let sheenColors = [
        NSColor(white: 1.0, alpha: 0.25).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    let sheenGradient = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(sheenGradient, start: CGPoint(x: 512, y: iconBounds.maxY), end: CGPoint(x: 512, y: iconBounds.midY), options: [])

    // 2. Draw Remote Desktop Screens monitor inside
    let monitorRect = CGRect(x: 230, y: 350, width: 564, height: 380)
    let monitorPath = CGPath(roundedRect: monitorRect, cornerWidth: 28, cornerHeight: 28, transform: nil)

    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.18, alpha: 0.95).cgColor)
    ctx.addPath(monitorPath)
    ctx.fillPath()

    // Monitor Screen border
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.3).cgColor)
    ctx.setLineWidth(6.0)
    ctx.addPath(monitorPath)
    ctx.strokePath()

    // Inner Desktop Viewport (Cyan / Blue wallpaper look)
    let screenGlass = monitorRect.insetBy(dx: 14, dy: 14)
    let glassPath = CGPath(roundedRect: screenGlass, cornerWidth: 16, cornerHeight: 16, transform: nil)
    ctx.saveGState()
    ctx.addPath(glassPath)
    ctx.clip()

    let screenColors = [
        NSColor(calibratedRed: 0.10, green: 0.60, blue: 0.95, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.40, green: 0.20, blue: 0.85, alpha: 1.0).cgColor
    ] as CFArray
    let screenGrad = CGGradient(colorsSpace: colorSpace, colors: screenColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(screenGrad, start: CGPoint(x: 512, y: screenGlass.maxY), end: CGPoint(x: 512, y: screenGlass.minY), options: [])

    // Top menu bar line on screen
    let menuBar = CGRect(x: screenGlass.minX, y: screenGlass.maxY - 18, width: screenGlass.width, height: 18)
    ctx.setFillColor(NSColor(white: 1.0, alpha: 0.25).cgColor)
    ctx.fill(menuBar)

    // Cursor arrow in center
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.setShadow(offset: CGSize(width: 2, height: -4), blur: 8, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    let cursorPath = CGMutablePath()
    cursorPath.move(to: CGPoint(x: 500, y: 550))
    cursorPath.addLine(to: CGPoint(x: 535, y: 515))
    cursorPath.addLine(to: CGPoint(x: 518, y: 515))
    cursorPath.addLine(to: CGPoint(x: 532, y: 485))
    cursorPath.addLine(to: CGPoint(x: 518, y: 478))
    cursorPath.addLine(to: CGPoint(x: 504, y: 508))
    cursorPath.addLine(to: CGPoint(x: 500, y: 495))
    cursorPath.closeSubpath()
    ctx.addPath(cursorPath)
    ctx.fillPath()

    ctx.restoreGState() // unclip screen glass

    // Monitor stand
    let standRect = CGRect(x: 482, y: 260, width: 60, height: 90)
    ctx.setFillColor(NSColor(white: 0.85, alpha: 0.9).cgColor)
    ctx.fill(standRect)

    let standBase = CGRect(x: 432, y: 245, width: 160, height: 18)
    let standBasePath = CGPath(roundedRect: standBase, cornerWidth: 9, cornerHeight: 9, transform: nil)
    ctx.addPath(standBasePath)
    ctx.fillPath()

    ctx.restoreGState() // unclip squircle

    // 3. Squircle Outer Subtle Rim Highlight
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.25).cgColor)
    ctx.setLineWidth(4.0)
    ctx.strokePath()

    guard let cgImage = ctx.makeImage() else {
        print("Failed to make image from context")
        return
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to get PNG data")
        return
    }

    let outURL = URL(fileURLWithPath: "AppIcon_1024.png")
    try? pngData.write(to: outURL)
    print("Generated AppIcon_1024.png successfully")
}

generateAppIcon()
