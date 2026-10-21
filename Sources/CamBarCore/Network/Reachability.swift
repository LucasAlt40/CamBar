import Foundation
import Network

/// Answers "does something accept connections at host:port?".
package protocol ReachabilityChecking: Sendable {
    func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool
}

/// A plain TCP connect. It only says the camera is on the network, not that the stream works.
package struct TCPReachability: ReachabilityChecking {
    package init() {}

    package func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "cambar.reachability")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let once = Once()
            let finish: @Sendable (Bool) -> Void = { reachable in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: reachable)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}

/// Lets a continuation be resumed exactly once from competing callbacks.
private final class Once: @unchecked Sendable {
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
