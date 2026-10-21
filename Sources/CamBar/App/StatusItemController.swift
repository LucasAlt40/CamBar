import AppKit
import Combine
import SwiftUI

/// The menu bar item ("N ON") and its popover, which keeps the native arrow pointing at the icon.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

    init(environment: AppEnvironment, router: WindowRouting) {
        self.environment = environment
        super.init()

        let content = NSHostingController(rootView: MenuView().injecting(environment, router: router))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        subscription = environment.reachability.$online
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] count in self?.statusItem.button?.image = statusBarImage(online: count) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        environment.pool.panelOpen = true
        environment.reachability.refresh()
    }

    func popoverDidClose(_ notification: Notification) {
        environment.pool.panelOpen = false
    }
}
