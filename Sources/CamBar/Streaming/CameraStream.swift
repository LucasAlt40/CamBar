import AppKit
import CamBarCore
import ImageIO

/// Live picture of one camera: runs ffmpeg, publishes decoded frames, telemetry and status,
/// and retries with backoff while somebody is watching.
@MainActor
final class CameraStream: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, live
        case failed(StreamFailure)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var frame: NSImage?
    @Published private(set) var info: StreamInfo?

    private(set) var profile: StreamProfile = .normal
    private(set) var isRunning = false
    /// A failing stream nobody is watching stops retrying until a view asks for it again.
    var isWatched = true

    private var camera: Camera
    private var password = ""
    private var process: FFmpegProcess?
    private var logParser = FFmpegLogParser()
    private var retryTask: Task<Void, Never>?
    private var failedAttempts = 0
    private let log: FileLog?

    init(camera: Camera, log: FileLog?) {
        self.camera = camera
        self.log = log
    }

    /// (Re)starts the stream. `keepFrame` leaves the last picture on screen while reconnecting.
    func start(camera: Camera, password: String, profile: StreamProfile, keepFrame: Bool = false) {
        stop(clearing: !keepFrame)
        self.camera = camera
        self.password = password
        self.profile = profile
        isRunning = true
        failedAttempts = 0
        launch()
    }

    func stop(clearing: Bool = true) {
        isRunning = false
        retryTask?.cancel()
        retryTask = nil
        process?.terminate()
        process = nil
        if clearing {
            status = .idle
            frame = nil
            info = nil
        }
    }

    // MARK: Process lifecycle

    private func launch() {
        guard let ffmpeg = FFmpeg.locate() else {
            isRunning = false
            status = .failed(.ffmpegMissing)
            return
        }
        status = .connecting
        logParser = FFmpegLogParser()

        let arguments = FFmpeg.videoArguments(url: camera.rtspURL(password: password),
                                              transport: camera.transport, profile: profile)
        let run = FFmpegProcess(executable: ffmpeg, arguments: arguments)
        let frames = FrameExtractor()
        let log = log
        let tag = camera.name

        var handlers = FFmpegProcess.Handlers()
        handlers.output = { [weak self, weak run] data in
            guard let image = frames.latestImage(after: data) else { return }
            Task { @MainActor in self?.receive(image, from: run) }
        }
        handlers.log = { [weak self, weak run] text in
            log?.append(text, tag: tag)
            Task { @MainActor in self?.receiveLog(text, from: run) }
        }
        handlers.exit = { [weak self, weak run] in
            Task { @MainActor in self?.processExited(run) }
        }

        do {
            try run.run(handlers)
            process = run
        } catch {
            isRunning = false
            status = .failed(.launchFailed(error.localizedDescription))
        }
    }

    private func receive(_ image: CGImage, from run: FFmpegProcess?) {
        guard run != nil, run === process else { return }
        frame = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        if status != .live { status = .live }
        failedAttempts = 0
    }

    private func receiveLog(_ text: String, from run: FFmpegProcess?) {
        guard run != nil, run === process else { return }
        if logParser.consume(text) { info = logParser.info }
    }

    private func processExited(_ run: FFmpegProcess?) {
        guard run != nil, run === process, isRunning else { return }
        process = nil
        logParser.finish()
        status = .failed(StreamFailure.classify(logParser.lastError))
        scheduleRetry()
    }

    /// Exponential backoff: 2, 4, 8, 16, then every 30 seconds.
    private func scheduleRetry() {
        guard isWatched else {
            isRunning = false
            return
        }
        failedAttempts += 1
        let delay = min(30, Double(1 << min(failedAttempts, 5)))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isRunning else { return }
            if self.isWatched { self.launch() } else { self.isRunning = false }
        }
    }
}

/// Collects MJPEG bytes on ffmpeg's reader thread and decodes only the newest complete frame,
/// so the main thread just draws.
private final class FrameExtractor: @unchecked Sendable {
    private var parser = MJPEGParser()

    func latestImage(after data: Data) -> CGImage? {
        guard let jpeg = parser.append(data).last,
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
