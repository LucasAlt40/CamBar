import SwiftUI

/// Directional pad + zoom. Holding a control moves the camera, releasing stops it;
/// the green knob in the middle works as a joystick, and a plain click on it recenters.
struct PTZPad: View {
    @ObservedObject var ptz: PTZController
    private let speed = 0.5

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                holdButton("plus", move: "zoom-in", zoom: speed)
                Hairline(color: .white.opacity(0.12)).frame(width: 18)
                holdButton("minus", move: "zoom-out", zoom: -speed)
            }
            .frame(width: 38, height: 84)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))

            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().stroke(.white.opacity(0.12), lineWidth: 0.5)
                holdButton("chevron.up", move: "up", tilt: speed).offset(y: -40)
                holdButton("chevron.down", move: "down", tilt: -speed).offset(y: 40)
                holdButton("chevron.left", move: "left", pan: -speed).offset(x: -40)
                holdButton("chevron.right", move: "right", pan: speed).offset(x: 40)
                PTZKnob(ptz: ptz)
            }
            .frame(width: 124, height: 124)
        }
    }

    private func holdButton(_ symbol: String, move: String,
                            pan: Double = 0, tilt: Double = 0, zoom: Double = 0) -> some View {
        let isActive = ptz.activeMove == move
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? Palette.accent : .white.opacity(0.9))
            .frame(width: 34, height: 34)
            .background(isActive ? Palette.accent.opacity(0.2) : .clear, in: Circle())
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in ptz.move(move, pan: pan, tilt: tilt, zoom: zoom) }
                .onEnded { _ in ptz.stop() })
    }
}

/// Offset of the dragged knob (kept outside the view because `@State` needs Xcode's macro plugins).
final class KnobOffset: ObservableObject {
    @Published var value = CGSize.zero
}

private struct PTZKnob: View {
    @ObservedObject var ptz: PTZController
    @StateObject private var offset = KnobOffset()
    private let radius: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Palette.accent.opacity(0.25))
            .overlay(Circle().fill(Palette.accent).frame(width: 7, height: 7))
            .overlay(Circle().stroke(Palette.accent.opacity(0.5), lineWidth: 0.5))
            .frame(width: 34, height: 34)
            .offset(offset.value)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let length = hypot(drag.translation.width, drag.translation.height)
                    let scale = length > radius ? radius / length : 1
                    offset.value = CGSize(width: drag.translation.width * scale, height: drag.translation.height * scale)
                    ptz.steer(dx: offset.value.width / radius, dy: -offset.value.height / radius)
                }
                .onEnded { drag in
                    if hypot(drag.translation.width, drag.translation.height) < 4 { ptz.goHome() }
                    ptz.stop()
                    withAnimation(.spring(response: 0.25)) { offset.value = .zero }
                })
            .help("Arraste para mover; clique para centralizar")
    }
}
