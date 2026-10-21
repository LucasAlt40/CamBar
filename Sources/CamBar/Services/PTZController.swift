import CamBarCore
import Foundation

/// Pan/tilt/zoom for one camera over ONVIF. Commands are serialized so a stop never overtakes its move.
@MainActor
final class PTZController: ObservableObject {
    enum State: Equatable { case idle, detecting, available, unavailable }

    @Published private(set) var state: State = .idle
    /// The move currently in progress (used to highlight the pressed control).
    @Published private(set) var activeMove: String?

    private let log: FileLog?
    private var client: ONVIFClient?
    private var endpoint: PTZEndpoint?
    private var queue: Task<Void, Never>?

    init(log: FileLog?) { self.log = log }

    func detect(camera: Camera, password: String) {
        guard state == .idle else { return }
        state = .detecting
        log?.clear()
        let client = ONVIFClient(username: camera.username, password: password, log: log)
        self.client = client
        let ports = camera.onvifPort.map { [$0] } ?? ONVIFClient.defaultPorts
        Task { [weak self] in
            let found = await client.discoverPTZ(host: camera.host, ports: ports)
            self?.endpoint = found
            self?.state = found == nil ? .unavailable : .available
        }
    }

    /// Starts a continuous move that lasts until `stop()`. Repeating the same move is ignored.
    func move(_ name: String, pan: Double, tilt: Double, zoom: Double) {
        guard state == .available, activeMove != name else { return }
        activeMove = name
        enqueue { client, endpoint in await client.continuousMove(endpoint, pan: pan, tilt: tilt, zoom: zoom) }
    }

    /// Joystick input in -1...1 per axis (y up). Quantized so the camera only gets a new command
    /// when the direction or speed noticeably changes.
    func steer(dx: Double, dy: Double) {
        func quantize(_ v: Double) -> Double { abs(v) < 0.25 ? 0 : (v * 4).rounded() / 4 }
        let pan = quantize(dx), tilt = quantize(dy)
        if pan == 0 && tilt == 0 {
            stop()
        } else {
            move("joystick \(pan) \(tilt)", pan: pan, tilt: tilt, zoom: 0)
        }
    }

    func stop() {
        guard activeMove != nil else { return }
        activeMove = nil
        enqueue { client, endpoint in await client.stop(endpoint) }
    }

    func goHome() {
        guard state == .available else { return }
        enqueue { client, endpoint in await client.goHome(endpoint) }
    }

    private func enqueue(_ command: @escaping @Sendable (ONVIFClient, PTZEndpoint) async -> Void) {
        guard let client, let endpoint else { return }
        let previous = queue
        queue = Task {
            await previous?.value
            await command(client, endpoint)
        }
    }
}
