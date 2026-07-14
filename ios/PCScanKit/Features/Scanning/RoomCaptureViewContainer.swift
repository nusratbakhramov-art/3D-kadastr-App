import SwiftUI
import ARKit

/// ARSCNView (kamera + jonli mesh wireframe) ni SwiftUI'ga ko'prik qiluvchi konteyner.
/// Ko'rinish ScanController tomonidan yaratiladi va egallanadi.
struct ARSceneContainer: UIViewRepresentable {
    let arView: ARSCNView

    func makeUIView(context: Context) -> ARSCNView {
        arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
