import AVFoundation
import CamBarCore

/// Plays a camera's audio track. A second ffmpeg decodes it to PCM, played through AVAudioEngine.
@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

    private static let sampleRate = 16_000
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
    private var process: FFmpegProcess?

    func start(camera: Camera, password: String) {
        guard !isPlaying, let ffmpeg = FFmpeg.locate() else { return }
        let arguments = FFmpeg.audioArguments(url: camera.rtspURL(password: password),
                                              transport: camera.transport, sampleRate: Self.sampleRate)
        let run = FFmpegProcess(executable: ffmpeg, arguments: arguments)
        let sink = PCMSink(node: node, format: format)

        var handlers = FFmpegProcess.Handlers()
        handlers.output = { data in sink.play(data) }
        handlers.exit = { [weak self, weak run] in
            Task { @MainActor in
                guard let self, run != nil, self.process === run else { return }
                self.stop()
            }
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            try run.run(handlers)
        } catch {
            engine.detach(node)
            return
        }
        node.play()
        process = run
        isPlaying = true
    }

    func stop() {
        process?.terminate()
        process = nil
        node.stop()
        engine.stop()
        if engine.attachedNodes.contains(node) { engine.detach(node) }
        isPlaying = false
    }
}

/// Converts PCM chunks and schedules them on the player node straight from ffmpeg's reader thread
/// (scheduling is thread-safe and avoids gaps caused by main-thread hiccups).
private final class PCMSink: @unchecked Sendable {
    private var converter = PCMConverter()
    private let node: AVAudioPlayerNode
    private let format: AVAudioFormat

    init(node: AVAudioPlayerNode, format: AVAudioFormat) {
        self.node = node
        self.format = format
    }

    func play(_ data: Data) {
        let samples = converter.convert(data)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        node.scheduleBuffer(buffer)
    }
}
