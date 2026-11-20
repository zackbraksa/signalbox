import AppKit
import ImageIO

let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = project.appendingPathComponent("Assets/PorcelainGlassIcon.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                              bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    throw CocoaError(.fileReadCorruptFile)
}
// Match the classic macOS tile size and mask.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
context.addPath(CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(artwork, in: tile)
let output = project.appendingPathComponent("Assets/AppIcon.png")
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil),
      let rendered = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }

// Preserve the approved master exactly for the native default appearance.
let modernURL = project.appendingPathComponent("Assets/Signalbox.icon/Assets/Default.png")
try Data(contentsOf: sourceURL).write(to: modernURL, options: .atomic)
