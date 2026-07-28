import AppKit

guard CommandLine.arguments.count == 4,
      let size = Int(CommandLine.arguments[2]),
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: size,
          pixelsHigh: size,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
      ) else {
    fputs("usage: render-svg.swift input.svg size output.png\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
image.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

try data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
