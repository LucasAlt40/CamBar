import CamBarCore
import SwiftUI

/// Composition root: the long-lived services, created once and injected into every view.
@MainActor
final class AppEnvironment {
    let store: CameraStore
    let pool: StreamPool
    let reachability: ReachabilityMonitor
    let checker: ReachabilityChecking
    let ptzLog: FileLog

    init(repository: CameraRepository, credentials: CredentialStore, checker: ReachabilityChecking,
         defaults: UserDefaults, streamLog: FileLog?, ptzLog: FileLog) {
        store = CameraStore(repository: repository, credentials: credentials)
        pool = StreamPool(store: store, credentials: credentials, defaults: defaults, log: streamLog)
        reachability = ReachabilityMonitor(store: store, checker: checker)
        self.checker = checker
        self.ptzLog = ptzLog
    }

    static func live() -> AppEnvironment {
        AppEnvironment(repository: UserDefaultsCameraRepository(),
                       credentials: KeychainCredentialStore(),
                       checker: TCPReachability(),
                       defaults: .standard,
                       streamLog: FileLog(name: "CamBar"),
                       ptzLog: FileLog(name: "CamBar-ptz"))
    }
}

extension View {
    /// Makes the shared services available to a view hierarchy.
    func injecting(_ environment: AppEnvironment, router: WindowRouting) -> some View {
        self
            .environmentObject(environment.store)
            .environmentObject(environment.pool)
            .environmentObject(environment.reachability)
            .environment(\.windowRouter, router)
    }
}
