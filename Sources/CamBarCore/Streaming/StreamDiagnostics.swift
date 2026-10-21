import Foundation

/// What the camera reports about its stream, read from ffmpeg's log.
package struct StreamInfo: Equatable, Sendable {
    package var width = 0
    package var height = 0
    package var fps = 0.0
    package var codec = ""
    package var hasAudio = false

    package init(width: Int = 0, height: Int = 0, fps: Double = 0, codec: String = "", hasAudio: Bool = false) {
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.hasAudio = hasAudio
    }

    package var resolution: String { "\(width)×\(height)" }

    package var fpsText: String {
        fps == fps.rounded() ? "\(Int(fps))" : String(format: "%.1f", fps)
    }

    /// e.g. `1920×1080 • 15 FPS • H.265 Main`
    package var summary: String {
        "\(resolution) • \(fpsText) FPS" + (codec.isEmpty ? "" : " • \(codec)")
    }
}

/// Why a stream could not play, phrased for the user.
package enum StreamFailure: Equatable, Sendable {
    case unauthorized
    case pathNotFound
    case notRTSP
    case badRequest
    case unreachable
    case ffmpegMissing
    case launchFailed(String)
    case unknown

    package var title: String {
        switch self {
        case .unauthorized: return "Usuário ou senha incorretos"
        case .pathNotFound: return "Caminho RTSP não encontrado"
        case .notRTSP: return "A câmera não aceitou o RTSP"
        case .badRequest: return "A câmera recusou o pedido"
        case .unreachable: return "Câmera inacessível"
        case .ffmpegMissing: return "ffmpeg não encontrado"
        case .launchFailed: return "Não foi possível iniciar"
        case .unknown: return "Sem sinal"
        }
    }

    package var hint: String {
        switch self {
        case .unauthorized: return "Confira as credenciais em Gerenciar câmeras."
        case .pathNotFound: return "Verifique o caminho do stream, por exemplo /onvif1."
        case .notRTSP: return "A porta responde, mas não fala RTSP. Ative RTSP/ONVIF no app da câmera."
        case .badRequest: return "Costuma ser usuário ou caminho RTSP incorreto."
        case .unreachable: return "Confira o IP e se ela está ligada e na mesma rede."
        case .ffmpegMissing: return "Instale com: brew install ffmpeg"
        case .launchFailed(let reason): return reason
        case .unknown: return "Detalhes em ~/Library/Logs/CamBar.log"
        }
    }

    /// Maps ffmpeg's most relevant error line to something the user can act on.
    package static func classify(_ line: String) -> StreamFailure {
        let s = line.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains(where: s.contains) }

        if has("401", "403", "unauthorized", "forbidden") { return .unauthorized }
        if has("404", "not found") { return .pathNotFound }
        if has("405", "not one of 40", "method not allowed") { return .notRTSP }
        if has("400 bad request") { return .badRequest }
        if has("refused", "timed out", "unreachable", "no route") { return .unreachable }
        return .unknown
    }
}

/// Reads ffmpeg's stderr incrementally: stream telemetry plus the latest error line.
package struct FFmpegLogParser {
    package private(set) var info: StreamInfo?
    package private(set) var lastError = ""

    package init() {}

    /// Consumes a chunk of log text. Returns `true` when `info` changed.
    @discardableResult
    package mutating func consume(_ text: String) -> Bool {
        var changed = false
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            if line.contains("Stream #0:") {
                if line.contains("Video:"), !line.contains("mjpeg"), let video = Self.parseVideo(line) {
                    var updated = info ?? StreamInfo()
                    updated.width = video.width
                    updated.height = video.height
                    updated.fps = video.fps
                    updated.codec = video.codec
                    changed = changed || updated != info
                    info = updated
                } else if line.contains("Audio:"), info?.hasAudio != true {
                    var updated = info ?? StreamInfo()
                    updated.hasAudio = true
                    info = updated
                    changed = true
                }
            }
            if line.localizedCaseInsensitiveContains("error") || line.contains("RTSP/1.0 4") {
                lastError = line
            }
        }
        return changed
    }

    // MARK: Parsing

    private static let sizeRegex = try! NSRegularExpression(pattern: #"\b(\d{3,5})x(\d{3,5})\b"#)
    private static let fpsRegex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?) fps"#)
    private static let codecRegex = try! NSRegularExpression(pattern: #"Video: ([a-z0-9]+)(?: \(([^)]*)\))?"#)
    private static let codecNames = ["h264": "H.264", "hevc": "H.265"]

    /// Parses ffmpeg's input video line, e.g. `Stream #0:0: Video: h264 (Main), …, 2304x1296, 15 fps, …`.
    package static func parseVideo(_ line: String) -> (width: Int, height: Int, fps: Double, codec: String)? {
        guard let size = groups(sizeRegex, in: line), let rate = groups(fpsRegex, in: line),
              let width = Int(size[0]), let height = Int(size[1]), let fps = Double(rate[0]) else { return nil }
        var codec = ""
        if let c = groups(codecRegex, in: line) {
            let name = codecNames[c[0]] ?? c[0].uppercased()
            codec = c[1].isEmpty ? name : "\(name) \(c[1])"
        }
        return (width, height, fps, codec)
    }

    private static func groups(_ regex: NSRegularExpression, in line: String) -> [String]? {
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (1..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: line).map { String(line[$0]) } ?? ""
        }
    }
}
