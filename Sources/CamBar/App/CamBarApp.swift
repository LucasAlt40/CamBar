import AppKit
import SwiftUI

@main
struct CamBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item, popover and windows are AppKit-managed (see AppDelegate).
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var router: WindowRouter?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.live()
        let router = WindowRouter(environment: environment)
        statusItem = StatusItemController(environment: environment, router: router)
        environment.reachability.start()
        self.environment = environment
        self.router = router
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.pool.shutdown()
    }
}
