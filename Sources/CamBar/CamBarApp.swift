import SwiftUI

@main
struct CamBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item, popover and windows are managed by AppDelegate.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
