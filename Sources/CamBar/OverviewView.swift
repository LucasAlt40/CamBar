import SwiftUI
import AppKit

/// Grid with every camera, opened from the popover.
struct OverviewView: View {
    @EnvironmentObject var store: CameraStore
    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.hairline).frame(height: 0.5)
            if store.cameras.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "video.badge.plus").font(.system(size: 28)).foregroundStyle(.white.opacity(0.4))
                    Text("Nenhuma câmera cadastrada").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(store.cameras.enumerated()), id: \.element.id) { i, cam in
                            OverviewTile(camera: cam, index: i + 1)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color.winBG)
        .background(WindowChrome())
        .preferredColorScheme(.dark)
        .frame(minWidth: 520, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("CamBar — Visão Geral").font(.system(size: 13, weight: .semibold))
            Text("\(store.cameras.count) canais")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: Capsule())
            Spacer()
            counter(store.online.count, "Online", Color.accentGreen)
            counter(store.cameras.count - store.online.count, "Sem sinal", Color(hex: 0xF43F5E))
            Button {
                store.refreshOnline()
                store.cameras.forEach { store.reconnect($0) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    Text("Atualizar").font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(.leading, 84).padding(.trailing, 14)
        .frame(height: 46)
        .background(Color.titleBG)
    }

    private func counter(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(n) \(label)").font(.system(size: 11, design: .monospaced)).foregroundStyle(color)
        }
    }
}

struct OverviewTile: View {
    @EnvironmentObject var store: CameraStore
    let camera: Camera
    let index: Int
    @StateObject private var session = StreamSession()

    var body: some View {
        VStack(spacing: 0) {
            if let stream = session.stream {
                TileContent(stream: stream, camera: camera, index: index,
                            expand: expand, retry: { store.reconnect(camera) })
            } else {
                Color.black.aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .background(Color.panelBG)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hairline, lineWidth: 0.5))
        .onAppear { session.attach(camera, hd: false, store: store) }
        .onDisappear { session.detach(store: store) }
    }

    private func expand() { WindowManager.shared.openViewer(camera) }
}

private struct TileContent: View {
    @ObservedObject var stream: CameraStream
    let camera: Camera
    let index: Int
    let expand: () -> Void
    let retry: () -> Void

    private var tint: Color {
        switch stream.status {
        case .live: return Color.accentGreen
        case .connecting, .idle: return Color(hex: 0xF59E0B)
        case .failed: return Color(hex: 0xF43F5E)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(camera.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(String(format: "CAM %02d", index))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                statusPill
            }
            .padding(.horizontal, 12).frame(height: 40)
            Rectangle().fill(Color.hairline).frame(height: 0.5)

            Color.black.aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    switch stream.status {
                    case .failed(let f): failure(f)
                    case .connecting where stream.frame == nil: connecting
                    default: live
                    }
                }
                .clipped()
        }
    }

    private var statusPill: some View {
        let text: String
        switch stream.status {
        case .live: text = "AO VIVO"
        case .connecting, .idle: text = "Conectando"
        case .failed: text = "Off-line"
        }
        return HStack(spacing: 8) {
            if let info = stream.info, stream.status == .live {
                Text("\(Int(info.fps)) FPS").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.accentGreen)
            }
            Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(tint.opacity(0.13), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 0.5))
        }
    }

    private var live: some View {
        ZStack(alignment: .bottom) {
            if let img = stream.frame { Image(nsImage: img).resizable().scaledToFit() }
            HStack {
                if let info = stream.info {
                    Text("\(info.width)×\(info.height)" + (info.codec.isEmpty ? "" : " • \(info.codec)"))
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                Spacer()
                Label("Clique para expandir", systemImage: "eye")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.accentGreen)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
            }
            .padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
    }

    private var connecting: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.regular)
            Text("Negociando RTSP…").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xFCD34D))
            Text("\(camera.host):\(camera.port)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private func failure(_ f: CameraStream.Failure) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash").font(.system(size: 16))
                .foregroundStyle(Color(hex: 0xFB7185))
                .frame(width: 40, height: 40)
                .background(Color(hex: 0xF43F5E).opacity(0.12), in: Circle())
                .overlay(Circle().stroke(Color(hex: 0xF43F5E).opacity(0.3), lineWidth: 0.5))
            Text(f.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xFDA4AF))
            Text(f.hint).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { retry() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    Text("Tentar reconectar").font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(PillButtonStyle())
        }
    }
}
