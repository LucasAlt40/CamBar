import SwiftUI

@main
struct CamBarApp: App {
    @StateObject private var store = CameraStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(store)
        } label: {
            Image(nsImage: statusBarImage(online: store.online.count))
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Câmera", id: "viewer", for: UUID.self) { $id in
            if let id, let camera = store.camera(id) {
                ViewerView(camera: camera).environmentObject(store)
            }
        }
        .defaultSize(width: 960, height: 560)

        Window("Gerenciar câmeras", id: "manage") {
            ManageView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 640)
    }
}
