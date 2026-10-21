import CamBarCore
import Foundation

/// Editing state of the settings window: which camera is selected, the draft being edited and the signal test.
@MainActor
final class SettingsViewModel: ObservableObject {
    enum SignalTest: Equatable { case idle, testing, reachable, unreachable }

    @Published var draft = Camera()
    @Published var password = ""
    @Published var search = ""
    @Published var showsPassword = false
    @Published var isConfirmingDelete = false
    @Published private(set) var selectedID: UUID?
    @Published private(set) var isNew = false
    @Published private(set) var signalTest: SignalTest = .idle
    @Published private(set) var justSaved = false

    let store: CameraStore
    private let checker: ReachabilityChecking
    private var testTask: Task<Void, Never>?
    private var savedTask: Task<Void, Never>?

    init(store: CameraStore, checker: ReachabilityChecking) {
        self.store = store
        self.checker = checker
    }

    var canSave: Bool { !draft.name.isEmpty && !draft.host.isEmpty }

    /// The saved camera being edited (nil while creating a new one).
    var savedCamera: Camera? { isNew ? nil : store.camera(selectedID) }

    /// Text binding for the optional ONVIF port.
    var onvifPortText: String {
        get { draft.onvifPort.map(String.init) ?? "" }
        set { draft.onvifPort = Int(newValue) }
    }

    func filtered(_ cameras: [Camera]) -> [Camera] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return cameras }
        return cameras.filter { $0.name.lowercased().contains(query) || $0.host.contains(query) }
    }

    // MARK: Actions

    func start() {
        if let camera = store.selected ?? store.cameras.first { select(camera) } else { startNewCamera() }
    }

    func select(_ camera: Camera) {
        selectedID = camera.id
        draft = camera
        password = store.password(for: camera.id)
        isNew = false
        resetTransientState()
        store.selectedID = camera.id
    }

    func startNewCamera() {
        draft = Camera()
        selectedID = draft.id
        password = ""
        isNew = true
        resetTransientState()
    }

    func cancel() {
        if let camera = savedCamera ?? store.cameras.first { select(camera) } else { startNewCamera() }
    }

    func save() {
        guard canSave else { return }
        store.save(draft, password: password)
        isNew = false
        selectedID = draft.id
        justSaved = true
        savedTask?.cancel()
        savedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.justSaved = false
        }
    }

    func deleteSelected() {
        guard let camera = savedCamera else { return }
        store.delete(camera)
        if let first = store.cameras.first { select(first) } else { startNewCamera() }
    }

    func testSignal() {
        signalTest = .testing
        let host = draft.host, port = draft.port, checker = checker
        testTask?.cancel()
        testTask = Task { [weak self] in
            let reachable = await checker.isReachable(host: host, port: port, timeout: 3)
            guard !Task.isCancelled else { return }
            self?.signalTest = reachable ? .reachable : .unreachable
        }
    }

    private func resetTransientState() {
        showsPassword = false
        testTask?.cancel()
        signalTest = .idle
    }
}
