import AppKit

/// Menu bar item: camera glyph, "N ON" and a status dot. Colors resolve at draw time so it follows the menu bar appearance.
func statusBarImage(online: Int) -> NSImage {
    let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    let text = "\(online) ON" as NSString
    let textSize = text.size(withAttributes: [.font: font])
    let iconSize: CGFloat = 16, gap: CGFloat = 5, dot: CGFloat = 6
    let width = ceil(iconSize + gap + textSize.width + gap + dot + 2)

    let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
        let color = NSColor.labelColor
        let icon = securityCameraImage(size: iconSize)
        let tinted = NSImage(size: icon.size, flipped: false) { r in
            icon.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: 0, y: 1, width: iconSize, height: iconSize))
        text.draw(at: NSPoint(x: iconSize + gap, y: (rect.height - textSize.height) / 2),
                  withAttributes: [.font: font, .foregroundColor: color])
        (online > 0 ? NSColor(srgbRed: 0.06, green: 0.73, blue: 0.51, alpha: 1) : NSColor.systemGray).setFill()
        NSBezierPath(ovalIn: NSRect(x: width - dot - 2, y: (rect.height - dot) / 2, width: dot, height: dot)).fill()
        return true
    }
    image.isTemplate = false
    return image
}
