import AppKit

// Export production sizes from the approved artwork without redrawing the mark.
guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: swift scripts/export_icon.swift artwork.png output-directory")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon-v2.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func export(_ size: Int, to url: URL, opaque: Bool = false) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
        pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    if opaque {
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
    }
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let encoded: NSBitmapImageRep
    if opaque {
        let rgb = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        rgb.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
        encoded = NSBitmapImageRep(cgImage: rgb.makeImage()!)
    } else {
        encoded = bitmap
    }
    try encoded.representation(using: .png, properties: [:])!.write(to: url)
}

for size in [16, 32, 128, 256, 512] {
    try export(size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try export(size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try export(1024, to: output.appendingPathComponent("app-icon-v2.png"), opaque: true)
try export(1024, to: output.appendingPathComponent("mac-icon-v2.png"))
print("Exported 16–1024 px representations to \(output.path)")
