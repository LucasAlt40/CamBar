import CamBarCore
import SwiftUI

/// "Gerenciar câmeras": camera list on the left, connection form with live preview on the right.
struct SettingsView: View {
    @StateObject private var model: SettingsViewModel
    @EnvironmentObject private var store: CameraStore
    @EnvironmentObject private var reachability: ReachabilityMonitor

    init(model: SettingsViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Hairline()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    sidebar.frame(width: min(max(geo.size.width * 0.2, 250), 330))
                    Hairline(axis: .vertical)
                    detail
                }
            }
        }
        .background(Palette.window)
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear(perform: model.start)
        .confirmationDialog("Excluir esta câmera?", isPresented: $model.isConfirmingDelete) {
            Button("Excluir", role: .destructive, action: model.deleteSelected)
        }
    }

    // MARK: Title bar

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "video").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                Text("CamBar — Gerenciar Câmeras").font(.system(size: 13, weight: .semibold))
            }
            Button(action: model.startNewCamera) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Adicionar câmera")
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(Palette.titleBar)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField.padding(12)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle("CÂMERAS REGISTRADAS (\(store.cameras.count))")
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    if model.isNew {
                        CameraRow(camera: model.draft, number: store.cameras.count + 1,
                                  isSelected: true, isOnline: nil)
                    }
                    ForEach(model.filtered(store.cameras)) { camera in
                        Button { model.select(camera) } label: {
                            CameraRow(camera: camera, number: store.number(of: camera) ?? 0,
                                      isSelected: !model.isNew && camera.id == model.selectedID,
                                      isOnline: reachability.isOnline(camera.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            Hairline()
            addButton.padding(12)
        }
        .background(Palette.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            TextField("Buscar câmera...", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 0.5))
    }

    private var addButton: some View {
        Button(action: model.startNewCamera) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text("Adicionar Nova Câmera").font(.system(size: 12, weight: .medium))
                Text("⌘N")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let isWide = geo.size.width >= 900
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        detailHeader.padding(.bottom, 18)
                        if isWide {
                            // form on the left; live preview and signal test take the remaining width
                            HStack(alignment: .top, spacing: 24) {
                                formColumn.frame(width: min(max(geo.size.width * 0.4, 440), 620))
                                VStack(spacing: 18) {
                                    previewCard
                                    signalTestCard
                                }
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            formColumn
                            signalTestCard.padding(.top, 18)
                            previewCard.padding(.top, 18)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: isWide ? .infinity : 720)
                    .frame(maxWidth: .infinity)
                }
            }
            Hairline()
            actionBar
        }
        .background(Palette.window)
    }

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Configuração de Conexão").font(.system(size: 18, weight: .semibold))
                    Text("RTSP / ONVIF")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Palette.accent.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(Palette.accent.opacity(0.25), lineWidth: 0.5))
                }
                Text("Parâmetros de rede e credenciais de stream local")
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            reachabilityBadge
        }
    }

    private var reachabilityBadge: some View {
        let isOnline = reachability.isOnline(model.draft.id)
        return HStack(spacing: 7) {
            Circle().fill(isOnline ? Palette.accent : .gray).frame(width: 7, height: 7)
            Text(isOnline ? "ONLINE" : "OFFLINE")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOnline ? Palette.accent : .white.opacity(0.5))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 0.5))
    }

    private var formColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            form
            HStack(spacing: 7) {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Palette.accent.opacity(0.8))
                Text("A senha fica salva de forma segura no **Keychain do macOS**.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 12).padding(.horizontal, 4)
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            FormRow("Nome da Câmera") {
                TextField("Ex: Quintal", text: $model.draft.name).formFieldStyle()
            }
            FormRow("IP da câmera") {
                TextField("192.168.x.x", text: $model.draft.host).formFieldStyle(monospaced: true)
            }
            FormRow("Porta RTSP") {
                TextField("554", value: $model.draft.port, format: .number.grouping(.never)).formFieldStyle(monospaced: true)
            }
            FormRow("Caminho RTSP") {
                TextField("/onvif1", text: $model.draft.path).formFieldStyle(monospaced: true)
            }
            FormRow("Porta ONVIF (PTZ)") {
                TextField("automática", text: $model.onvifPortText).formFieldStyle(monospaced: true)
            }
            FormRow("Usuário") {
                TextField("Nome de usuário do feed", text: $model.draft.username).formFieldStyle()
            }
            FormRow("Senha") {
                HStack(spacing: 4) {
                    if model.showsPassword {
                        TextField("", text: $model.password).formFieldStyle(monospaced: true)
                    } else {
                        SecureField("", text: $model.password).formFieldStyle()
                    }
                    Button { model.showsPassword.toggle() } label: {
                        Image(systemName: model.showsPassword ? "eye.slash" : "eye")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            FormRow("Transporte", showsDivider: false) {
                Picker("", selection: $model.draft.transport) {
                    ForEach(RTSPTransport.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 0.5))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("PRÉ-VISUALIZAÇÃO")
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if let camera = model.savedCamera {
                        CameraFeedView(camera: camera)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "video.badge.plus").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                            Text("Salve a câmera para ver a imagem ao vivo")
                                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 0.5))
        }
        .padding(12)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.hairline, lineWidth: 0.5))
    }

    private var signalTestCard: some View {
        let (icon, title, tint): (String, String, Color) = {
            switch model.signalTest {
            case .idle: return ("bolt", "Pronto para testar", Palette.accent)
            case .testing: return ("bolt", "Testando…", Palette.warning)
            case .reachable: return ("checkmark", "A câmera respondeu na porta \(model.draft.port)", Palette.accent)
            case .unreachable: return ("xmark", "Sem resposta no IP e porta informados", Palette.danger)
            }
        }()
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.25), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(model.draft.displayURL)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Testar Sinal", action: model.testSignal)
                .buttonStyle(PillButtonStyle())
                .disabled(model.draft.host.isEmpty || model.signalTest == .testing)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 0.5))
    }

    private var actionBar: some View {
        HStack {
            Button { model.isConfirmingDelete = true } label: {
                Label("Excluir Câmera", systemImage: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.dangerSoft)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(model.isNew)
            .opacity(model.isNew ? 0.35 : 1)
            Spacer()
            Button("Cancelar", action: model.cancel).buttonStyle(PillButtonStyle())
            Button(action: model.save) {
                Label(model.justSaved ? "Salvo!" : "Salvar", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(Palette.accentStrong, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.accent.opacity(0.45), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSave)
            .opacity(model.canSave ? 1 : 0.45)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Palette.titleBar.opacity(0.6))
    }
}

// MARK: - Building blocks

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.45))
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    var showsDivider = true
    @ViewBuilder let content: Content

    init(_ label: String, showsDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.label = label
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 140, alignment: .leading)
                Spacer(minLength: 8)
                content.frame(maxWidth: 300, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            if showsDivider { Hairline(color: .white.opacity(0.06)) }
        }
    }
}

private struct CameraRow: View {
    let camera: Camera
    let number: Int
    let isSelected: Bool
    /// `nil` for the unsaved draft.
    let isOnline: Bool?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "video")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Palette.accent : .white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(isSelected ? Palette.accent.opacity(0.2) : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Palette.accent.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(camera.name.isEmpty ? "Nova câmera" : camera.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    if let isOnline {
                        Circle().fill(isOnline ? Palette.accent : .gray).frame(width: 6, height: 6)
                    }
                }
                Text(camera.host.isEmpty ? "sem IP" : camera.endpoint)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Palette.accent.opacity(0.9) : .white.opacity(0.45))
            }
            Spacer(minLength: 4)
            Text("cam \(number)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isSelected ? Palette.accent : .white.opacity(0.45))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(isSelected ? Palette.accent.opacity(0.18) : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isSelected ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Palette.accent.opacity(0.3) : .clear, lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}

private extension RTSPTransport {
    var label: String {
        switch self {
        case .auto: return "Automático"
        case .udp: return "UDP (Baixa Latência)"
        case .tcp: return "TCP (Confiável)"
        case .http: return "HTTP Tunneling"
        }
    }
}

private extension View {
    func formFieldStyle(monospaced: Bool = false) -> some View {
        textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
    }
}
