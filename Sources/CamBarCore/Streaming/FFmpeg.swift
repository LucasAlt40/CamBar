import Foundation

/// Locates the ffmpeg binary and builds its command lines.
package enum FFmpeg {
    package static let searchPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

    package static func locate(fileManager: FileManager = .default) -> URL? {
        searchPaths.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    /// RTSP in, MJPEG frames out on stdout. Hardware decoding, frames passed through as the camera sends them.
    package static func videoArguments(url: String, transport: RTSPTransport, profile: StreamProfile) -> [String] {
        ["-loglevel", "verbose", "-fflags", "nobuffer", "-flags", "low_delay", "-hwaccel", "videotoolbox"]
            + (profile.decodesKeyframesOnly ? ["-skip_frame", "nokey"] : [])
            + transport.ffmpegArguments
            + ["-i", url, "-an",
               "-vf", "scale='min(\(profile.maxWidth),iw)':-2",
               "-fps_mode", "passthrough",
               "-q:v", "\(profile.jpegQuality)",
               "-f", "mjpeg", "pipe:1"]
    }

    /// RTSP in, mono 16-bit little-endian PCM out on stdout.
    package static func audioArguments(url: String, transport: RTSPTransport, sampleRate: Int) -> [String] {
        ["-loglevel", "quiet", "-fflags", "nobuffer"]
            + transport.ffmpegArguments
            + ["-i", url, "-vn", "-f", "s16le", "-ar", "\(sampleRate)", "-ac", "1", "pipe:1"]
    }
}
