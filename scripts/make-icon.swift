// Generates Resources/AppIcon.icns: Lucide "cctv" glyph (ISC) on a dark rounded square.
import AppKit

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
<path d="M16.75 12h3.632a1 1 0 0 1 .894 1.447l-2.034 4.069a1 1 0 0 1-1.708.134l-2.124-2.97"/>
<path d="M17.106 9.053a1 1 0 0 1 .447 1.341l-3.106 6.211a1 1 0 0 1-1.342.447L3.61 12.3a2.92 2.92 0 0 1-1.3-3.91L3.69 5.6a2.92 2.92 0 0 1 3.92-1.3z"/>
<path d="M2 19h3.76a2 2 0 0 0 1.8-1.1L9 15"/><path d="M2 21v-4"/><path d="M7 9h.01"/>
</svg>
"""

func render(_ px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size, flipped: false) { rect in
        let inset = rect.width * 0.08
        let body = rect.insetBy(dx: inset, dy: inset)
        let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
        NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.16, blue: 0.20, alpha: 1),
                            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1)])!.draw(in: shape, angle: -90)
        NSColor(white: 1, alpha: 0.10).setStroke(); shape.lineWidth = max(1, rect.width / 256); shape.stroke()

        let glyph = NSImage(data: Data(svg.utf8))!
        let g = body.width * 0.56
        let target = NSRect(x: body.midX - g / 2, y: body.midY - g / 2, width: g, height: g)
        let tinted = NSImage(size: target.size, flipped: false) { r in
            glyph.draw(in: r)
            NSColor(srgbRed: 0.31, green: 0.87, blue: 0.64, alpha: 1).set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: target)
        return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes { try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png")) }
