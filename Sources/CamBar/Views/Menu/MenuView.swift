import CamBarCore
import SwiftUI

/// Popover content: selected camera live, tabs to switch, quick actions.
struct MenuView: View {
    @EnvironmentObject private var store: CameraStore
    @EnvironmentObject private var pool: StreamPool
    @EnvironmentObject private var reachability: ReachabilityMonitor
    @Environment(\.windowRouter) private var router

    private let previewSize = CGSize(width: 372, height: 209)

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline(color: .white.opacity(0.06))
            VStack(spacing: 12) {
                if let camera = store.selected {
                    preview(camera)
                } else {
                    emptyState
                }
                if store.cameras.count > 1 { tabs }
            }
            .padding(14)
            Hairline(color: .white.opacity(0.06))
            footer
        }
        .frame(width: 400)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            circleIcon(Image(nsImage: securityCameraImage(size: 16)).renderingMode(.template))
            Text(store.selected?.name ?? "Câmeras")
                .font(.system(size: 14, weight: .semibold))
            if let selected = store.selected {
                Circle()
                    .fill(reachability.isOnline(selected.id) ? Palette.accent : .gray)
                    .frame(width: 6, height: 6)
            }
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                circleIcon(Image(systemName: "power").font(.system(size: 12, weight: .medium)))
            }
            .buttonStyle(.plain)
            .help("Sair")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func circleIcon(_ image: some View) -> some View {
        image
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(0.06), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
    }

    private func preview(_ camera: Camera) -> some View {
        CameraFeedView(camera: camera, isActive: pool.panelOpen)
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 0.5))
            .overlay(alignment: .topTrailing) {
                Button { router?.showViewer(for: camera) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(10)
                .help("Abrir em janela")
            }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(store.cameras) { camera in
                    let isSelected = camera.id == store.selectedID
                    Button { store.selectedID = camera.id } label: {
                        Text(camera.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color.white.opacity(0.14) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(minWidth: previewSize.width)
        }
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("Nenhuma câmera ainda").font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Adicionar câmera") { router?.showSettings() }.controlSize(.small)
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        let onlineCount = reachability.online.count
        return HStack(spacing: 8) {
            Image(systemName: onlineCount == 0 ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(onlineCount == 0 ? .gray : Palette.accent)
            Text("\(onlineCount) de \(store.cameras.count) online")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Toggle(isOn: $pool.keepConnected) {
                Text("Sempre ativo").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Mantém as câmeras conectadas em modo espera com o painel fechado.")
            footerButton("square.grid.2x2", help: "Visão geral") { router?.showOverview() }
            footerButton("slider.horizontal.3", help: "Gerenciar câmeras") { router?.showSettings() }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func footerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
    }
}
