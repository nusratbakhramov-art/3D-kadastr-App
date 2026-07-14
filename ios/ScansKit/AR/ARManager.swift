import UIKit
import ARKit
import RealityKit
import NSDK

/// AR infratuzilmasini boshqaradi: NSDKView, sensor dataSource va frame loop.
///
/// - NSDKView (live rejim) yaratadi va NSDKSession'ga DefaultSessionDataSource ulaydi
/// - ARSession lifecycle (start / stop)
/// - Har freymda `nsdkSession.update()` chaqiradi va ARFrameState'ni yangilaydi
final class ARManager: NSObject, UIOrientationReporter {

    let nsdkSession: NSDKSession
    let nsdkView = NSDKView()
    let frameState = ARFrameState()

    /// Har ARKit freymida chaqiriladigan ixtiyoriy hook (masalan, keyframe yig'ish).
    var onFrame: ((ARFrame) -> Void)?

    var currentOrientation: NSDKScreenOrientation {
        let orientation = nsdkView.window?.windowScene?.interfaceOrientation ?? .unknown
        return NSDKScreenOrientation(orientation)
    }

    private var dataSource: NSDKSessionDataSource?

    init(nsdkSession: NSDKSession) {
        self.nsdkSession = nsdkSession
        super.init()

        dataSource = DefaultSessionDataSource(
            session: nsdkView.session,
            orientationReporter: self
        )
        nsdkSession.dataSource = dataSource
        nsdkView.delegate = self
    }

    // MARK: - ARSession Lifecycle

    func startSession() {
        nsdkView.session.run(makeConfiguration())
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopSession() {
        nsdkView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARUtils.isLidarAvailable() {
            config.frameSemantics.insert(.sceneDepth)
        }
        return config
    }

    // MARK: - Camera Color Lock

    /// Ekspozitsiya va oq balansni qulflaydi — tekstura kadrlari bir xil
    /// yorug'lik/rangda bo'lishi uchun (skan paytida chaqiriladi).
    func lockCameraColor() {
        guard let device = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
            device.unlockForConfiguration()
        } catch {
            print("[ARManager] Camera color lock failed: \(error)")
        }
    }

    func unlockCameraColor() {
        guard let device = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            print("[ARManager] Camera color unlock failed: \(error)")
        }
    }

    // MARK: - Per-Frame Update

    private func handleFrameUpdate() {
        nsdkSession.update()
        frameState.update(camera: nsdkView.getCamera())
    }
}

// MARK: - NSDKViewDelegate

extension ARManager: NSDKViewDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        handleFrameUpdate()
        onFrame?(frame)
    }

    func playbackSession(_ session: PlaybackSession, didUpdate frame: PlaybackFrame) {
        handleFrameUpdate()
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        frameState.update(trackingState: camera.trackingState)
    }

    func playbackSession(
        _ session: PlaybackSession,
        cameraDidChangeTrackingState camera: PlaybackCamera
    ) {
        frameState.update(trackingState: camera.trackingState)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        frameState.update(trackingState: .notAvailable)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        nsdkView.session.run(
            makeConfiguration(),
            options: [.resetTracking, .removeExistingAnchors]
        )
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        print("[ARManager] ARSession failed: \(error.localizedDescription)")
    }
}
