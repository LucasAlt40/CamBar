import SwiftUI
import AppKit

final class ViewerState: ObservableObject {
    @Published var hd = true
    @Published var toast: String?
    @Published var hovering = true
}

/// Expanded single-camera window: telemetry, HD/SD, sound, snapshot and fullscreen.
struct ViewerView: View {
    @EnvironmentObject var store: CameraStore
    let camera: Camera
    @StateObject private var session = StreamSession()
    @StateObject private var ui = ViewerState()
    @StateObject private var audio = AudioPlayer()
    @StateObject private var ptz = PTZController()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            if let stream = session.stream {
                FeedContent(stream: stream, showBadge: false)
                ViewerControls(stream: stream, camera: camera, audio: audio, ui: ui, ptz: ptz)
            }
            header
                .opacity(ui.hovering || session.stream == nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: ui.hovering)
        }
        .onHover { ui.hovering = $0 }
        .background(Color.winBG)
        .background(WindowChrome(aspectRatio: NSSize(width: 16, height: 9)))
        .preferredColorScheme(.dark)
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            session.attach(camera, hd: ui.hd, store: store)
            ptz.detect(camera: camera, password: store.password(for: camera.id))
        }
        .onChange(of: ui.hd) { _, hd in session.setHD(hd, store: store) }
        .onDisappear { ptz.stop(); audio.stop(); session.detach(store: store) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(camera.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            if let stream = session.stream { ViewerStatusChip(stream: stream) }
            Spacer()
            if let stream = session.stream { TelemetryChip(stream: stream) }
            Spacer()
            qualityPicker
            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 30, height: 28)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain).help("Tela cheia")
        }
        .padding(.leading, 84).padding(.trailing, 14)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: 70).frame(maxHeight: .infinity, alignment: .top), alignment: .top)
    }

    private var qualityPicker: some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { hd in
                Button { ui.hd = hd } label: {
                    Text(hd ? "HD" : "SD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(ui.hd == hd ? .black : .white.opacity(0.6))
                        .frame(width: 40, height: 24)
                        .background(ui.hd == hd ? Color.accentGreen : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(Color.hairline, lineWidth: 0.5))
    }
}

private struct ViewerStatusChip: View {
    @ObservedObject var stream: CameraStream

    var body: some View {
        let (text, color): (String, Color) = {
            switch stream.status {
            case .live: return ("AO VIVO", Color.accentGreen)
            case .connecting: return ("CONECTANDO", Color(hex: 0xF59E0B))
            case .failed: return ("SEM SINAL", Color(hex: 0xF43F5E))
            case .idle: return ("PARADO", .gray)
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(color)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}

struct TelemetryChip: View {
    @ObservedObject var stream: CameraStream

    var body: some View {
        if let info = stream.info {
            Text(info.summary)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.accentGreen)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().stroke(Color.hairline, lineWidth: 0.5))
        }
    }
}

/// Sound + snapshot pill over the video.
private struct ViewerControls: View {
    @EnvironmentObject var store: CameraStore
    @ObservedObject var stream: CameraStream
    let camera: Camera
    @ObservedObject var audio: AudioPlayer
    @ObservedObject var ui: ViewerState
    @ObservedObject var ptz: PTZController

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            actionPill
            if ptz.state == .available {
                PTZPad(ptz: ptz).padding(16)
            } else if ptz.state == .unavailable {
                Label("Sem suporte PTZ", systemImage: "nosign")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                    .padding(14)
            }
        }
    }

    private var actionPill: some View {
        VStack {
            if let toast = ui.toast {
                Text(toast).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                    .transition(.opacity)
                    .padding(.top, 14)
            }
            Spacer()
            HStack(spacing: 0) {
                if stream.info?.hasAudio == true {
                    Button { audio.toggle(camera: camera, password: store.password(for: camera.id)) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: audio.isOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            Text(audio.isOn ? "ON" : "MUDO").font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(audio.isOn ? Color.accentGreen : .white.opacity(0.75))
                        .padding(.horizontal, 12).frame(height: 30)
                    }
                    .buttonStyle(.plain).help(audio.isOn ? "Silenciar" : "Ouvir o som da câmera")
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 0.5, height: 16)
                }
                Button { snapshot() } label: {
                    Image(systemName: "camera.fill").foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12).frame(height: 30)
                }
                .buttonStyle(.plain).help("Salvar foto").disabled(stream.frame == nil)
            }
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func snapshot() {
        guard let image = stream.frame, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { return }
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("CamBar")
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = dir.appendingPathComponent("\(camera.name) \(stamp.string(from: Date())).jpg")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try jpeg.write(to: url)
            show("Foto salva em Imagens/CamBar")
        } catch {
            show("Não foi possível salvar a foto")
        }
    }

    private func show(_ text: String) {
        withAnimation { ui.toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { ui.toast = nil } }
    }
}


/// Directional pad + zoom, holding a button moves the camera, releasing stops it.
private struct PTZPad: View {
    @ObservedObject var ptz: PTZController
    private let speed = 0.5

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 0) {
                holdButton("plus", key: "zin", pan: 0, tilt: 0, zoom: speed)
                Rectangle().fill(.white.opacity(0.12)).frame(width: 18, height: 0.5)
                holdButton("minus", key: "zout", pan: 0, tilt: 0, zoom: -speed)
            }
            .frame(width: 38, height: 84)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))

            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().stroke(.white.opacity(0.12), lineWidth: 0.5)
                holdButton("chevron.up", key: "up", pan: 0, tilt: speed, zoom: 0).offset(y: -40)
                holdButton("chevron.down", key: "down", pan: 0, tilt: -speed, zoom: 0).offset(y: 40)
                holdButton("chevron.left", key: "left", pan: -speed, tilt: 0, zoom: 0).offset(x: -40)
                holdButton("chevron.right", key: "right", pan: speed, tilt: 0, zoom: 0).offset(x: 40)
                PTZKnob(ptz: ptz)
            }
            .frame(width: 124, height: 124)
        }
    }

    private func holdButton(_ symbol: String, key: String, pan: Double, tilt: Double, zoom: Double) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ptz.activeKey == key ? Color.accentGreen : .white.opacity(0.9))
            .frame(width: 34, height: 34)
            .background(ptz.activeKey == key ? Color.accentGreen.opacity(0.2) : .clear, in: Circle())
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in ptz.begin(key: key, pan: pan, tilt: tilt, zoom: zoom) }
                .onEnded { _ in ptz.stop() })
    }
}


final class KnobState: ObservableObject { @Published var offset = CGSize.zero }

/// Drag the green knob to steer, release to stop; a plain click recenters the camera.
private struct PTZKnob: View {
    @ObservedObject var ptz: PTZController
    @StateObject private var knob = KnobState()
    private let radius: CGFloat = 36

    var body: some View {
        Circle().fill(Color.accentGreen.opacity(0.25))
            .overlay(Circle().fill(Color.accentGreen).frame(width: 7, height: 7))
            .overlay(Circle().stroke(Color.accentGreen.opacity(0.5), lineWidth: 0.5))
            .frame(width: 34, height: 34)
            .offset(knob.offset)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let len = hypot(v.translation.width, v.translation.height)
                    let k = len > radius ? radius / len : 1
                    knob.offset = CGSize(width: v.translation.width * k, height: v.translation.height * k)
                    ptz.drive(dx: knob.offset.width / radius, dy: -knob.offset.height / radius)
                }
                .onEnded { v in
                    if hypot(v.translation.width, v.translation.height) < 4 { ptz.goHome() }
                    ptz.stop()
                    withAnimation(.spring(response: 0.25)) { knob.offset = .zero }
                })
            .help("Arraste para mover; clique para centralizar")
    }
}
