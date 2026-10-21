import CamBarCore
import SwiftUI

/// 0.5 pt separator line.
struct Hairline: View {
    var axis: Axis = .horizontal
    var color: Color = Palette.hairline

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: axis == .vertical ? 0.5 : nil, height: axis == .horizontal ? 0.5 : nil)
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }
}

/// Small monospaced capsule with a colored dot, e.g. "● AO VIVO".
struct StatusChip: View {
    enum Style {
        /// Over video: dark capsule, colored dot, white text.
        case overlay
        /// On chrome: tinted capsule and text.
        case tinted
    }

    let status: CameraStream.Status
    var style: Style = .tinted

    var body: some View {
        let color = status.color(for: style)
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(status.label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(style == .overlay ? 0.5 : 0)
                .foregroundStyle(style == .overlay ? .white : color)
        }
        .padding(.horizontal, 9).padding(.vertical, style == .overlay ? 5 : 4)
        .background(style == .overlay ? Color.black.opacity(0.55) : color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(style == .overlay ? Color.white.opacity(0.12) : color.opacity(0.3), lineWidth: 0.5))
    }
}

extension CameraStream.Status {
    var label: String {
        switch self {
        case .live: return "AO VIVO"
        case .connecting: return "CONECTANDO"
        case .failed: return "SEM SINAL"
        case .idle: return "PARADO"
        }
    }

    func color(for style: StatusChip.Style) -> Color {
        switch self {
        case .live: return style == .overlay ? Palette.danger : Palette.accent
        case .connecting: return Palette.warning
        case .failed: return style == .overlay ? .gray : Palette.danger
        case .idle: return .gray
        }
    }
}

/// Why the stream is not playing, with an optional retry.
struct FailureView: View {
    enum Tone { case neutral, alert }

    let failure: StreamFailure
    var tone: Tone = .neutral
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.system(size: tone == .alert ? 16 : 15, weight: .medium))
                .foregroundStyle(tone == .alert ? Palette.dangerSoft : .white.opacity(0.7))
                .frame(width: 38, height: 38)
                .background(tone == .alert ? Palette.danger.opacity(0.12) : .white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(tone == .alert ? Palette.danger.opacity(0.3) : .white.opacity(0.1), lineWidth: 0.5))
            Text(failure.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone == .alert ? Palette.dangerText : .white)
            Text(failure.hint)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button(action: retry) {
                    Label("Tentar reconectar", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.horizontal, 28)
    }
}

/// Small monospaced tag on a dark capsule, used for telemetry over video.
struct OverlayTag: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
    }
}
