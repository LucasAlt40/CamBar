import CamBarCore
import Combine
import Foundation

/// State and actions of the expanded camera window.
@MainActor
final class ViewerViewModel: ObservableObject {
    /// Follows edits made in settings while the window is open (name, host, credentials).
    @Published private(set) var camera: Camera
    let session = StreamSession()
    let audio = AudioPlayer()
    let ptz: PTZController

    @Published var isHD = true {
        didSet { session.setHD(isHD) }
    }
    @Published var isHovering = true
    @Published private(set) var toast: String?

    private let store: CameraStore
    private let pool: StreamPool
    private var toastTask: Task<Void, Never>?
    private var subscription: AnyCancellable?

    init(camera: Camera, store: CameraStore, pool: StreamPool, ptzLog: FileLog?) {
        self.camera = camera
        self.store = store
        self.pool = pool
        ptz = PTZController(log: ptzLog)
        subscription = store.changes.sink { [weak self] change in
            guard let self, case .updated(let updated) = change, updated.id == self.camera.id else { return }
            self.camera = updated
            // audio runs its own ffmpeg with the old address and credentials
            self.audio.stop()
        }
    }

    func appear() {
        session.attach(camera, hd: isHD, pool: pool)
        ptz.detect(camera: camera, password: store.password(for: camera.id))
    }

    func disappear() {
        ptz.stop()
        audio.stop()
        session.detach()
    }

    func toggleAudio() {
        if audio.isPlaying {
            audio.stop()
        } else {
            audio.start(camera: camera, password: store.password(for: camera.id))
        }
    }

    func takeSnapshot() {
        guard let frame = session.stream?.frame else { return }
        do {
            try Snapshot.save(frame, cameraName: camera.name)
            showToast("Foto salva em Imagens/CamBar")
        } catch {
            showToast("Não foi possível salvar a foto")
        }
    }

    private func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
