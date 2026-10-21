import CamBarCore
import Combine
import Foundation

/// Something other services need to react to (streams restart on edit, stop on delete).
enum CameraChange {
    case updated(Camera)
    case removed(UUID)
}

/// Source of truth for the camera list. Persists through a repository; passwords go to a credential store.
@MainActor
final class CameraStore: ObservableObject {
    @Published private(set) var cameras: [Camera]
    @Published var selectedID: UUID?

    let changes = PassthroughSubject<CameraChange, Never>()

    private let repository: CameraRepository
    private let credentials: CredentialStore

    init(repository: CameraRepository, credentials: CredentialStore) {
        self.repository = repository
        self.credentials = credentials
        cameras = repository.load()
        selectedID = cameras.first?.id
    }

    var selected: Camera? { camera(selectedID) }

    func camera(_ id: UUID?) -> Camera? {
        guard let id else { return nil }
        return cameras.first { $0.id == id }
    }

    /// 1-based position, used for the "cam N" labels.
    func number(of camera: Camera) -> Int? {
        cameras.firstIndex { $0.id == camera.id }.map { $0 + 1 }
    }

    func password(for id: UUID) -> String { credentials.password(for: id) }

    func save(_ camera: Camera, password: String) {
        credentials.setPassword(password, for: camera.id)
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[index] = camera
        } else {
            cameras.append(camera)
            if selectedID == nil { selectedID = camera.id }
        }
        repository.save(cameras)
        changes.send(.updated(camera))
    }

    func delete(_ camera: Camera) {
        cameras.removeAll { $0.id == camera.id }
        credentials.setPassword("", for: camera.id)
        if selectedID == camera.id { selectedID = cameras.first?.id }
        repository.save(cameras)
        changes.send(.removed(camera.id))
    }
}
