import ARKit
import RoomPlan

/// Runtime gate for LiDAR-class devices. We do not require LiDAR via Info.plist
/// (there is no such device-capability key) — we check at launch and route the
/// user to an explanation screen on unsupported hardware.
enum DeviceCapability {
    /// True on devices whose ARKit build supports mesh scene reconstruction,
    /// i.e. those with a LiDAR scanner (iPhone Pro / iPad Pro lineup).
    static var supportsLiDARScanning: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static var supportsClassification: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    static var supportsSceneDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Apple RoomPlan availability (LiDAR + supported chip). Used to gate the
    /// wall/object-detecting capture flow.
    static var supportsRoomPlan: Bool {
        if #available(iOS 16, *) {
            return RoomCaptureSession.isSupported
        }
        return false
    }
}
