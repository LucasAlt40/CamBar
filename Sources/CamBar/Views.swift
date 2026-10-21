import SwiftUI
import AppKit

/// Reports whether the hosting window is currently on screen, so streams only run while the popover is open.
struct WindowVisibility: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.onChange = { visible = $0 }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            if let o = observer { NotificationCenter.default.removeObserver(o) }
            guard let window else { onChange?(false); return }
            onChange?(window.occlusionState.contains(.visible))
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.onChange?(window.occlusionState.contains(.visible))
            }
        }
    }
}

final class StreamHolder: ObservableObject { @Published var stream: CameraStream? }
final class MenuState: ObservableObject { @Published var isOpen = false }

/// Live picture + status overlay for one camera.
struct LiveFeed: View {
    @EnvironmentObject var store: CameraStore
    let camera: Camera
    var active: Bool = true
    var hd: Bool = false
    @StateObject private var holder = StreamHolder()
    private var stream: CameraStream? {
        get { holder.stream }
        nonmutating set { holder.stream = newValue }
    }

    var body: some View {
        ZStack {
            Color.black
            if let stream = holder.stream { FeedContent(stream: stream) }
        }
        .onAppear { update() }
        .onChange(of: active) { _, _ in update() }
        .onChange(of: camera.id) { old, _ in
            store.release(old, hd: hd); stream = nil; update()
        }
        .onDisappear { if stream != nil { store.release(camera.id, hd: hd); stream = nil } }
    }

    private func update() {
        if active, stream == nil {
            stream = store.acquire(camera, hd: hd)
        } else if !active, stream != nil {
            store.release(camera.id, hd: hd); stream = nil
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    static let popover = Color(hex: 0x16191E)
    static let cardBG = Color(hex: 0x1C2128)
    static let accentGreen = Color(hex: 0x10B981)
}

private struct StatusBadge: View {
    let status: CameraStream.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.5)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        .foregroundStyle(.white)
    }

    private var color: Color {
        switch status {
        case .live: return Color(hex: 0xF43F5E)
        case .connecting: return Color(hex: 0xF59E0B)
        default: return .gray
        }
    }
    private var label: String {
        switch status {
        case .live: return "AO VIVO"
        case .connecting: return "CONECTANDO"
        case .failed: return "SEM SINAL"
        case .idle: return "PARADO"
        }
    }
}

private struct FeedContent: View {
    @ObservedObject var stream: CameraStream

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let img = stream.frame {
                Image(nsImage: img).resizable().scaledToFit()
            }
            switch stream.status {
            case .connecting:
                if stream.frame == nil { ProgressView().controlSize(.small) }
            case .failed(let f):
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.06), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
                    Text(f.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Text(f.hint).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28).padding(.top, 14)
            default: EmptyView()
            }
            StatusBadge(status: stream.status).padding(10)
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var store: CameraStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var ui = MenuState()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.06))
            VStack(spacing: 12) {
                if let cam = store.camera(store.selectedID) {
                    preview(cam)
                } else {
                    empty
                }
                if store.cameras.count > 1 { tabs }
            }
            .padding(14)
            Divider().overlay(.white.opacity(0.06))
            footer
        }
        .frame(width: 400)
        .background(Color.popover)
        .preferredColorScheme(.dark)
        .background(WindowVisibility(visible: $ui.isOpen))
        .onChange(of: ui.isOpen) { _, open in
            store.panelOpen = open
            if open { store.refreshOnline() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: securityCameraImage(size: 16))
                .renderingMode(.template)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
            Text(store.camera(store.selectedID)?.name ?? "Câmeras")
                .font(.system(size: 14, weight: .semibold))
            Circle()
                .fill(store.selectedID.map { store.online.contains($0) } == true ? Color.accentGreen : Color.gray)
                .frame(width: 6, height: 6)
                .opacity(store.camera(store.selectedID) == nil ? 0 : 1)
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain).help("Sair")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func preview(_ cam: Camera) -> some View {
        LiveFeed(camera: cam, active: ui.isOpen)
            .frame(width: 372, height: 209)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 0.5))
            .overlay(alignment: .topTrailing) {
                Button { openViewer(cam) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain).padding(10).help("Abrir em janela")
            }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(store.cameras) { cam in
                    let selected = cam.id == store.selectedID
                    Button { store.selectedID = cam.id } label: {
                        Text(cam.name)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? .white : .white.opacity(0.55))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(selected ? Color.white.opacity(0.14) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(minWidth: 372)
        }
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("Nenhuma câmera ainda").font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Adicionar câmera") { openManage() }.controlSize(.small)
        }
        .frame(width: 372, height: 209)
        .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: store.online.isEmpty ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(store.online.isEmpty ? Color.gray : Color.accentGreen)
            Text("\(store.online.count) de \(store.cameras.count) online")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Toggle(isOn: $store.keepConnected) {
                Text("Sempre ativo").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            .toggleStyle(.switch).controlSize(.mini)
            .help("Mantém as câmeras conectadas com o painel fechado. Usa mais CPU e rede.")
            Button { openManage() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Gerenciar câmeras")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func openManage() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "manage")
    }

    private func openViewer(_ cam: Camera) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "viewer", value: cam.id)
    }
}

struct ViewerView: View {
    let camera: Camera

    var body: some View {
        LiveFeed(camera: camera, hd: true)
            .frame(minWidth: 480, minHeight: 270)
            .navigationTitle(camera.name)
    }
}
