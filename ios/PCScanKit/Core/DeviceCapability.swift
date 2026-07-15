import ARKit
import RoomPlan
import RealityKit

/// Qurilma imkoniyatlarini (LiDAR / RoomPlan / Object Capture) tekshiruvchi servis.
enum DeviceCapability {

    /// LiDAR-asosidagi scene reconstruction qo'llab-quvvatlanadimi.
    static var supportsLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// RoomPlan sessiyasi ushbu qurilmada ishlaydimi (LiDAR talab qiladi).
    static var supportsRoomPlan: Bool {
        RoomCaptureSession.isSupported
    }

    /// Object Capture (fotogrammetriya) on-device qo'llab-quvvatlanadimi.
    static var supportsObjectCapture: Bool {
        PhotogrammetrySession.isSupported
    }

    /// Ilovaning asosiy funksiyasi (skanerlash) uchun minimal talab.
    static var meetsMinimumRequirements: Bool {
        supportsRoomPlan
    }

    /// Foydalanuvchiga ko'rsatiladigan qisqa diagnostika matni.
    static var summary: String {
        var lines: [String] = []
        lines.append(supportsRoomPlan ? "✓ LiDAR / RoomPlan" : "✗ LiDAR / RoomPlan (qurilma qo'llab-quvvatlamaydi)")
        lines.append(supportsObjectCapture
                     ? "✓ Object Capture (real tekstura)"
                     : "✗ Object Capture (faqat parametrik model bo'ladi)")
        return lines.joined(separator: "\n")
    }
}
