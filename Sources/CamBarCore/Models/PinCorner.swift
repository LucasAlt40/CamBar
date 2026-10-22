import CoreGraphics
import Foundation

/// Screen corner where a camera can be pinned.
package enum PinCorner: String, Codable, CaseIterable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    package var label: String {
        switch self {
        case .topLeading: return "Superior esquerdo"
        case .topTrailing: return "Superior direito"
        case .bottomLeading: return "Inferior esquerdo"
        case .bottomTrailing: return "Inferior direito"
        }
    }

    package var isTop: Bool { self == .topLeading || self == .topTrailing }
    package var isLeading: Bool { self == .topLeading || self == .bottomLeading }

    /// The diagonally opposite corner, where the resize handle sits.
    package var opposite: PinCorner {
        switch self {
        case .topLeading: return .bottomTrailing
        case .topTrailing: return .bottomLeading
        case .bottomLeading: return .topTrailing
        case .bottomTrailing: return .topLeading
        }
    }

    package var symbol: String {
        switch self {
        case .topLeading: return "arrow.up.left"
        case .topTrailing: return "arrow.up.right"
        case .bottomLeading: return "arrow.down.left"
        case .bottomTrailing: return "arrow.down.right"
        }
    }
}

/// Where and how large the pinned camera is on a given screen.
package enum PinLayout {
    package static let margin: CGFloat = 16
    package static let aspectRatio: CGFloat = 16.0 / 9.0
    /// Below this the hover controls no longer fit.
    package static let minWidth: CGFloat = 240

    /// Largest width that still fits the screen with the margin around it.
    package static func maxWidth(in visible: CGRect) -> CGFloat {
        max(minWidth, min(visible.width - margin * 2, (visible.height - margin * 2) * aspectRatio).rounded(.down))
    }

    /// The user's width (from resizing) clamped to the screen, or the automatic size when there is none.
    package static func size(in visible: CGRect, width preferred: CGFloat?) -> CGSize {
        guard let preferred else { return size(in: visible) }
        let width = min(max(preferred, minWidth), maxWidth(in: visible)).rounded()
        return CGSize(width: width, height: (width / aspectRatio).rounded())
    }

    /// Width change for a drag of the resize handle by (dx, dy) in AppKit coordinates (y up).
    /// The drag is projected onto the window's diagonal, so the handle follows the pointer at 16:9
    /// and moving away from the pinned corner grows the picture.
    package static func widthChange(dx: CGFloat, dy: CGFloat, pinnedTo corner: PinCorner) -> CGFloat {
        let outX = corner.isLeading ? dx : -dx
        let outY = corner.isTop ? -dy : dy
        return (outX + outY / aspectRatio) / (1 + 1 / (aspectRatio * aspectRatio))
    }

    /// About a fifth of the screen width (never below 280 pt nor above 560 pt), and never taller than
    /// a third of the screen, so it stays a glanceable picture-in-picture on any display.
    package static func size(in visible: CGRect) -> CGSize {
        var width = min(max(visible.width * 0.2, 280), 560)
        width = min(width, visible.height / 3 * aspectRatio, visible.width - margin * 2)
        width = width.rounded()
        return CGSize(width: width, height: (width / aspectRatio).rounded())
    }

    /// Frame in AppKit coordinates (origin at the bottom left) inside the screen's visible area,
    /// which already excludes the menu bar and the Dock.
    package static func frame(for corner: PinCorner, in visible: CGRect, width: CGFloat? = nil) -> CGRect {
        let size = size(in: visible, width: width)
        let x: CGFloat, y: CGFloat
        switch corner {
        case .topLeading, .bottomLeading: x = visible.minX + margin
        case .topTrailing, .bottomTrailing: x = visible.maxX - margin - size.width
        }
        switch corner {
        case .bottomLeading, .bottomTrailing: y = visible.minY + margin
        case .topLeading, .topTrailing: y = visible.maxY - margin - size.height
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
