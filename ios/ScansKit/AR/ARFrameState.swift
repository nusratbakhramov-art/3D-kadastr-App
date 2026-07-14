import Foundation
import ARKit
import NSDK
import Combine

/// Har freymdagi AR holati — ARManager'ning frame loop'i tomonidan yangilanadi.
final class ARFrameState {

    @Published private(set) var camera: NSDKCamera?
    @Published private(set) var trackingState: ARCamera.TrackingState = .notAvailable

    func update(camera: NSDKCamera?) {
        self.camera = camera
    }

    func update(trackingState: ARCamera.TrackingState) {
        self.trackingState = trackingState
    }
}
