import SwiftUI
import SceneKit

/// SceneKit `SCNView`'ni SwiftUI'ga ko'prik qiluvchi konteyner.
struct SceneViewContainer: UIViewRepresentable {
    let controller: RoomSceneController

    func makeUIView(context: Context) -> SCNView {
        controller.scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
