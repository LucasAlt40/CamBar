import Foundation

/// Where the camera list is persisted.
package protocol CameraRepository {
    func load() -> [Camera]
    func save(_ cameras: [Camera])
}

package struct UserDefaultsCameraRepository: CameraRepository {
    private let defaults: UserDefaults
    private let key: String

    package init(defaults: UserDefaults = .standard, key: String = "cameras") {
        self.defaults = defaults
        self.key = key
    }

    package func load() -> [Camera] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Camera].self, from: data)) ?? []
    }

    package func save(_ cameras: [Camera]) {
        guard let data = try? JSONEncoder().encode(cameras) else { return }
        defaults.set(data, forKey: key)
    }
}

/// In-memory repository for checks and previews.
package final class InMemoryCameraRepository: CameraRepository {
    package private(set) var cameras: [Camera]

    package init(_ cameras: [Camera] = []) { self.cameras = cameras }

    package func load() -> [Camera] { cameras }
    package func save(_ cameras: [Camera]) { self.cameras = cameras }
}
