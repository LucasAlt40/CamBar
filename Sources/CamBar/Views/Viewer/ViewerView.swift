import AppKit
import CamBarCore
import SwiftUI

/// Expanded camera window: full-bleed video, header on hover, sound, snapshot, PTZ.
struct ViewerView: View {
    @StateObject private var model: ViewerViewModel

    init(model: ViewerViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ViewerScreen(model: model, session: model.session, audio: model.audio, ptz: model.ptz)
            .onAppear(perform: model.appear)
            .onDisappear(perform: model.disappear)
    }
}

/// Observes the nested objects so each change redraws only what depends on it.
private struct ViewerScreen: View {
    @ObservedObject var model: ViewerViewModel
    @ObservedObject var session: StreamSession
    @ObservedObject var audio: AudioPlayer
    @ObservedObject var ptz: PTZController

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            if let stream = session.stream {
                StreamFrameView(stream: stream, showsStatus: false)
                controls(stream)
            }
            header
                .opacity(model.isHovering || session.stream == nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: model.isHovering)
        }
        .onHover { model.isHovering = $0 }
        .preferredColorScheme(.dark)
        .frame(minWidth: 640, minHeight: 360)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.camera.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            if let stream = session.stream { LiveStatusChip(stream: stream) }
            Spacer()
            if let stream = session.stream { TelemetryChip(stream: stream) }
            Spacer()
            qualityPicker
            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 30, height: 28)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Tela cheia")
        }
        .padding(.leading, 84).padding(.trailing, 14)   // leaves room for the traffic lights
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
        }
    }

    private var qualityPicker: some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { hd in
                let isSelected = model.isHD == hd
                Button { model.isHD = hd } label: {
                    Text(hd ? "HD" : "SD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                        .frame(width: 40, height: 24)
                        .background(isSelected ? Palette.accent : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.5))
    }

    // MARK: Overlays

    private func controls(_ stream: CameraStream) -> some View {
        ZStack {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                    .padding(.top, 56)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
            ActionPill(stream: stream, audio: audio, toggleAudio: model.toggleAudio, snapshot: model.takeSnapshot)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            ptzControls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
    }

    @ViewBuilder
    private var ptzControls: some View {
        switch ptz.state {
        case .available:
            PTZPad(ptz: ptz).padding(16)
        case .unavailable:
            Label("Sem suporte PTZ", systemImage: "nosign")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 12).frame(height: 30)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                .padding(14)
        case .idle, .detecting:
            EmptyView()
        }
    }
}

/// Sound + snapshot pill.
private struct ActionPill: View {
    @ObservedObject var stream: CameraStream
    @ObservedObject var audio: AudioPlayer
    let toggleAudio: () -> Void
    let snapshot: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if stream.info?.hasAudio == true {
                Button(action: toggleAudio) {
                    HStack(spacing: 6) {
                        Image(systemName: audio.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        Text(audio.isPlaying ? "ON" : "MUDO").font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(audio.isPlaying ? Palette.accent : .white.opacity(0.75))
                    .padding(.horizontal, 12).frame(height: 30)
                }
                .buttonStyle(.plain)
                .help(audio.isPlaying ? "Silenciar" : "Ouvir o som da câmera")
                Hairline(axis: .vertical, color: .white.opacity(0.15)).frame(height: 16)
            }
            Button(action: snapshot) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12).frame(height: 30)
            }
            .buttonStyle(.plain)
            .help("Salvar foto")
            .disabled(stream.frame == nil)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}

private struct LiveStatusChip: View {
    @ObservedObject var stream: CameraStream
    var body: some View { StatusChip(status: stream.status) }
}

/// "1920×1080 • 15 FPS • H.265 Main", once ffmpeg has reported it.
struct TelemetryChip: View {
    @ObservedObject var stream: CameraStream

    var body: some View {
        if let info = stream.info, info.hasVideo {
            Text(info.summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.5))
        }
    }
}
