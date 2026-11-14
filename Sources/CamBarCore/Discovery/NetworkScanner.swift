import Foundation
import Network

/// Something on the local network that looks like a camera, and why.
package struct DiscoveredDevice: Identifiable, Equatable, Sendable {
    package var host: String
    /// Port that answered an RTSP OPTIONS request.
    package var rtspPort: Int?
    /// Port of the ONVIF service, from the WS-Discovery answer.
    package var onvifPort: Int?
    /// Name and model the camera announces over ONVIF, when it does.
    package var name: String?
    package var hardware: String?

    package init(host: String, rtspPort: Int? = nil, onvifPort: Int? = nil, name: String? = nil, hardware: String? = nil) {
        self.host = host
        self.rtspPort = rtspPort
        self.onvifPort = onvifPort
        self.name = name
        self.hardware = hardware
    }

    package var id: String { host }

    /// e.g. "RTSP na porta 554 • ONVIF na porta 5000"
    package var evidence: String {
        [rtspPort.map { "RTSP na porta \($0)" }, onvifPort.map { "ONVIF na porta \($0)" }]
            .compactMap { $0 }.joined(separator: " • ")
    }

    package var title: String {
        if let name, !name.isEmpty { return name }
        if let hardware, !hardware.isEmpty { return hardware }
        return "Possível câmera"
    }
}

/// A local IPv4 network to scan.
package struct LocalNetwork: Equatable, Sendable {
    package var address: UInt32
    package var prefixLength: Int

    package init(address: UInt32, prefixLength: Int) {
        self.address = address
        self.prefixLength = prefixLength
    }

    /// e.g. "192.168.1.0/24": what the user is told before agreeing to the scan.
    package var description: String {
        let prefix = NetworkScanner.scanPrefix(prefixLength)
        return "\(NetworkScanner.format(address & NetworkScanner.mask(prefix)))/\(prefix)"
    }
}

package struct ScanProgress: Equatable, Sendable {
    package var checked: Int
    package var total: Int

    package init(checked: Int, total: Int) {
        self.checked = checked
        self.total = total
    }
}

/// Finds possible cameras on the local network, only when the user asks: an ONVIF WS-Discovery probe (multicast)
/// plus a TCP check of the RTSP ports on every address of the local subnet, confirmed with an RTSP OPTIONS request.
/// Nothing leaves the local network and no credentials are sent.
package enum NetworkScanner {
    package static let rtspPorts = [554, 8554]

    // MARK: Subnets

    /// Larger networks are narrowed to the /24 around this computer, so a scan stays at 254 addresses.
    package static func scanPrefix(_ prefixLength: Int) -> Int { min(max(prefixLength, 24), 30) }

    package static func mask(_ prefix: Int) -> UInt32 { prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix) }

    package static func parse(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts[0] << 24 | parts[1] << 16 | parts[2] << 8 | parts[3]
    }

    package static func format(_ value: UInt32) -> String {
        "\(value >> 24 & 255).\(value >> 16 & 255).\(value >> 8 & 255).\(value & 255)"
    }

    /// Every host address of the (narrowed) subnet, except this computer, the network and the broadcast address.
    package static func hosts(around address: UInt32, prefixLength: Int) -> [String] {
        let m = mask(scanPrefix(prefixLength))
        let network = address & m, broadcast = network | ~m
        guard broadcast > network + 1 else { return [] }
        return (network + 1..<broadcast).filter { $0 != address }.map(format)
    }

    /// Only private ranges are scanned (10/8, 172.16/12, 192.168/16): never a public network.
    package static func isPrivate(_ address: UInt32) -> Bool {
        let a = address >> 24, b = address >> 16 & 255
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }

    /// Private IPv4 networks of the active interfaces (skipping loopback), one per subnet.
    package static func localNetworks() -> [LocalNetwork] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var networks: [LocalNetwork] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let netmask = entry.pointee.ifa_netmask else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let m = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let prefix = m.nonzeroBitCount
            guard isPrivate(ip), (8...30).contains(prefix) else { continue }
            let candidate = LocalNetwork(address: ip, prefixLength: prefix)
            if !networks.contains(where: { $0.description == candidate.description }) { networks.append(candidate) }
        }
        return networks
    }

    // MARK: WS-Discovery

    package static func probeMessage(id: UUID) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<e:Envelope xmlns:e=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:w=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\" "
            + "xmlns:d=\"http://schemas.xmlsoap.org/ws/2005/04/discovery\" xmlns:dn=\"http://www.onvif.org/ver10/network/wsdl\">"
            + "<e:Header><w:MessageID>uuid:\(id.uuidString.lowercased())</w:MessageID><w:To e:mustUnderstand=\"true\">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>"
            + "<w:Action e:mustUnderstand=\"true\">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action></e:Header>"
            + "<e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body></e:Envelope>"
    }

    private static let xaddrsRegex = try! NSRegularExpression(pattern: #"<[\w]*:?XAddrs>([^<]+)</"#)
    private static let scopesRegex = try! NSRegularExpression(pattern: #"<[\w]*:?Scopes[^>]*>([^<]+)</"#)

    /// Devices in a ProbeMatches answer: host and ONVIF port from XAddrs, name and model from the scopes.
    package static func parseProbeMatches(_ xml: String) -> [DiscoveredDevice] {
        func groups(_ regex: NSRegularExpression) -> [String] {
            regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap {
                Range($0.range(at: 1), in: xml).map { String(xml[$0]) }
            }
        }
        let scopes = groups(scopesRegex).first?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        func scope(_ kind: String) -> String? {
            let prefix = "onvif://www.onvif.org/\(kind)/"
            return scopes.lazy
                .filter { $0.lowercased().hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                .map { ($0.removingPercentEncoding ?? $0).replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
        }

        var devices: [DiscoveredDevice] = []
        for list in groups(xaddrsRegex) {
            for address in list.split(whereSeparator: \.isWhitespace) {
                // cameras with several interfaces list every address; IPv6 ones are skipped
                guard let url = URL(string: String(address)), let host = url.host, parse(host) != nil,
                      !devices.contains(where: { $0.host == host }) else { continue }
                devices.append(DiscoveredDevice(host: host, onvifPort: url.port ?? 80, name: scope("name"), hardware: scope("hardware")))
            }
        }
        return devices
    }

    // MARK: RTSP

    package static func optionsRequest(host: String, port: Int) -> String {
        "OPTIONS rtsp://\(host):\(port)/ RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: CamBar\r\n\r\n"
    }

    /// Any RTSP status line counts, including 401: the port speaks RTSP even if it wants a password.
    package static func isRTSPResponse(_ text: String) -> Bool { text.hasPrefix("RTSP/1.") }

    /// Combines what each method found about the same address.
    package static func merge(_ a: DiscoveredDevice, _ b: DiscoveredDevice) -> DiscoveredDevice {
        DiscoveredDevice(host: a.host, rtspPort: a.rtspPort ?? b.rtspPort, onvifPort: a.onvifPort ?? b.onvifPort,
                         name: a.name ?? b.name, hardware: a.hardware ?? b.hardware)
    }

    /// Sorts addresses as numbers (192.168.1.9 before 192.168.1.10).
    package static func hostOrder(_ a: String, _ b: String) -> Bool { (parse(a) ?? .max) < (parse(b) ?? .max) }

    // MARK: Scan

    /// Runs both discovery methods. `found` gets every device as it appears (merged with what was known);
    /// cancelling the calling task stops the scan.
    package static func scan(networks: [LocalNetwork],
                             progress: @escaping @Sendable (ScanProgress) -> Void,
                             found: @escaping @Sendable (DiscoveredDevice) -> Void) async -> [DiscoveredDevice] {
        let results = Results(found: found)
        // (named apart from hosts(around:): older compilers resolve the call to the local array)
        let addresses = Array(Set(networks.flatMap { NetworkScanner.hosts(around: $0.address, prefixLength: $0.prefixLength) }))
        let targets = addresses.flatMap { host in rtspPorts.map { (host, $0) } }
        progress(ScanProgress(checked: 0, total: targets.count))

        async let discovery: Void = withTaskGroup(of: Void.self) { group in
            for network in networks {
                group.addTask { for device in await discoverONVIF(from: network.address) { results.add(device) } }
            }
        }

        var checked = 0
        await withTaskGroup(of: (String, Int, Bool).self) { group in
            var pending = targets[...]
            func next() {
                guard let (host, port) = pending.popFirst() else { return }
                group.addTask { (host, port, await probeRTSP(host: host, port: port)) }
            }
            for _ in 0..<64 { next() }
            for await (host, port, isRTSP) in group {
                checked += 1
                if isRTSP { results.add(DiscoveredDevice(host: host, rtspPort: port)) }
                progress(ScanProgress(checked: checked, total: targets.count))
                if !Task.isCancelled { next() }
            }
        }
        await discovery
        return results.all.sorted { hostOrder($0.host, $1.host) }
    }

    /// Thread-safe collection of what was found.
    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var devices: [String: DiscoveredDevice] = [:]
        private let found: @Sendable (DiscoveredDevice) -> Void

        init(found: @escaping @Sendable (DiscoveredDevice) -> Void) { self.found = found }

        func add(_ device: DiscoveredDevice) {
            lock.lock()
            let merged = devices[device.host].map { NetworkScanner.merge($0, device) } ?? device
            devices[device.host] = merged
            lock.unlock()
            found(merged)
        }

        var all: [DiscoveredDevice] {
            lock.lock()
            defer { lock.unlock() }
            return Array(devices.values)
        }
    }

    /// TCP connect plus an RTSP OPTIONS request; true when the answer is an RTSP status line.
    private static func probeRTSP(host: String, port: Int) async -> Bool {
        guard !Task.isCancelled, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "cambar.scan.rtsp")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let once = ResumeOnce()
            let finish: @Sendable (Bool) -> Void = { result in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    queue.asyncAfter(deadline: .now() + 2) { finish(false) }
                    connection.send(content: Data(optionsRequest(host: host, port: port).utf8), completion: .contentProcessed { _ in })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                        finish(data.map { isRTSPResponse(String(decoding: $0, as: UTF8.self)) } ?? false)
                    }
                case .failed, .waiting, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 0.6) {
                if connection.state != .ready { finish(false) }
            }
        }
    }

    /// Sends the WS-Discovery probe from one interface and collects answers for a few seconds (BSD sockets,
    /// since the Network framework only does multicast with an entitlement).
    private static func discoverONVIF(from localAddress: UInt32, seconds: Double = 4) async -> [DiscoveredDevice] {
        let cancelled = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: runDiscovery(localAddress: localAddress, seconds: seconds, cancelled: cancelled))
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    private static func runDiscovery(localAddress: UInt32, seconds: Double, cancelled: CancelFlag) -> [DiscoveredDevice] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_addr.s_addr = localAddress.bigEndian
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { return [] }
        var interface = in_addr(s_addr: localAddress.bigEndian)
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &interface, socklen_t(MemoryLayout<in_addr>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(3702).bigEndian
        destination.sin_addr.s_addr = (parse("239.255.255.250") ?? 0).bigEndian
        let message = Array(probeMessage(id: UUID()).utf8)
        let sent = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, message, message.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return [] }

        var devices: [DiscoveredDevice] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !cancelled.isSet {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { continue }
            for device in parseProbeMatches(String(decoding: buffer[..<count], as: UTF8.self))
            where !devices.contains(where: { $0.host == device.host }) {
                devices.append(device)
            }
        }
        return devices
    }
}

/// Lets a continuation be resumed exactly once from competing callbacks.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
