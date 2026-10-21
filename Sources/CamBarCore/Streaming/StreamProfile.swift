/// How much of the camera's stream is decoded. The camera always sends its native frame rate;
/// the profile decides the output size and, in standby, decodes keyframes only (~1 fps), which is where the CPU goes.
package enum StreamProfile: Sendable, CaseIterable {
    /// Nobody is looking: keep the connection alive as cheaply as possible.
    case standby
    /// Popover, settings preview and overview tiles.
    case normal
    /// Expanded window.
    case hd

    package var maxWidth: Int {
        switch self {
        case .standby: return 480
        case .normal: return 720
        case .hd: return 1280
        }
    }

    /// ffmpeg `-q:v` for MJPEG (lower is better).
    package var jpegQuality: Int {
        switch self {
        case .standby: return 8
        case .normal: return 7
        case .hd: return 5
        }
    }

    package var decodesKeyframesOnly: Bool { self == .standby }
}
