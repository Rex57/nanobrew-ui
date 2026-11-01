// Makes the app icon (D16): nanobrew's logo on a white macOS rounded square, no grid lines.
// Usage: swift scripts/make-icon.swift <logo.png> <out.png>   (1024x1024 master; bundle.sh makes the .icns)
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: make-icon.swift <logo.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's macOS icon grid: an 824-point square at 100 points from each edge, corner radius about 185.
let square = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: square, xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 20
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// The logo has a white (254) background: draw it larger than the square and clip, so its art fills about 70%.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
let logoSide: CGFloat = 1000
logo.draw(in: NSRect(x: (CGFloat(size) - logoSide) / 2, y: (CGFloat(size) - logoSide) / 2, width: logoSide, height: logoSide))
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
