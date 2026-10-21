import SwiftUI
import AppKit
import Combine

/// Status item + popover (with the native arrow pointing at the menu bar icon) and the app's windows.
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = CameraStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowManager.shared.store = store

        let content = NSHostingController(rootView: MenuView().environmentObject(store))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        updateIcon(store.online.count)
        store.$online
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateIcon($0.count) }
            .store(in: &cancellables)
    }

    private func updateIcon(_ online: Int) {
        statusItem?.button?.image = statusBarImage(online: online)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        store.panelOpen = true
        store.refreshOnline()
    }

    func popoverDidClose(_ notification: Notification) {
        store.panelOpen = false
    }
}

/// Opens and tracks the viewer, overview and settings windows.
final class WindowManager {
    static let shared = WindowManager()
    var store: CameraStore!

    private var viewers: [UUID: NSWindow] = [:]
    private var manage: NSWindow?
    private var overview: NSWindow?

    func openViewer(_ camera: Camera) {
        if let w = viewers[camera.id] { show(w); return }
        let w = makeWindow(size: NSSize(width: 1000, height: 563), minSize: NSSize(width: 640, height: 360),
                           title: camera.name, content: ViewerView(camera: camera).environmentObject(store))
        viewers[camera.id] = w
        track(w) { [weak self] in self?.viewers[camera.id] = nil }
        show(w)
    }

    func openManage() {
        if let w = manage { show(w); return }
        let w = makeWindow(size: NSSize(width: 900, height: 640), minSize: NSSize(width: 760, height: 560),
                           title: "Gerenciar câmeras", content: ManageView().environmentObject(store))
        manage = w
        track(w) { [weak self] in self?.manage = nil }
        show(w)
    }

    func openOverview() {
        if let w = overview { show(w); return }
        let w = makeWindow(size: NSSize(width: 920, height: 640), minSize: NSSize(width: 520, height: 360),
                           title: "Visão geral", content: OverviewView().environmentObject(store))
        overview = w
        track(w) { [weak self] in self?.overview = nil }
        show(w)
    }

    private func makeWindow<V: View>(size: NSSize, minSize: NSSize, title: String, content: V) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = title
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.minSize = minSize
        w.contentView = NSHostingView(rootView: content)
        w.center()
        return w
    }

    /// A menu bar app is hidden from Cmd+Tab; behave like a regular app only while a window is open.
    private func updatePolicy() {
        let hasWindows = !viewers.isEmpty || manage != nil || overview != nil
        NSApp.setActivationPolicy(hasWindows ? .regular : .accessory)
    }

    private func show(_ w: NSWindow) {
        updatePolicy()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Drops the SwiftUI content on close so streams, audio and PTZ are released.
    private func track(_ w: NSWindow, onClose: @escaping () -> Void) {
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [unowned self] _ in
            w.contentView = nil
            onClose()
            self.updatePolicy()
            if let t = token { NotificationCenter.default.removeObserver(t) }
        }
    }
}
