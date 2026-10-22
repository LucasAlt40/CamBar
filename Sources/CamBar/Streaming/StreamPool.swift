import AppKit
import CamBarCore
import Combine

/// Shares one stream per camera between every view that shows it (lease pattern) and decides its profile:
/// HD while an expanded window wants it, normal while visible, standby (keyframes only) when nobody looks.
@MainActor
final class StreamPool: ObservableObject {
    private enum Keys { static let keepConnected = "keepConnected" }

    /// Keep streams connected after the popover closes. Off: they stop `idleGrace` after the last viewer leaves.
    @Published var keepConnected: Bool {
        didSet {
            defaults.set(keepConnected, forKey: Keys.keepConnected)
            reevaluateAll()
        }
    }

    /// While the popover is open every connected camera runs at normal quality, so tab switches are instant.
    @Published var panelOpen = false {
        didSet { reevaluateAll() }
    }

    /// With the displays asleep nobody can see a frame, so every stream drops to standby (still connected).
    private var displaysAsleep = false {
        didSet { reevaluateAll() }
    }

    @MainActor
    private final class Entry {
        let stream: CameraStream
        var camera: Camera
        var leases = 0
        var hdLeases = 0
        var idleStop: Task<Void, Never>?

        init(camera: Camera, log: FileLog?) {
            self.camera = camera
            stream = CameraStream(camera: camera, log: log)
        }
    }

    private var entries: [UUID: Entry] = [:]
    private let credentials: CredentialStore
    private let defaults: UserDefaults
    private let log: FileLog?
    private let idleGrace: Duration
    private var subscriptions: Set<AnyCancellable> = []

    init(store: CameraStore, credentials: CredentialStore, defaults: UserDefaults = .standard,
         log: FileLog?, idleGrace: Duration = .seconds(60)) {
        self.credentials = credentials
        self.defaults = defaults
        self.log = log
        self.idleGrace = idleGrace
        keepConnected = defaults.object(forKey: Keys.keepConnected) as? Bool ?? true
        store.changes.sink { [weak self] change in self?.apply(change) }.store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in self?.displaysAsleep = true }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in self?.displaysAsleep = false }.store(in: &subscriptions)
    }

    // MARK: Leases

    func lease(_ camera: Camera, hd: Bool = false) -> StreamLease {
        let entry = entries[camera.id] ?? makeEntry(for: camera)
        entry.leases += 1
        if hd { entry.hdLeases += 1 }
        reevaluate(entry)
        return StreamLease(stream: entry.stream, cameraID: camera.id, hd: hd, pool: self)
    }

    fileprivate func release(_ lease: StreamLease) {
        guard let entry = entries[lease.cameraID], entry.leases > 0 else { return }
        entry.leases -= 1
        if lease.hd { entry.hdLeases = max(0, entry.hdLeases - 1) }
        reevaluate(entry)
    }

    fileprivate func lease(_ lease: StreamLease, didChangeHD hd: Bool) {
        guard let entry = entries[lease.cameraID] else { return }
        entry.hdLeases = max(0, entry.hdLeases + (hd ? 1 : -1))
        reevaluate(entry)
    }

    // MARK: Commands

    func reconnect(_ id: UUID) {
        guard let entry = entries[id] else { return }
        start(entry)
    }

    func reconnectAll() {
        entries.values.filter { $0.leases > 0 || $0.stream.isRunning }.forEach { start($0) }
    }

    /// Stops every ffmpeg process (app quitting).
    func shutdown() {
        entries.values.forEach {
            $0.idleStop?.cancel()
            $0.stream.stop()
        }
    }

    // MARK: Policy

    private func makeEntry(for camera: Camera) -> Entry {
        let entry = Entry(camera: camera, log: log)
        entries[camera.id] = entry
        return entry
    }

    private func apply(_ change: CameraChange) {
        switch change {
        case .updated(let camera):
            guard let entry = entries[camera.id] else { return }
            entry.camera = camera
            // a watched stream that gave up (e.g. launch failed) gets another chance with the new settings
            if entry.stream.isRunning || entry.leases > 0 { start(entry) }
        case .removed(let id):
            entries[id]?.idleStop?.cancel()
            entries[id]?.stream.stop()
            entries[id] = nil
        }
    }

    private func profile(for entry: Entry) -> StreamProfile {
        if displaysAsleep { return .standby }
        if entry.hdLeases > 0 { return .hd }
        if panelOpen || entry.leases > 0 || !keepConnected { return .normal }
        return .standby
    }

    private func reevaluate(_ entry: Entry) {
        let stream = entry.stream
        stream.isWatched = entry.leases > 0

        if entry.leases > 0 || keepConnected {
            entry.idleStop?.cancel()
            entry.idleStop = nil
        }

        if entry.leases > 0, !stream.isRunning {
            start(entry)
        } else if stream.isRunning, stream.profile != profile(for: entry) {
            start(entry, keepFrame: true)
        }

        if entry.leases == 0, !keepConnected, stream.isRunning, entry.idleStop == nil {
            scheduleIdleStop(entry)
        }
    }

    private func reevaluateAll() { entries.values.forEach(reevaluate) }

    private func start(_ entry: Entry, keepFrame: Bool = false) {
        entry.stream.start(camera: entry.camera, password: credentials.password(for: entry.camera.id),
                           profile: profile(for: entry), keepFrame: keepFrame)
    }

    private func scheduleIdleStop(_ entry: Entry) {
        let grace = idleGrace
        entry.idleStop = Task { [weak self, weak entry] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, let self, let entry, entry.leases == 0, !self.keepConnected else { return }
            entry.stream.stop()
            entry.idleStop = nil
        }
    }
}

/// A view's claim on a camera stream. Release it when the view goes away.
@MainActor
final class StreamLease {
    let stream: CameraStream
    let cameraID: UUID
    private(set) var hd: Bool
    private(set) var isReleased = false
    private weak var pool: StreamPool?

    fileprivate init(stream: CameraStream, cameraID: UUID, hd: Bool, pool: StreamPool) {
        self.stream = stream
        self.cameraID = cameraID
        self.hd = hd
        self.pool = pool
    }

    func setHD(_ value: Bool) {
        guard !isReleased, value != hd else { return }
        hd = value
        pool?.lease(self, didChangeHD: value)
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        pool?.release(self)
    }
}
