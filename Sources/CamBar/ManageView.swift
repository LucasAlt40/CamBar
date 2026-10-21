import SwiftUI
import AppKit

extension Color {
    static let winBG = Color(hex: 0x0F1319)
    static let titleBG = Color(hex: 0x141922)
    static let sidebarBG = Color(hex: 0x121720)
    static let panelBG = Color(hex: 0x171C25)
    static let hairline = Color.white.opacity(0.08)
}

final class ManageModel: ObservableObject {
    enum Test: Equatable { case idle, testing, ok, fail }

    @Published var selectedID: UUID?
    @Published var draft = Camera(name: "", host: "")
    @Published var password = ""
    @Published var isNew = false
    @Published var search = ""
    @Published var showPassword = false
    @Published var test: Test = .idle
    @Published var confirmDelete = false
    @Published var justSaved = false
}

/// Makes the hosting window draggable from its background and blends the title bar into the content.
struct WindowChrome: NSViewRepresentable {
    /// When set, the window keeps this content aspect ratio while resizing (no letterbox bars).
    var aspectRatio: NSSize?

    func makeNSView(context: Context) -> NSView {
        let v = ChromeView()
        v.aspectRatio = aspectRatio
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        var aspectRatio: NSSize?

        override func viewDidMoveToWindow() {
            guard let w = window else { return }
            if let aspectRatio { w.contentAspectRatio = aspectRatio }
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(srgbRed: 0.059, green: 0.075, blue: 0.098, alpha: 1)
        }
    }
}

struct ManageView: View {
    @EnvironmentObject var store: CameraStore
    @StateObject private var m = ManageModel()

    private var filtered: [Camera] {
        let q = m.search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.cameras }
        return store.cameras.filter { $0.name.lowercased().contains(q) || $0.host.contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Rectangle().fill(Color.hairline).frame(height: 0.5)
            GeometryReader { geo in
                let sidebarWidth = min(max(geo.size.width * 0.2, 250), 330)
                HStack(spacing: 0) {
                    sidebar.frame(width: sidebarWidth)
                    Rectangle().fill(Color.hairline).frame(width: 0.5)
                    detail
                }
            }
        }
        .background(Color.winBG)
        .background(WindowChrome())
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            if let c = store.camera(store.selectedID) ?? store.cameras.first { select(c) } else { newCamera() }
        }
        .confirmationDialog("Excluir esta câmera?", isPresented: $m.confirmDelete) {
            Button("Excluir", role: .destructive) {
                if let c = store.camera(m.selectedID) {
                    store.remove(c)
                    if let first = store.cameras.first { select(first) } else { newCamera() }
                }
            }
        }
    }

    // MARK: Title bar

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "video").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentGreen)
                Text("CamBar — Gerenciar Câmeras").font(.system(size: 13, weight: .semibold))
            }
            HStack {
                Spacer()
                Button { newCamera() } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65)).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain).help("Adicionar câmera")
            }
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(Color.titleBG)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                TextField("Buscar câmera...", text: $m.search)
                    .textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline, lineWidth: 0.5))
            .padding(12)
            Rectangle().fill(Color.hairline).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CÂMERAS REGISTRADAS (\(store.cameras.count))")
                        .font(.system(size: 10.5, weight: .medium)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.45)).padding(.horizontal, 8).padding(.vertical, 6)
                    if m.isNew { row(m.draft, index: store.cameras.count + 1, selected: true, isDraft: true) }
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, cam in
                        row(cam, index: (store.cameras.firstIndex(of: cam) ?? i) + 1,
                            selected: !m.isNew && cam.id == m.selectedID, isDraft: false)
                    }
                }
                .padding(8)
            }

            Rectangle().fill(Color.hairline).frame(height: 0.5)
            Button { newCamera() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("Adicionar Nova Câmera").font(.system(size: 12, weight: .medium))
                    Text("⌘N").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain).keyboardShortcut("n", modifiers: .command)
            .padding(12)
        }
        .background(Color.sidebarBG)
    }

    private func row(_ cam: Camera, index: Int, selected: Bool, isDraft: Bool) -> some View {
        let online = store.online.contains(cam.id)
        return Button { if !isDraft { select(cam) } } label: {
            HStack(spacing: 10) {
                Image(systemName: "video")
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Color.accentGreen : .white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(selected ? Color.accentGreen.opacity(0.2) : Color.white.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(selected ? Color.accentGreen.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cam.name.isEmpty ? "Nova câmera" : cam.name)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(1)
                        if !isDraft {
                            Circle().fill(online ? Color.accentGreen : Color.gray).frame(width: 6, height: 6)
                        }
                    }
                    Text(cam.host.isEmpty ? "sem IP" : "\(cam.host):\(cam.port)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(selected ? Color.accentGreen.opacity(0.9) : .white.opacity(0.45))
                }
                Spacer(minLength: 4)
                Text("cam \(index)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(selected ? Color.accentGreen : .white.opacity(0.45))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(selected ? Color.accentGreen.opacity(0.18) : Color.white.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.accentGreen.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentGreen.opacity(0.3) : .clear, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let wide = geo.size.width >= 900
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        detailHeader.padding(.bottom, 18)
                        if wide {
                            // form on the left, live preview + signal test fill the rest of the width
                            let formWidth = min(max(geo.size.width * 0.4, 440), 620)
                            HStack(alignment: .top, spacing: 24) {
                                formColumn.frame(width: formWidth)
                                VStack(spacing: 18) {
                                    previewCard
                                    testBlock
                                }
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            formColumn
                            testBlock.padding(.top, 18)
                            previewCard.padding(.top, 18)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: wide ? .infinity : 720)
                    .frame(maxWidth: .infinity)
                }
            }

            Rectangle().fill(Color.hairline).frame(height: 0.5)
            actionBar
        }
        .background(Color.winBG)
    }

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Configuração de Conexão").font(.system(size: 18, weight: .semibold))
                    Text("RTSP / ONVIF")
                        .font(.system(size: 10.5)).foregroundStyle(Color.accentGreen)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.accentGreen.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(Color.accentGreen.opacity(0.25), lineWidth: 0.5))
                }
                Text("Parâmetros de rede e credenciais de stream local")
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            reachBadge
        }
    }

    private var formColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            card
            HStack(spacing: 7) {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Color.accentGreen.opacity(0.8))
                Text("A senha fica salva de forma segura no **Keychain do macOS**.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 12).padding(.horizontal, 4)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PRÉ-VISUALIZAÇÃO").font(.system(size: 10.5, weight: .medium)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
            }
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if !m.isNew, let cam = store.camera(m.selectedID) {
                        LiveFeed(camera: cam)
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
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline, lineWidth: 0.5))
        }
        .padding(12)
        .background(Color.panelBG, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hairline, lineWidth: 0.5))
    }

    private var reachBadge: some View {
        let up = store.online.contains(m.draft.id)
        return HStack(spacing: 7) {
            Circle().fill(up ? Color.accentGreen : Color.gray).frame(width: 7, height: 7)
            Text(up ? "ONLINE" : "OFFLINE").font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(up ? Color.accentGreen : .white.opacity(0.5))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline, lineWidth: 0.5))
    }

    private var card: some View {
        VStack(spacing: 0) {
            field("Nome da Câmera") {
                TextField("Ex: Quintal", text: $m.draft.name).fieldStyle()
            }
            field("IP da câmera") {
                TextField("192.168.x.x", text: $m.draft.host).fieldStyle(mono: true)
            }
            field("Porta RTSP") {
                TextField("554", value: $m.draft.port, format: .number.grouping(.never)).fieldStyle(mono: true)
            }
            field("Caminho RTSP") {
                TextField("/onvif1", text: $m.draft.path).fieldStyle(mono: true)
            }
            field("Porta ONVIF (PTZ)") {
                TextField("automática", text: Binding(get: { m.draft.onvifPort.map(String.init) ?? "" },
                                                      set: { m.draft.onvifPort = Int($0) })).fieldStyle(mono: true)
            }
            field("Usuário") {
                TextField("Nome de usuário do feed", text: $m.draft.username).fieldStyle()
            }
            field("Senha") {
                HStack(spacing: 4) {
                    if m.showPassword {
                        TextField("", text: $m.password).fieldStyle(mono: true)
                    } else {
                        SecureField("", text: $m.password).textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing).font(.system(size: 12))
                    }
                    Button { m.showPassword.toggle() } label: {
                        Image(systemName: m.showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            field("Transporte", last: true) {
                Picker("", selection: Binding(get: { m.draft.transport ?? "auto" },
                                              set: { m.draft.transport = $0 })) {
                    Text("Automático").tag("auto")
                    Text("UDP (Baixa Latência)").tag("udp")
                    Text("TCP (Confiável)").tag("tcp")
                    Text("HTTP Tunneling").tag("http")
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
        .background(Color.panelBG, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline, lineWidth: 0.5))
    }

    private func field<C: View>(_ label: String, last: Bool = false, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.78))
                    .frame(width: 140, alignment: .leading)
                Spacer(minLength: 8)
                content().frame(maxWidth: 300, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            if !last { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5) }
        }
    }

    private var testBlock: some View {
        let (icon, title, tint): (String, String, Color) = {
            switch m.test {
            case .idle: return ("bolt", "Pronto para testar", Color.accentGreen)
            case .testing: return ("bolt", "Testando…", Color.orange)
            case .ok: return ("checkmark", "A câmera respondeu na porta \(m.draft.port)", Color.accentGreen)
            case .fail: return ("xmark", "Sem resposta no IP e porta informados", Color.red)
            }
        }()
        return HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.25), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text("rtsp://\(m.draft.host.isEmpty ? "…" : m.draft.host):\(m.draft.port)\(m.draft.path.hasPrefix("/") ? m.draft.path : "/" + m.draft.path)")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Testar Sinal") { runTest() }
                .buttonStyle(PillButtonStyle()).disabled(m.draft.host.isEmpty || m.test == .testing)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 0.5))
    }

    private var actionBar: some View {
        HStack {
            Button { m.confirmDelete = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 11))
                    Text("Excluir Câmera").font(.system(size: 12))
                }
                .foregroundStyle(Color(hex: 0xFB7185))
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.plain).disabled(m.isNew).opacity(m.isNew ? 0.35 : 1)
            Spacer()
            Button("Cancelar") { cancel() }.buttonStyle(PillButtonStyle())
            Button { save() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text(m.justSaved ? "Salvo!" : "Salvar").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background(Color(hex: 0x059669), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentGreen.opacity(0.45), lineWidth: 0.5))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            .disabled(m.draft.host.isEmpty || m.draft.name.isEmpty)
            .opacity(m.draft.host.isEmpty || m.draft.name.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Color.titleBG.opacity(0.6))
    }

    // MARK: Actions

    private func select(_ cam: Camera) {
        m.selectedID = cam.id
        m.draft = cam
        m.password = Keychain.password(for: cam.id)
        m.isNew = false
        m.showPassword = false
        m.test = .idle
        store.selectedID = cam.id
    }

    private func newCamera() {
        m.draft = Camera(name: "", host: "")
        m.selectedID = m.draft.id
        m.password = ""
        m.isNew = true
        m.showPassword = false
        m.test = .idle
    }

    private func cancel() {
        if let c = store.camera(m.selectedID), !m.isNew { select(c) }
        else if let first = store.cameras.first { select(first) }
        else { newCamera() }
    }

    private func save() {
        store.upsert(m.draft, password: m.password)
        m.isNew = false
        m.selectedID = m.draft.id
        m.justSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { m.justSaved = false }
    }

    private func runTest() {
        m.test = .testing
        let host = m.draft.host, port = m.draft.port
        Task {
            let ok = await tcpReachable(host: host, port: port, timeout: 3)
            await MainActor.run { m.test = ok ? .ok : .fail }
        }
    }
}

private extension View {
    func fieldStyle(mono: Bool = false) -> some View {
        self.textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12, design: mono ? .monospaced : .default))
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
