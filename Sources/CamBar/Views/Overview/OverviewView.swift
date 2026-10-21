import CamBarCore
import SwiftUI

/// Grid with every camera.
struct OverviewView: View {
    @EnvironmentObject private var store: CameraStore
    @EnvironmentObject private var pool: StreamPool
    @EnvironmentObject private var reachability: ReachabilityMonitor

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if store.cameras.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "video.badge.plus").font(.system(size: 28)).foregroundStyle(.white.opacity(0.4))
                    Text("Nenhuma câmera cadastrada").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.cameras) { camera in
                            OverviewTile(camera: camera, number: store.number(of: camera) ?? 0)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Palette.window)
        .preferredColorScheme(.dark)
        .frame(minWidth: 520, minHeight: 360)
    }

    private var header: some View {
        let online = reachability.online.count
        return HStack(spacing: 12) {
            Text("CamBar — Visão Geral").font(.system(size: 13, weight: .semibold))
            Text("\(store.cameras.count) canais")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: Capsule())
            Spacer()
            counter(online, "Online", Palette.accent)
            counter(store.cameras.count - online, "Sem sinal", Palette.danger)
            Button {
                reachability.refresh()
                pool.reconnectAll()
            } label: {
                Label("Atualizar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(.leading, 84).padding(.trailing, 14)   // leaves room for the traffic lights
        .frame(height: 46)
        .background(Palette.titleBar)
    }

    private func counter(_ count: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(label)").font(.system(size: 11, design: .monospaced)).foregroundStyle(color)
        }
    }
}

/// One camera in the grid. Leases its stream while on screen.
private struct OverviewTile: View {
    @EnvironmentObject private var pool: StreamPool
    @Environment(\.windowRouter) private var router
    let camera: Camera
    let number: Int
    @StateObject private var session = StreamSession()

    var body: some View {
        Group {
            if let stream = session.stream {
                TileContent(stream: stream, camera: camera, number: number,
                            expand: { router?.showViewer(for: camera) },
                            retry: { pool.reconnect(camera.id) })
            } else {
                Color.black.aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.hairline, lineWidth: 0.5))
        .onAppear { session.attach(camera, hd: false, pool: pool) }
        .onDisappear { session.detach() }
    }
}

private struct TileContent: View {
    @ObservedObject var stream: CameraStream
    let camera: Camera
    let number: Int
    let expand: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(stream.status.color(for: .tinted)).frame(width: 7, height: 7)
                Text(camera.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(String(format: "CAM %02d", number))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                if let info = stream.info, stream.status == .live {
                    Text("\(info.fpsText) FPS").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Palette.accent)
                }
                StatusChip(status: stream.status)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            Hairline()

            Color.black
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { videoArea }
                .clipped()
        }
    }

    @ViewBuilder
    private var videoArea: some View {
        switch stream.status {
        case .failed(let failure):
            FailureView(failure: failure, tone: .alert, retry: retry)
        case .connecting where stream.frame == nil:
            VStack(spacing: 8) {
                ProgressView()
                Text("Negociando RTSP…").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.warningText)
                Text(camera.endpoint).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            }
        default:
            ZStack(alignment: .bottom) {
                if let frame = stream.frame { Image(nsImage: frame).resizable().scaledToFit() }
                HStack {
                    if let info = stream.info {
                        OverlayTag(text: info.resolution + (info.codec.isEmpty ? "" : " • \(info.codec)"))
                    }
                    Spacer()
                    Label("Clique para expandir", systemImage: "eye")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                .padding(10)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: expand)
        }
    }
}
