import SwiftUI
import AppKit

/// Holds one view's claim on a camera stream (acquire/release plus the HD switch).
final class StreamSession: ObservableObject {
    @Published private(set) var stream: CameraStream?
    private var cameraID: UUID?
    private var hd = false

    func attach(_ camera: Camera, hd: Bool, store: CameraStore) {
        guard stream == nil else { return }
        self.hd = hd
        cameraID = camera.id
        stream = store.acquire(camera, hd: hd)
    }

    func detach(store: CameraStore) {
        guard stream != nil, let id = cameraID else { return }
        store.release(id, hd: hd)
        stream = nil
        cameraID = nil
    }

    func setHD(_ new: Bool, store: CameraStore) {
        guard stream != nil, let id = cameraID, new != hd else { return }
        hd = new
        store.setHD(id, enabled: new)
    }
}

/// Live picture + status overlay for one camera.
struct LiveFeed: View {
    @EnvironmentObject var store: CameraStore
    let camera: Camera
    var active: Bool = true
    var hd: Bool = false
    @StateObject private var session = StreamSession()

    var body: some View {
        ZStack {
            Color.black
            if let stream = session.stream { FeedContent(stream: stream) }
        }
        .onAppear { update() }
        .onChange(of: active) { _, _ in update() }
        .onChange(of: hd) { _, new in session.setHD(new, store: store) }
        .onChange(of: camera.id) { _, _ in session.detach(store: store); update() }
        .onDisappear { session.detach(store: store) }
    }

    private func update() {
        if active { session.attach(camera, hd: hd, store: store) } else { session.detach(store: store) }
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

struct FeedContent: View {
    @ObservedObject var stream: CameraStream
    var showBadge = true

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
            if showBadge { StatusBadge(status: stream.status).padding(10) }
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var store: CameraStore

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
        .preferredColorScheme(.dark)
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
        LiveFeed(camera: cam, active: store.panelOpen)
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
            Button { openOverview() } label: { Image(systemName: "square.grid.2x2") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Visão geral")
            Button { openManage() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Gerenciar câmeras")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func openManage() { WindowManager.shared.openManage() }
    private func openOverview() { WindowManager.shared.openOverview() }
    private func openViewer(_ cam: Camera) { WindowManager.shared.openViewer(cam) }
}
