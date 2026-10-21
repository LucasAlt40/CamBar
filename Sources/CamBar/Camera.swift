import Foundation
import Network
import Security

struct Camera: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int = 554
    var path: String = "/"
    var username: String = ""
    var transport: String?   // nil/"auto", "tcp" or "udp"

    func rtspURL(password: String) -> String {
        var auth = ""
        if !username.isEmpty {
            let u = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            let p = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            auth = password.isEmpty ? "\(u)@" : "\(u):\(p)@"
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        return "rtsp://\(auth)\(host):\(port)\(normalizedPath)"
    }
}

enum Keychain {
    private static let service = "CamBar"

    static func password(for id: UUID) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setPassword(_ password: String, for id: UUID) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(base as CFDictionary)
        guard !password.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

final class CameraStore: ObservableObject {
    @Published var cameras: [Camera] = [] { didSet { save() } }
    @Published var selectedID: UUID?
    @Published var online: Set<UUID> = []
    /// Keep streams connected after the popover closes (costs CPU and network).
    @Published var keepConnected: Bool = true {
        didSet {
            UserDefaults.standard.set(keepConnected, forKey: "keepConnected")
            if keepConnected {
                pendingStops.values.forEach { $0.cancel() }
                pendingStops.removeAll()
            } else {
                for (id, n) in refCounts where n == 0 { scheduleStop(id) }
            }
            applyAllProfiles()
        }
    }
    /// True while the menu bar popover is on screen: every connected camera runs at normal quality so tab switches are instant.
    @Published var panelOpen = false {
        didSet { applyAllProfiles() }
    }
    private var monitor: Timer?
    private var pendingStops: [UUID: DispatchWorkItem] = [:]
    private var hdCounts: [UUID: Int] = [:]
    private let idleGrace: TimeInterval = 60

    private var streams: [UUID: CameraStream] = [:]
    private var refCounts: [UUID: Int] = [:]
    private let defaultsKey = "cameras"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Camera].self, from: data) {
            cameras = decoded
        }
        selectedID = cameras.first?.id
        keepConnected = UserDefaults.standard.object(forKey: "keepConnected") as? Bool ?? true
        refreshOnline()
        monitor = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refreshOnline()
        }
    }

    func refreshOnline() {
        let cams = cameras
        Task {
            let up = await withTaskGroup(of: (UUID, Bool).self, returning: Set<UUID>.self) { group in
                for c in cams { group.addTask { (c.id, await tcpReachable(host: c.host, port: c.port)) } }
                var found = Set<UUID>()
                for await (id, ok) in group where ok { found.insert(id) }
                return found
            }
            await MainActor.run { self.online = up }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cameras) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func camera(_ id: UUID?) -> Camera? { cameras.first { $0.id == id } }

    func upsert(_ camera: Camera, password: String) {
        Keychain.setPassword(password, for: camera.id)
        if let i = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[i] = camera
            streams[camera.id]?.restart(camera: camera, password: password)
        } else {
            cameras.append(camera)
            if selectedID == nil { selectedID = camera.id }
        }
        refreshOnline()
    }

    func remove(_ camera: Camera) {
        streams[camera.id]?.stop()
        streams[camera.id] = nil
        refCounts[camera.id] = nil
        hdCounts[camera.id] = nil
        Keychain.setPassword("", for: camera.id)
        cameras.removeAll { $0.id == camera.id }
        if selectedID == camera.id { selectedID = cameras.first?.id }
        refreshOnline()
    }

    /// Streams are shared between the menu bar preview and the expanded window. Once connected they
    /// stay up while viewed, and afterwards either indefinitely (keepConnected) or for `idleGrace` seconds.
    func acquire(_ camera: Camera, hd: Bool = false) -> CameraStream {
        let stream = streams[camera.id] ?? CameraStream()
        streams[camera.id] = stream
        pendingStops[camera.id]?.cancel()
        pendingStops[camera.id] = nil
        refCounts[camera.id, default: 0] += 1
        stream.viewers = refCounts[camera.id] ?? 0
        if hd { hdCounts[camera.id, default: 0] += 1 }
        applyProfile(camera, stream: stream)
        if !stream.isActive {
            stream.start(camera: camera, password: Keychain.password(for: camera.id))
        }
        return stream
    }

    private func profile(for id: UUID) -> CameraStream.Profile {
        if (hdCounts[id] ?? 0) > 0 { return .hd }
        if panelOpen || (refCounts[id] ?? 0) > 0 || !keepConnected { return .normal }
        return .standby
    }

    private func applyProfile(_ camera: Camera, stream: CameraStream) {
        let want = profile(for: camera.id)
        guard stream.profile != want else { return }
        stream.profile = want
        if stream.isActive {
            stream.start(camera: camera, password: Keychain.password(for: camera.id), keepFrame: true)
        }
    }

    private func applyAllProfiles() {
        for (id, stream) in streams { if let cam = camera(id) { applyProfile(cam, stream: stream) } }
    }

    func release(_ id: UUID, hd: Bool = false) {
        guard let n = refCounts[id], n > 0 else { return }
        refCounts[id] = n - 1
        streams[id]?.viewers = n - 1
        if hd, let c = hdCounts[id], c > 0 { hdCounts[id] = c - 1 }
        if let cam = camera(id), let st = streams[id] { applyProfile(cam, stream: st) }
        if n - 1 == 0 && !keepConnected { scheduleStop(id) }
    }

    private func scheduleStop(_ id: UUID) {
        pendingStops[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, (self.refCounts[id] ?? 0) == 0 else { return }
            self.streams[id]?.stop()
            self.pendingStops[id] = nil
        }
        pendingStops[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleGrace, execute: work)
    }
}

/// Plain TCP connect to host:port, used to tell whether a camera is reachable on the network.
func tcpReachable(host: String, port: Int, timeout: TimeInterval = 2) async -> Bool {
    guard !host.isEmpty, let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
    return await withCheckedContinuation { cont in
        let q = DispatchQueue(label: "cambar.reach")
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let once = Once()
        let finish: @Sendable (Bool) -> Void = { ok in
            guard once.claim() else { return }
            conn.cancel()
            cont.resume(returning: ok)
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .waiting, .cancelled: finish(false)
            default: break
            }
        }
        conn.start(queue: q)
        q.asyncAfter(deadline: .now() + timeout) { finish(false) }
    }
}

/// Lets a continuation be resumed exactly once from concurrent callbacks.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
