import AppKit
import CamBarCore
import Combine
import SwiftUI

/// Keeps one camera floating in a screen corner, above other windows and on every Space.
@MainActor
final class PinController: ObservableObject {
    private enum Keys {
        static let camera = "pinnedCamera"
        static let corner = "pinnedCorner"
        static let screen = "pinnedScreen"
        static let width = "pinnedWidth"
    }

    struct Pin: Equatable {
        let cameraID: UUID
        let corner: PinCorner
        let screenID: String
    }

    /// A connected monitor, described so the user can tell them apart.
    struct Display: Identifiable {
        let id: String
        let name: String
        let size: CGSize
        let isMain: Bool

        var isPortrait: Bool { size.height > size.width }
        var orientation: String { isPortrait ? "Vertical" : "Horizontal" }
        var symbol: String { isPortrait ? "rectangle.portrait" : "rectangle" }
        var title: String { "\(name) · \(Int(size.width))×\(Int(size.height)) · \(orientation)" }
    }

    @Published private(set) var pin: Pin?
    @Published private(set) var displays: [Display] = PinController.connectedDisplays()
    /// Width chosen by resizing; `nil` follows the screen size automatically.
    @Published private(set) var customWidth: CGFloat?

    /// Set once the router exists; lets the pinned view expand the camera into its window.
    weak var router: WindowRouting?

    private let store: CameraStore
    private let pool: StreamPool
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var resizeStart: (width: CGFloat, mouse: NSPoint)?
    private var subscriptions: Set<AnyCancellable> = []

    init(store: CameraStore, pool: StreamPool, defaults: UserDefaults = .standard) {
        self.store = store
        self.pool = pool
        self.defaults = defaults
        customWidth = (defaults.object(forKey: Keys.width) as? Double).map { CGFloat($0) }

        store.changes.sink { [weak self] change in
            if case .removed(let id) = change, self?.pin?.cameraID == id { self?.unpin() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.displays = PinController.connectedDisplays()
                self?.reposition()
            }
            .store(in: &subscriptions)
    }

    /// Brings back the pin from the last run. Call after the router is set.
    func restore() {
        guard let raw = defaults.string(forKey: Keys.camera), let id = UUID(uuidString: raw),
              store.camera(id) != nil else { return }
        let corner = defaults.string(forKey: Keys.corner).flatMap(PinCorner.init) ?? .bottomTrailing
        let screenID = defaults.string(forKey: Keys.screen) ?? Self.mainDisplayID
        show(Pin(cameraID: id, corner: corner, screenID: screenID))
    }

    func isPinned(_ camera: Camera) -> Bool { pin?.cameraID == camera.id }

    /// Pins to `display` (default: where the camera is already pinned, else the main monitor).
    func pin(_ camera: Camera, to corner: PinCorner, on display: Display? = nil) {
        let screenID = display?.id ?? pin?.screenID ?? Self.mainDisplayID
        show(Pin(cameraID: camera.id, corner: corner, screenID: screenID))
        defaults.set(camera.id.uuidString, forKey: Keys.camera)
        defaults.set(corner.rawValue, forKey: Keys.corner)
        defaults.set(screenID, forKey: Keys.screen)
    }

    func unpin() {
        pin = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        defaults.removeObject(forKey: Keys.camera)
        defaults.removeObject(forKey: Keys.corner)
        defaults.removeObject(forKey: Keys.screen)
    }

    // MARK: Resizing

    /// Called on every drag event of the resize handle. Uses the pointer's screen position, because the
    /// view's own coordinates move while the window resizes under it.
    func resize() {
        guard let pin, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let start = resizeStart ?? (panel.frame.width, mouse)
        resizeStart = start
        customWidth = start.width + PinLayout.widthChange(dx: mouse.x - start.mouse.x, dy: mouse.y - start.mouse.y,
                                                          pinnedTo: pin.corner)
        reposition()
    }

    func endResize() {
        resizeStart = nil
        guard let width = panel?.frame.width else { return }
        customWidth = width   // the clamped size, so a later screen change starts from what is visible
        defaults.set(Double(width), forKey: Keys.width)
    }

    /// Back to the automatic size (double-click on the handle).
    func resetSize() {
        customWidth = nil
        defaults.removeObject(forKey: Keys.width)
        reposition()
    }

    // MARK: Panel

    /// The panel is reused across pins: its view follows `pin`, so switching cameras just swaps the stream.
    private func show(_ pin: Pin) {
        self.pin = pin
        let panel = self.panel ?? makePanel()
        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        let view = PinnedCameraView(controller: self)
            .environmentObject(store)
            .environmentObject(pool)
            .environmentObject(self)   // PinMenu (monitor button) reads it
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }

    // MARK: Displays

    private static var mainDisplayID: String { NSScreen.screens.first.map(id(of:)) ?? "" }

    /// Stable across reboots and reconnections (unlike the numeric display ID).
    private static func id(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return screen.localizedName }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func connectedDisplays() -> [Display] {
        NSScreen.screens.enumerated().map { index, screen in
            Display(id: id(of: screen), name: screen.localizedName, size: screen.frame.size, isMain: index == 0)
        }
    }

    private func reposition() {
        guard let pin, let panel else { return }
        // A monitor that was unplugged falls back to the main one; the pin returns if it is reconnected.
        let screen = NSScreen.screens.first { Self.id(of: $0) == pin.screenID } ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(PinLayout.frame(for: pin.corner, in: visible, width: customWidth), display: true)
    }
}

/// The picture-in-picture content: live video with controls that appear on hover.
private struct PinnedCameraView: View {
    @ObservedObject var controller: PinController
    @EnvironmentObject private var store: CameraStore
    @StateObject private var hover = HoverState()

    var body: some View {
        ZStack {
            if let pin = controller.pin, let camera = store.camera(pin.cameraID) {
                CameraFeedView(camera: camera, showsStatus: false)
                    .contentShape(Rectangle())
                    .onTapGesture { controller.router?.showViewer(for: camera) }
                controls(camera, pin: pin)
                    .opacity(hover.isHovering ? 1 : 0)
                ResizeHandle(controller: controller, corner: pin.corner.opposite)
                    .opacity(hover.isHovering ? 1 : 0.45)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hover.isHovering)
        .background(HoverTracker(state: hover))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18), lineWidth: 0.5))
        .preferredColorScheme(.dark)
    }

    private func controls(_ camera: Camera, pin: PinController.Pin) -> some View {
        // on the pinned (outer) edge, away from the resize handle
        VStack {
            if !pin.corner.isTop { Spacer() }
            HStack(spacing: 6) {
                Text(camera.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer()
                ForEach(PinCorner.allCases, id: \.self) { corner in
                    iconButton(corner.symbol, help: corner.label, selected: corner == pin.corner) {
                        controller.pin(camera, to: corner)
                    }
                }
                if controller.displays.count > 1 {
                    PinMenu(camera: camera) {
                        Image(systemName: "display")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 22, height: 22)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
                    }
                }
                iconButton("arrow.up.left.and.arrow.down.right", help: "Abrir em janela") {
                    controller.router?.showViewer(for: camera)
                }
                iconButton("pin.slash.fill", help: "Desafixar") { controller.unpin() }
            }
            .padding(8)
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear],
                                       startPoint: pin.corner.isTop ? .top : .bottom,
                                       endPoint: pin.corner.isTop ? .bottom : .top))
            if pin.corner.isTop { Spacer() }
        }
    }

    private func iconButton(_ symbol: String, help: String, selected: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(selected ? .black : .white.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(selected ? Palette.accent : .black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Grip in the inner corner: drag to resize (16:9 kept, pinned corner fixed), double-click to go back
/// to the automatic size.
private struct ResizeHandle: View {
    let controller: PinController
    let corner: PinCorner

    var body: some View {
        Grip()
            .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.8), radius: 1.5)
            // the grip is drawn for the bottom-right corner; mirror it for the others
            .scaleEffect(x: corner.isLeading ? -1 : 1, y: corner.isTop ? -1 : 1)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .background(ResizeCursorArea(cursor: corner.resizeCursor))
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    corner.resizeCursor.set()   // the pointer can outrun the handle while the window catches up
                    controller.resize()
                }
                .onEnded { _ in
                    NSCursor.arrow.set()
                    controller.endResize()
                })
            .onTapGesture(count: 2) { controller.resetSize() }
            .help("Arraste para redimensionar; clique duas vezes para o tamanho automático")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
    }

    private struct Grip: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            for inset in [0, rect.width * 0.45] {
                path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
            }
            return path
        }
    }
}

/// Shows the resize cursor over the handle. Tracks with `.activeAlways` and sets the cursor by hand,
/// because cursor rects only work in the key window of the active app and this panel is neither.
private struct ResizeCursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorView {
        let view = CursorView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: CursorView, context: Context) { view.cursor = cursor }

    final class CursorView: NSView {
        var cursor = NSCursor.arrow

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { cursor.set() }
        // re-asserted on every move: other apps may reset the cursor while CamBar is in the background
        override func mouseMoved(with event: NSEvent) { cursor.set() }
        override func mouseExited(with event: NSEvent) {
            guard NSEvent.pressedMouseButtons == 0 else { return }   // still dragging
            NSCursor.arrow.set()
        }
    }
}

private extension PinCorner {
    /// Diagonal resize cursor for a handle in this corner.
    var resizeCursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch self {
            case .topLeading: position = .topLeft
            case .topTrailing: position = .topRight
            case .bottomLeading: position = .bottomLeft
            case .bottomTrailing: position = .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        return .crosshair
    }

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

/// Hover detection that works while the app is inactive (SwiftUI's `onHover` does not).
@MainActor
private final class HoverState: ObservableObject {
    @Published var isHovering = false
}

private struct HoverTracker: NSViewRepresentable {
    let state: HoverState

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = { [state] in state.isHovering = $0 }
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = { [state] in state.isHovering = $0 }
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}

/// "Fixar na tela" menu. With several monitors each one gets its own section (name, resolution and
/// orientation) with the four corners; unpin appears when this camera is the pinned one.
struct PinMenu<Content: View>: View {
    @EnvironmentObject private var pins: PinController
    let camera: Camera
    @ViewBuilder let label: () -> Content

    var body: some View {
        Menu {
            if pins.displays.count > 1 {
                ForEach(pins.displays) { display in
                    Section(display.title) { cornerButtons(on: display) }
                }
            } else {
                cornerButtons(on: pins.displays.first)
            }
            if pins.isPinned(camera) {
                Divider()
                Button("Desafixar", role: .destructive) { pins.unpin() }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Fixar na tela")
    }

    private func cornerButtons(on display: PinController.Display?) -> some View {
        ForEach(PinCorner.allCases, id: \.self) { corner in
            Button {
                pins.pin(camera, to: corner, on: display)
            } label: {
                if let pin = pins.pin, pin.cameraID == camera.id, pin.corner == corner,
                   display == nil || pin.screenID == display?.id {
                    Label(corner.label, systemImage: "checkmark")
                } else {
                    Text(corner.label)
                }
            }
        }
    }
}
