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
    private var monitor: Timer?

    private var streams: [UUID: CameraStream] = [:]
    private var refCounts: [UUID: Int] = [:]
    private let defaultsKey = "cameras"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Camera].self, from: data) {
            cameras = decoded
        }
        selectedID = cameras.first?.id
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
        Keychain.setPassword("", for: camera.id)
        cameras.removeAll { $0.id == camera.id }
        if selectedID == camera.id { selectedID = cameras.first?.id }
        refreshOnline()
    }

    /// Streams are shared between the menu bar preview and the expanded window,
    /// and run only while at least one view holds them.
    func acquire(_ camera: Camera) -> CameraStream {
        let stream = streams[camera.id] ?? CameraStream()
        streams[camera.id] = stream
        refCounts[camera.id, default: 0] += 1
        if refCounts[camera.id] == 1 {
            stream.start(camera: camera, password: Keychain.password(for: camera.id))
        }
        return stream
    }

    func release(_ id: UUID) {
        guard let n = refCounts[id], n > 0 else { return }
        refCounts[id] = n - 1
        if n - 1 == 0 { streams[id]?.stop() }
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
