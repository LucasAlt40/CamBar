import CamBarCore
import Combine
import Foundation

/// Which cameras answer on the network, refreshed periodically and whenever the list changes.
@MainActor
final class ReachabilityMonitor: ObservableObject {
    @Published private(set) var online: Set<UUID> = []

    private let store: CameraStore
    private let checker: ReachabilityChecking
    private let interval: Duration
    private var loop: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subscription: AnyCancellable?

    init(store: CameraStore, checker: ReachabilityChecking, interval: Duration = .seconds(20)) {
        self.store = store
        self.checker = checker
        self.interval = interval
        // @Published emits before the value is stored, so use the value it hands over
        subscription = store.$cameras.dropFirst().sink { [weak self] cameras in self?.refresh(cameras) }
    }

    func isOnline(_ id: UUID) -> Bool { online.contains(id) }

    func start() {
        loop?.cancel()
        let interval = interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh(_ cameras: [Camera]? = nil) {
        let targets = cameras ?? store.cameras
        let checker = checker
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let reachable = await withTaskGroup(of: (UUID, Bool).self, returning: Set<UUID>.self) { group in
                for camera in targets {
                    group.addTask {
                        (camera.id, await checker.isReachable(host: camera.host, port: camera.port, timeout: 2))
                    }
                }
                var found = Set<UUID>()
                for await (id, isUp) in group where isUp { found.insert(id) }
                return found
            }
            guard !Task.isCancelled else { return }
            self?.online = reachable
        }
    }
}
