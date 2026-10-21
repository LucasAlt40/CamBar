import CamBarCore
import SwiftUI

/// Holds one view's stream lease and republishes it so SwiftUI redraws when it changes.
@MainActor
final class StreamSession: ObservableObject {
    @Published private(set) var lease: StreamLease?

    var stream: CameraStream? { lease?.stream }

    func attach(_ camera: Camera, hd: Bool, pool: StreamPool) {
        if let lease, lease.cameraID == camera.id { return }
        detach()
        lease = pool.lease(camera, hd: hd)
    }

    func detach() {
        lease?.release()
        lease = nil
    }

    func setHD(_ hd: Bool) { lease?.setHD(hd) }
}

/// Live picture of a camera. Leases the stream while visible and `isActive`.
struct CameraFeedView: View {
    @EnvironmentObject private var pool: StreamPool
    let camera: Camera
    var isActive = true
    var hd = false
    var showsStatus = true
    @StateObject private var session = StreamSession()

    var body: some View {
        ZStack {
            Color.black
            if let stream = session.stream {
                StreamFrameView(stream: stream, showsStatus: showsStatus)
            }
        }
        .onAppear(perform: sync)
        .onChange(of: isActive) { sync() }
        .onChange(of: camera.id) { sync() }
        .onChange(of: hd) { _, hd in session.setHD(hd) }
        .onDisappear { session.detach() }
    }

    private func sync() {
        if isActive { session.attach(camera, hd: hd, pool: pool) } else { session.detach() }
    }
}

/// Draws a stream: the latest frame plus connecting/failure states.
struct StreamFrameView: View {
    @ObservedObject var stream: CameraStream
    var showsStatus = true
    var retry: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let frame = stream.frame {
                Image(nsImage: frame).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Group {
                switch stream.status {
                case .connecting where stream.frame == nil:
                    ProgressView().controlSize(.small)
                case .failed(let failure):
                    FailureView(failure: failure, retry: retry)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsStatus {
                StatusChip(status: stream.status, style: .overlay).padding(10)
            }
        }
    }
}
