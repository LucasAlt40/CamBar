import AppKit
import Foundation
import ImageIO

/// Decodes an RTSP stream by piping it through ffmpeg as MJPEG and splitting the JPEG frames.
final class CameraStream: ObservableObject {
    struct Failure: Equatable { var title: String; var hint: String }
    enum Status: Equatable { case idle, connecting, live, failed(Failure) }

    /// What the camera reports about its own stream (parsed from ffmpeg's log).
    struct Info: Equatable {
        var width = 0, height = 0
        var fps = 0.0
        var codec = ""
        var hasAudio = false
        var summary: String {
            let fpsText = fps == fps.rounded() ? "\(Int(fps))" : String(format: "%.1f", fps)
            return "\(width)×\(height) • \(fpsText) FPS" + (codec.isEmpty ? "" : " • \(codec)")
        }
    }

    @Published var info: Info?
    @Published var frame: NSImage?
    @Published var status: Status = .idle

    private var process: Process?
    private var wanted = false
    private let viewersLock = NSLock()
    private var _viewers = 0

    /// Number of views showing this stream.
    var viewers: Int {
        get { viewersLock.lock(); defer { viewersLock.unlock() }; return _viewers }
        set { viewersLock.lock(); _viewers = newValue; viewersLock.unlock() }
    }
    var isActive: Bool { wanted }

    /// Resolution/frame-rate presets. The camera itself sends 15 fps, so `normal` and `hd` use all of it;
    /// `standby` keeps the connection alive cheaply while nobody is looking.
    enum Profile {
        case standby, normal, hd
        var width: Int { self == .hd ? 1280 : self == .normal ? 720 : 480 }
        /// Standby is throttled; otherwise frames pass through exactly as the camera sends them.
        var rateArgs: [String] { self == .standby ? ["-r", "2"] : ["-fps_mode", "passthrough"] }
        var quality: Int { self == .hd ? 5 : self == .normal ? 7 : 8 }
    }
    var profile: Profile = .normal
    private var generation = 0
    private var lastError = ""

    static var ffmpegPath: String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    func start(camera: Camera, password: String, keepFrame: Bool = false) {
        stop(clearFrame: !keepFrame)
        Self.resetLog()
        wanted = true
        generation += 1
        launch(url: camera.rtspURL(password: password), transport: camera.transport, gen: generation)
    }

    func restart(camera: Camera, password: String) {
        guard wanted else { return }
        start(camera: camera, password: password)
    }

    func stop(clearFrame: Bool = true) {
        wanted = false
        generation += 1
        process?.terminate()
        process = nil
        if clearFrame { DispatchQueue.main.async { self.status = .idle; self.frame = nil; self.info = nil } }
    }

    private func launch(url: String, transport: String?, gen: Int) {
        guard let ffmpeg = Self.ffmpegPath else {
            DispatchQueue.main.async { self.status = .failed(Failure(title: "ffmpeg não encontrado", hint: "Instale com: brew install ffmpeg")) }
            return
        }
        DispatchQueue.main.async { self.status = .connecting }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        var transportArgs: [String] = []
        if let t = transport, ["tcp", "udp", "http"].contains(t) { transportArgs = ["-rtsp_transport", t] }
        p.arguments = [
            "-loglevel", "verbose", "-fflags", "nobuffer", "-flags", "low_delay",
            "-hwaccel", "videotoolbox",
        ] + transportArgs + [
            "-i", url, "-an",
            "-vf", "scale='min(\(profile.width),iw)':-2",
        ] + profile.rateArgs + [
            "-q:v", "\(profile.quality)", "-f", "mjpeg", "pipe:1",
        ]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        lastError = ""

        var buffer = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { return }
            buffer.append(chunk)
            var latest: NSImage?
            while let start = buffer.firstRange(of: Data([0xFF, 0xD8])),
                  let end = buffer.firstRange(of: Data([0xFF, 0xD9]), in: start.upperBound..<buffer.endIndex) {
                let jpeg = buffer.subdata(in: start.lowerBound..<end.upperBound)
                buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                if let img = Self.decode(jpeg) { latest = img }
            }
            if buffer.count > 8_000_000 { buffer.removeAll() }
            if let img = latest {
                DispatchQueue.main.async {
                    guard self.generation == gen else { return }
                    self.frame = img
                    self.status = .live
                }
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard let s = String(data: d, encoding: .utf8), !s.isEmpty else { return }
            Self.appendLog(s)
            let lines = s.split(separator: "\n").map(String.init)
            for line in lines where line.contains("Stream #0:") {
                if line.contains("Video:"), !line.contains("mjpeg"), let v = Self.parseVideo(line) {
                    DispatchQueue.main.async { var i = self?.info ?? Info(); i.width = v.width; i.height = v.height; i.fps = v.fps; i.codec = v.codec; self?.info = i }
                } else if line.contains("Audio:") {
                    DispatchQueue.main.async { var i = self?.info ?? Info(); i.hasAudio = true; self?.info = i }
                }
            }
            if let e = lines.last(where: { $0.contains("Error") || $0.contains("error") || $0.contains("RTSP/1.0 4") }) {
                self?.lastError = e
            }
        }
        p.terminationHandler = { [weak self] _ in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.wanted, self.generation == gen else { return }
                self.status = .failed(self.friendlyError(self.lastError))
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    guard self.wanted, self.generation == gen else { return }
                    // nobody is watching a failing camera: stop retrying until a view asks for it again
                    if self.viewers == 0 { self.wanted = false; return }
                    self.launch(url: url, transport: transport, gen: gen)
                }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            DispatchQueue.main.async { self.status = .failed(Failure(title: "Não foi possível iniciar", hint: error.localizedDescription)) }
        }
    }

    /// Decodes on the reader thread so the main thread only has to draw.
    private static func decode(_ data: Data) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func parseVideo(_ line: String) -> Info? {
        func match(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
            return (1..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: line).map { String(line[$0]) } ?? ""
            }
        }
        guard let size = match(#"\b(\d{3,5})x(\d{3,5})\b"#), let fps = match(#"(\d+(?:\.\d+)?) fps"#),
              let w = Int(size[0]), let h = Int(size[1]), let f = Double(fps[0]) else { return nil }
        var codec = ""
        if let c = match(#"Video: ([a-z0-9]+)(?: \(([^)]*)\))?"#) {
            let name = ["h264": "H.264", "hevc": "H.265"][c[0]] ?? c[0].uppercased()
            codec = c[1].isEmpty ? name : "\(name) \(c[1])"
        }
        return Info(width: w, height: h, fps: f, codec: codec)
    }

    static let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/CamBar.log")

    private static func resetLog() {
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: logURL)
    }

    /// Appends ffmpeg output to the log with any rtsp credentials masked.
    private static func appendLog(_ text: String) {
        let masked = text.replacingOccurrences(of: "://[^/@\\s]*@", with: "://***@", options: .regularExpression)
        guard let data = masked.data(using: .utf8), let h = try? FileHandle(forWritingTo: logURL) else { return }
        h.seekToEndOfFile(); h.write(data); try? h.close()
    }

    private func friendlyError(_ raw: String) -> Failure {
        let s = raw.lowercased()
        if s.contains("401") || s.contains("403") || s.contains("unauthorized") || s.contains("forbidden") {
            return Failure(title: "Usuário ou senha incorretos", hint: "Confira as credenciais em Gerenciar câmeras.")
        }
        if s.contains("404") || s.contains("not found") {
            return Failure(title: "Caminho RTSP não encontrado", hint: "Verifique o caminho do stream, por exemplo /onvif1.")
        }
        if s.contains("405") || s.contains("not one of 40") || s.contains("method not allowed") {
            return Failure(title: "A câmera não aceitou o RTSP", hint: "A porta responde, mas não fala RTSP. Ative RTSP/ONVIF no app da câmera.")
        }
        if s.contains("refused") || s.contains("timed out") || s.contains("unreachable") || s.contains("no route") {
            return Failure(title: "Câmera inacessível", hint: "Confira o IP e se ela está ligada e na mesma rede.")
        }
        return Failure(title: "Sem sinal", hint: "Detalhes em ~/Library/Logs/CamBar.log")
    }
}
