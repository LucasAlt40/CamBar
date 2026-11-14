import AppKit
import CamBarCore

/// "Buscar atualizações": asks GitHub and, when there is a new version, offers to open its download page.
@MainActor
enum Updates {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var isChecking = false

    static func checkInteractively() {
        guard !isChecking else { return }
        isChecking = true
        let current = currentVersion
        Task {
            let result = await UpdateChecker.check(currentVersion: current)
            isChecking = false
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            switch result {
            case .available(let release):
                alert.messageText = "Atualização disponível"
                alert.informativeText = "A versão \(release.version) do CamBar está disponível (você tem a \(current))."
                alert.addButton(withTitle: "Abrir página de download")
                alert.addButton(withTitle: "Agora não")
                if alert.runModal() == .alertFirstButtonReturn, let url = release.pageURL, url.host == "github.com" {
                    NSWorkspace.shared.open(url)
                }
            case .upToDate, .noReleases:
                alert.messageText = "Você já está na versão mais recente (\(current))."
                alert.runModal()
            case .failed:
                alert.alertStyle = .warning
                alert.messageText = "Não foi possível verificar agora"
                alert.informativeText = "Confira a conexão com a internet e tente de novo."
                alert.runModal()
            }
        }
    }
}
