import AppKit
import CamBarCore
import Combine
import SwiftUI

/// Navigation between the app's windows, injected into views through the environment.
@MainActor
protocol WindowRouting: AnyObject {
    func showViewer(for camera: Camera)
    func showOverview()
    func showSettings()
}

private struct WindowRouterKey: EnvironmentKey {
    static let defaultValue: WindowRouting? = nil
}

extension EnvironmentValues {
    var windowRouter: WindowRouting? {
        get { self[WindowRouterKey.self] }
        set { self[WindowRouterKey.self] = newValue }
    }
}

/// Opens one window per destination (re-focusing it if already open). While any window is open the app
/// behaves like a regular app (Dock, Cmd+Tab); otherwise it is just the menu bar item.
@MainActor
final class WindowRouter: NSObject, WindowRouting, NSWindowDelegate {
    private enum Destination: Hashable {
        case viewer(UUID), overview, settings
    }

    private let environment: AppEnvironment
    private var windows: [Destination: NSWindow] = [:]
    private var subscription: AnyCancellable?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        subscription = environment.store.changes.sink { [weak self] change in
            switch change {
            case .updated(let camera): self?.windows[.viewer(camera.id)]?.title = camera.name
            case .removed(let id): self?.windows[.viewer(id)]?.close()   // its stream is gone
            }
        }
    }

    func showViewer(for camera: Camera) {
        show(.viewer(camera.id), title: camera.name,
             size: NSSize(width: 1000, height: 563), minSize: NSSize(width: 640, height: 360),
             aspectRatio: NSSize(width: 16, height: 9)) {
            ViewerView(model: ViewerViewModel(camera: camera, store: environment.store,
                                              pool: environment.pool, ptzLog: environment.ptzLog))
        }
    }

    func showOverview() {
        show(.overview, title: "Visão geral",
             size: NSSize(width: 920, height: 640), minSize: NSSize(width: 520, height: 360)) {
            OverviewView()
        }
    }

    func showSettings() {
        show(.settings, title: "Gerenciar câmeras",
             size: NSSize(width: 900, height: 640), minSize: NSSize(width: 760, height: 560)) {
            SettingsView(model: SettingsViewModel(store: environment.store, checker: environment.checker))
        }
    }

    private func show<Content: View>(_ destination: Destination, title: String, size: NSSize, minSize: NSSize,
                                     aspectRatio: NSSize? = nil, content: () -> Content) {
        let window = windows[destination] ?? makeWindow(title: title, size: size, minSize: minSize,
                                                         aspectRatio: aspectRatio, content: content())
        windows[destination] = window
        updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, minSize: NSSize,
                                           aspectRatio: NSSize?, content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.windowNS
        window.minSize = minSize
        if let aspectRatio { window.contentAspectRatio = aspectRatio }
        window.contentView = NSHostingView(rootView: content.injecting(environment, router: self))
        window.center()
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let destination = windows.first(where: { $0.value === window })?.key else { return }
        // tearing down the SwiftUI tree releases streams, audio and PTZ
        window.contentView = nil
        windows[destination] = nil
        updateActivationPolicy()
    }

    private func updateActivationPolicy() {
        NSApp.setActivationPolicy(windows.isEmpty ? .accessory : .regular)
    }
}
