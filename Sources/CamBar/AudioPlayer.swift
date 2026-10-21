import AVFoundation
import Foundation

/// Plays the camera's audio track: a second ffmpeg decodes it to raw PCM, played through AVAudioEngine.
final class AudioPlayer: ObservableObject {
    @Published private(set) var isOn = false

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var process: Process?
    private var leftover = Data()

    func toggle(camera: Camera, password: String) {
        isOn ? stop() : start(camera: camera, password: password)
    }

    func start(camera: Camera, password: String) {
        guard !isOn, let ffmpeg = CameraStream.ffmpegPath else { return }
        var transport: [String] = []
        if let t = camera.transport, ["tcp", "udp", "http"].contains(t) { transport = ["-rtsp_transport", t] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-loglevel", "quiet", "-fflags", "nobuffer"] + transport + [
            "-i", camera.rtspURL(password: password), "-vn", "-f", "s16le", "-ar", "16000", "-ac", "1", "pipe:1",
        ]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            if !chunk.isEmpty { self?.play(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            out.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { if self?.process === p { self?.teardown() } }
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            try p.run()
        } catch {
            engine.detach(node)
            return
        }
        node.play()
        process = p
        isOn = true
    }

    func stop() { teardown() }

    private func teardown() {
        let p = process
        process = nil
        p?.terminate()
        node.stop()
        engine.stop()
        if engine.attachedNodes.contains(node) { engine.detach(node) }
        leftover.removeAll()
        isOn = false
    }

    private func play(_ chunk: Data) {
        var data = leftover + chunk
        let usable = data.count - data.count % 2
        leftover = data.suffix(from: data.startIndex + usable)
        data = data.prefix(usable)
        let frames = usable / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let dst = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<frames { dst[i] = Float(Int16(littleEndian: src[i])) / 32768 }
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
    }

    deinit { process?.terminate() }
}
