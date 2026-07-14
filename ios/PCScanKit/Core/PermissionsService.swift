import AVFoundation

/// Kamera ruxsatini boshqaruvchi servis.
@MainActor
final class PermissionsService: ObservableObject {
    enum State {
        case unknown
        case authorized
        case denied
    }

    @Published private(set) var camera: State = .unknown

    init() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = .authorized
        case .denied, .restricted: camera = .denied
        default: camera = .unknown
        }
    }

    /// Kamera ruxsatini so'raydi va natijani qaytaradi.
    @discardableResult
    func requestCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera = .authorized
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            camera = granted ? .authorized : .denied
            return granted
        default:
            camera = .denied
            return false
        }
    }
}
