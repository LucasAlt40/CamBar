import CamBarCore
import SwiftUI

/// State of "Procurar câmeras na rede": nothing runs until the user agrees, then results arrive live.
@MainActor
final class ScannerModel: ObservableObject {
    enum Phase: Equatable { case intro, scanning, finished, stopped }

    @Published private(set) var phase: Phase = .intro
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var progress = ScanProgress(checked: 0, total: 0)
    let networks = NetworkScanner.localNetworks()
    private var task: Task<Void, Never>?

    var fraction: Double { progress.total == 0 ? 0 : Double(progress.checked) / Double(progress.total) }

    func start() {
        task?.cancel()
        devices = []
        progress = ScanProgress(checked: 0, total: 0)
        phase = .scanning
        let networks = networks
        task = Task { [weak self] in
            _ = await NetworkScanner.scan(networks: networks,
                progress: { value in Task { @MainActor in self?.progress = value } },
                found: { device in Task { @MainActor in self?.show(device) } })
            guard let self, self.phase == .scanning else { return }
            self.phase = Task.isCancelled ? .stopped : .finished
        }
    }

    func stop() {
        task?.cancel()
        if phase == .scanning { phase = .stopped }
    }

    private func show(_ device: DiscoveredDevice) {
        if let index = devices.firstIndex(where: { $0.host == device.host }) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { NetworkScanner.hostOrder($0.host, $1.host) }
        }
    }
}

/// Sheet of the settings window: explains the scan, runs it with the user's permission and lists what answered.
struct ScannerView: View {
    @StateObject private var model = ScannerModel()
    @EnvironmentObject private var store: CameraStore
    let add: (DiscoveredDevice) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Palette.accent)
                    Text("Procurar câmeras na rede").font(.system(size: 17, weight: .semibold))
                }
                Text(status).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if model.phase != .intro {
                    ProgressView(value: model.fraction).tint(Palette.accent)
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)

            Group {
                if model.phase == .intro { intro } else { results }
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity, alignment: .top)

            Hairline()
            HStack {
                Spacer()
                switch model.phase {
                case .intro:
                    Button("Cancelar", action: close).buttonStyle(PillButtonStyle())
                    primary("Iniciar busca", action: model.start).disabled(model.networks.isEmpty)
                case .scanning:
                    Button("Parar", action: model.stop).buttonStyle(PillButtonStyle())
                case .finished, .stopped:
                    Button("Fechar", action: close).buttonStyle(PillButtonStyle())
                    primary("Buscar de novo", action: model.start)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(Palette.titleBar.opacity(0.6))
        }
        .frame(width: 560, height: 520)
        .background(Palette.window)
        .preferredColorScheme(.dark)
        .onDisappear(perform: model.stop)
    }

    private var status: String {
        let found = foundText(model.devices.count)
        switch model.phase {
        case .intro:
            return model.networks.isEmpty
                ? "Nenhuma rede local foi encontrada. Conecte o Mac à mesma rede das câmeras e tente de novo."
                : "Nada é feito até você clicar em Iniciar busca."
        case .scanning:
            return "Verificando \(model.progress.checked) de \(model.progress.total) portas… \(found)"
        case .finished:
            return model.devices.isEmpty
                ? "Busca concluída: nada respondeu como câmera. Confira se as câmeras estão ligadas e se o RTSP/ONVIF está ativo no app delas."
                : "Busca concluída: \(found)."
        case .stopped:
            return "Busca interrompida. \(found)"
        }
    }

    private func foundText(_ count: Int) -> String {
        switch count {
        case 0: return "Nenhuma câmera encontrada até agora."
        case 1: return "1 possível câmera encontrada"
        default: return "\(count) possíveis câmeras encontradas"
        }
    }

    private var intro: some View {
        let networks = model.networks.isEmpty ? "—" : model.networks.map(\.description).joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 10) {
            Text("O CamBar pode procurar aparelhos na sua rede local que pareçam câmeras. Para isso ele vai:")
            Text("•  enviar uma pergunta ONVIF (WS-Discovery) para a rede, que as câmeras compatíveis respondem;")
            Text("•  testar as portas RTSP 554 e 8554 em cada endereço de \(networks) (até 254 por rede).")
            Text("Nada sai da sua rede local e nenhuma senha é enviada. O macOS pode pedir permissão de acesso à rede local; aceite para a busca funcionar.")
                .foregroundStyle(.white.opacity(0.55)).padding(.top, 4)
            Text("Só faça a busca em uma rede que é sua ou em que você tem permissão.")
                .foregroundStyle(Palette.warningText)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.white.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 0.5))
    }

    private var results: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.devices) { device in row(device) }
            }
        }
    }

    private func row(_ device: DiscoveredDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "video")
                .font(.system(size: 12))
                .foregroundStyle(Palette.accent)
                .frame(width: 30, height: 30)
                .background(Palette.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(device.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(device.host).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.accent)
                Text(device.evidence).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if let existing = store.cameras.first(where: { $0.host == device.host }) {
                Text("Já cadastrada: \(existing.name)")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())
            } else {
                Button { add(device) } label: { Label("Adicionar", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.hairline, lineWidth: 0.5))
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background(Palette.accentStrong, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }
}
