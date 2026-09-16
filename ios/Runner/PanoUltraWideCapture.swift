// Astra 0.5 ultra-wide capture, adapted to Kadastr's MethodChannel and directory lifecycle.
import AVFoundation
import Combine
import CoreMedia
import CoreMotion
import Flutter
import ImageIO
import simd
import SwiftUI
import UIKit

/// Capture selection is independent of panorama viewer and processing capabilities.
enum PanoCaptureMode: String {
    case arkit, ultrawide

    static func resolve(_ value: Any?) -> PanoCaptureMode? {
        guard let value else { return .arkit }
        guard let name = value as? String else { return nil }
        return PanoCaptureMode(rawValue: name)
    }

    @available(iOS 15.0, *)
    func start(from presenter: UIViewController, strings: [String: String], result: @escaping FlutterResult) {
        switch self {
        case .arkit: PanoCaptureCoordinator.shared.start(from: presenter, strings: strings, result: result)
        case .ultrawide:
            if #available(iOS 15.4, *) {
                PanoUltraWideCaptureCoordinator.shared.start(from: presenter, strings: strings, result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED_IOS", message: "Ultra-keng suratga olish uchun iOS 15.4+ kerak", details: nil))
            }
        }
    }
}

struct PanoUltraWideCapability {
    let cameraAuthorization: AVAuthorizationStatus
    let reason: String?
    var available: Bool { reason == nil }

    init(supportedOS: Bool, hasCamera: Bool, hasMotion: Bool, authorization: AVAuthorizationStatus) {
        cameraAuthorization = authorization
        if !supportedOS { reason = "UNSUPPORTED_IOS" }
        else if !hasCamera { reason = "NO_ULTRAWIDE_CAMERA" }
        else if !hasMotion { reason = "NO_DEVICE_MOTION" }
        else if authorization == .denied || authorization == .restricted { reason = "CAMERA_PERMISSION" }
        else { reason = nil }
    }

    static func current() -> Self {
        let supportedOS: Bool
        if #available(iOS 15.4, *) { supportedOS = true } else { supportedOS = false }
        return Self(supportedOS: supportedOS,
                    hasCamera: AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil,
                    hasMotion: CMMotionManager().isDeviceMotionAvailable,
                    authorization: AVCaptureDevice.authorizationStatus(for: .video))
    }

    var channelValue: [String: Any] {
        let authorization: String
        switch cameraAuthorization {
        case .authorized: authorization = "authorized"
        case .notDetermined: authorization = "notDetermined"
        case .denied: authorization = "denied"
        case .restricted: authorization = "restricted"
        @unknown default: authorization = "unknown"
        }
        return ["available": available, "cameraAuthorization": authorization,
                "reason": reason as Any? ?? NSNull()]
    }
}

/// Acquisition order is separate from target IDs. All access is on the main queue.
/// A frame becomes accepted only AFTER its JPEG and metadata have reached disk.
struct PanoUltraWideCaptureState {
    struct Shot: Equatable { let index: Int; let targetId: Int }
    let targets = PanoTargetGrid.ultraWide17()
    private(set) var metas: [PanoFrameMeta] = []
    private(set) var pending: Shot?
    private(set) var ended = false
    private var nextIndex = 0
    var captured: Set<Int> { Set(metas.map { $0.targetId }) }
    var complete: Bool { captured.count == targets.count }

    mutating func reserve(targetId: Int) -> Shot? {
        guard !ended, pending == nil, !captured.contains(targetId),
              targets.contains(where: { $0.id == targetId }) else { return nil }
        let shot = Shot(index: nextIndex, targetId: targetId)
        nextIndex += 1
        pending = shot
        return shot
    }

    @discardableResult
    mutating func accept(_ meta: PanoFrameMeta) -> Bool {
        guard !ended, let shot = pending, shot.index == meta.index, shot.targetId == meta.targetId else { return false }
        metas.append(meta)
        pending = nil
        return true
    }

    mutating func reject() { pending = nil }

    @discardableResult
    mutating func undo() -> PanoFrameMeta? {
        guard !ended, pending == nil else { return nil }
        return metas.popLast()
    }

    mutating func finish(confirmedEarly: Bool) -> Int? {
        guard !ended, pending == nil, complete || (confirmedEarly && metas.count >= 4) else { return nil }
        ended = true
        return metas.count
    }

    mutating func cancel() { ended = true; pending = nil }
}

/// Continuous dwell is reset by a target change, movement, tilt, pause, or a sample gap.
struct PanoUltraWideDwellGate {
    private var target: Int?
    private var start: TimeInterval?
    private var lastTime: TimeInterval?

    mutating func reset() { target = nil; start = nil; lastTime = nil }

    mutating func update(targetID: Int?, angle: Float, angularSpeed: Float, levelOK: Bool,
                         enabled: Bool, time: TimeInterval) -> Double {
        guard enabled, levelOK, let targetID, time.isFinite,
              angle < PanoUltraWidePose.angleThreshold,
              angularSpeed < PanoUltraWidePose.maxAngularSpeed else { reset(); return 0 }
        if target != targetID || lastTime == nil || time < lastTime! || time - lastTime! > 0.1 {
            target = targetID
            start = time
        }
        lastTime = time
        return min(1, (time - (start ?? time)) / PanoUltraWidePose.dwellSeconds)
    }
}

/// Reference attitude and sensor-pixel convention from Astra's UltraWideCaptureController.
enum PanoUltraWidePose {
    static let angleThreshold: Float = 6 * .pi / 180
    static let maxAngularSpeed: Float = 8 * .pi / 180
    static let maxRoll: Float = 12 * .pi / 180
    static let dwellSeconds = 0.35

    // Sensor image-right points down a portrait phone. Core forward is -Z.
    static let sensorToDevice = simd_float3x3(columns: (
        SIMD3<Float>(0, -1, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)))
    static let referenceToWorld = simd_float3x3(rows: [
        SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, -1, 0)])

    static func rotation(attitude: simd_float3x3, gravity: SIMD3<Float>,
                         needsTranspose: inout Bool?) -> simd_float3x3 {
        if needsTranspose == nil, simd_length(gravity) > 0.5 {
            needsTranspose = (attitude * simd_normalize(gravity)).z > -0.8
        }
        return referenceToWorld * (needsTranspose == true ? attitude.transpose : attitude) * sensorToDevice
    }

    static func roll(gravity: SIMD3<Float>) -> Float {
        guard simd_length(gravity) > 0.5 else { return 0 }
        let up = sensorToDevice.transpose * simd_normalize(-gravity)
        return atan2(up.y, -up.x)
    }

    /// Validate the actual exposure, including pole-aware roll; never use request-time pose.
    static func atExposure(time: TimeInterval, history: CapturePoseHistory, target: PanoTarget) -> simd_float3x3? {
        guard let rotation = history.rotation(at: time, maxAngularSpeed: maxAngularSpeed),
              simd_dot(-rotation.columns.2, target.direction) >= cos(angleThreshold) else { return nil }
        let up = rotation.transpose * SIMD3<Float>(0, 1, 0)
        var level = CaptureLevelState()
        guard level.update(forwardY: -rotation.columns.2.y, gravityRoll: atan2(up.y, -up.x), maxRoll: maxRoll) else { return nil }
        return rotation
    }

    static func metadata(shot: PanoUltraWideCaptureState.Shot, target: PanoTarget,
                         rotation r: simd_float3x3, intrinsics: [Float], width: Int, height: Int,
                         timestamp: TimeInterval) -> PanoFrameMeta {
        PanoFrameMeta(index: shot.index, targetId: target.id, targetYaw: target.yaw, targetPitch: target.pitch,
                      transform: [r.columns.0.x, r.columns.0.y, r.columns.0.z, 0,
                                  r.columns.1.x, r.columns.1.y, r.columns.1.z, 0,
                                  r.columns.2.x, r.columns.2.y, r.columns.2.z, 0, 0, 0, 0, 1],
                      intrinsics: intrinsics, imageWidth: width, imageHeight: height,
                      pixelWidth: width, pixelHeight: height, timestamp: timestamp,
                      highRes: true, file: "frame_\(shot.index).jpg", poseSource: "sensors:coremotion")
    }
}

/// Disk operations run on the controller's serial IO queue. Metadata is the commit record.
enum PanoUltraWideFiles {
    static func writeMetas(_ metas: [PanoFrameMeta], dir: URL) throws {
        try JSONEncoder().encode(metas).write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
    }

    static func save(image: CGImage, meta: PanoFrameMeta, previous: [PanoFrameMeta], dir: URL) throws {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "PanoCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "JPEG yaratilmadi"])
        }
        // Keep raw landscape pixels; the pose/intrinsics refer to these pixels, not EXIF display rotation.
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.90,
                                                kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "PanoCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "JPEG yozilmadi"])
        }
        let file = dir.appendingPathComponent(meta.file)
        try (data as Data).write(to: file, options: .atomic)
        do { try writeMetas(previous + [meta], dir: dir) }
        catch { try? FileManager.default.removeItem(at: file); throw error }
    }

    static func undo(metas: [PanoFrameMeta], dir: URL) throws {
        guard let last = metas.last else { return }
        try writeMetas(Array(metas.dropLast()), dir: dir)
        // A leftover JPEG is harmless after removing its metadata entry.
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(last.file))
    }
}

@available(iOS 15.4, *)
final class PanoUltraWideCaptureController: NSObject, ObservableObject,
    AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Dot: Identifiable {
        let id: Int
        var point: CGPoint
        var visible: Bool
        var captured: Bool
        var angle: Float
        var isNext: Bool
    }
    @Published var dots: [Dot] = []
    @Published var capturedCount = 0
    @Published var nearestAngle: Float = 999
    @Published var dwellProgress: Double = 0
    @Published var message = ""
    @Published var isCapturing = false
    @Published var ready = false
    @Published var levelOK = true
    @Published var rollRadians: Double = 0
    @Published var lastThumb: UIImage?
    @Published var chevronAngle: Double?
    @Published var canUndo = false
    @Published var fatalError: String?
    private(set) var failureCode = "CAPTURE_FAILED"

    let dir: URL
    let strings: [String: String]
    let targets = PanoTargetGrid.ultraWide17()
    var requiredTotal: Int { targets.count }
    var viewSize: CGSize = .zero
    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    private let motion = CMMotionManager()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "kadastr.pano.uw.video")
    private let sessionQueue = DispatchQueue(label: "kadastr.pano.uw.session")
    private let ioQueue = DispatchQueue(label: "kadastr.pano.uw.io", qos: .userInitiated)
    private var sensorIntrinsics: CaptureIntrinsics? // videoQueue only
    private var device: AVCaptureDevice?             // sessionQueue only
    private var settingsLocked = false              // sessionQueue only
    private var configured = false                 // sessionQueue only
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    // Capture/pose/UI state is main-queue owned. Camera startup and disk work never block it.
    private var state = PanoUltraWideCaptureState()
    private var active = false
    private var started = false
    private var pendingPhotoID: Int64?
    private var sensorHFOVdeg: Float = 100
    private var poseHistory = CapturePoseHistory()
    private var levelState = CaptureLevelState()
    private var attitudeNeedsTranspose: Bool?
    private var confirmationVisible = false
    private var dwellGate = PanoUltraWideDwellGate()
    private var observers: [NSObjectProtocol] = []
    private var motionWatchdog: Timer?
    private var lastMotionHostTime: TimeInterval = 0

    init(dir: URL, strings: [String: String]) {
        self.dir = dir
        self.strings = strings
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        motionWatchdog?.invalidate()
        motion.stopDeviceMotionUpdates()
    }

    private func s(_ key: String, _ fallback: String) -> String { strings[key] ?? fallback }

    func start() {
        guard !started, !state.ended else { return }
        started = true
        active = true
        haptic.prepare()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] note in
                let detail = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                self?.fail(code: "CAMERA_INTERRUPTED", message: detail ?? "Kamera to'xtatildi. Suratga olishni qayta boshlang.")
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            // Restarting xArbitraryZVertical can reset yaw. Never mix two reference frames.
            self?.fail(code: "CAPTURE_INTERRUPTED", message: "Ilova fonda to'xtatildi. Suratga olishni qayta boshlang.")
        })
        sessionQueue.async { [self] in
            do {
                try configureSession()
                session.startRunning()
                let fov = device?.activeFormat.videoFieldOfView ?? 100
                DispatchQueue.main.async { [self] in
                    guard active else { return }
                    sensorHFOVdeg = fov
                    startMotion()
                }
            } catch {
                DispatchQueue.main.async { self.fail(code: "CAMERA_FAILED", message: error.localizedDescription) }
            }
        }
    }

    func stop() {
        active = false
        ready = false
        motion.stopDeviceMotionUpdates()
        motionWatchdog?.invalidate()
        motionWatchdog = nil
        dwellGate.reset()
        dwellProgress = 0
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
        }
    }

    private func fail(code: String, message: String) {
        guard active, fatalError == nil else { return }
        failureCode = code
        let key: String
        switch code {
        case "CAPTURE_INTERRUPTED", "CAMERA_INTERRUPTED": key = "err_interrupted"
        case "NO_DEVICE_MOTION", "MOTION_FAILED", "MOTION_UNAVAILABLE": key = "err_motion"
        case "CAPTURE_IO": key = "err_storage"
        case "CAMERA_FAILED": key = "err_camera"
        default: key = "err_photo"
        }
        fatalError = s(key, message)
        stop()
        state.reject()
        pendingPhotoID = nil
        isCapturing = false
    }

    private func configureSession() throws {
        guard !configured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) else {
            throw NSError(domain: "PanoCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "0.5× kamera mavjud emas"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw NSError(domain: "PanoCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Kamerani ochib bo'lmadi"])
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        if #available(iOS 16.0, *) {
            if let dims = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
            }) { photoOutput.maxPhotoDimensions = dims }
        } else { photoOutput.isHighResolutionCaptureEnabled = true }
        do {
            try device.lockForConfiguration()
            if device.isGeometricDistortionCorrectionSupported { device.isGeometricDistortionCorrectionEnabled = true }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        } catch { /* Same best-effort device configuration as Astra. */ }
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
            if let c = videoOutput.connection(with: .video) {
                if c.isVideoStabilizationSupported { c.preferredVideoStabilizationMode = .off }
                if c.isCameraIntrinsicMatrixDeliverySupported { c.isCameraIntrinsicMatrixDeliveryEnabled = true }
                if c.isVideoOrientationSupported { c.videoOrientation = .landscapeRight }
            }
        }
        if let c = photoOutput.connection(with: .video), c.isVideoOrientationSupported { c.videoOrientation = .landscapeRight }
        if let c = previewLayer.connection, c.isVideoOrientationSupported { c.videoOrientation = .portrait }
        self.device = device
        configured = true
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { fail(code: "NO_DEVICE_MOTION", message: "Giroskop mavjud emas."); return }
        motion.deviceMotionUpdateInterval = 1 / 60.0
        motion.showsDeviceMovementDisplay = true
        lastMotionHostTime = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        motionWatchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.active else { return }
            if CMClockGetTime(CMClockGetHostTimeClock()).seconds - self.lastMotionHostTime > 3 {
                self.fail(code: "MOTION_UNAVAILABLE", message: "Harakat sensori javob bermayapti.")
            }
        }
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, error in
            guard let self, self.active else { return }
            if let error { self.fail(code: "MOTION_FAILED", message: error.localizedDescription); return }
            guard let dm else { return }
            self.lastMotionHostTime = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            self.ready = true
            self.onMotion(dm)
        }
    }

    private func onMotion(_ dm: CMDeviceMotion) {
        let m = dm.attitude.rotationMatrix
        let attitude = simd_float3x3(rows: [SIMD3(Float(m.m11), Float(m.m12), Float(m.m13)),
                                          SIMD3(Float(m.m21), Float(m.m22), Float(m.m23)),
                                          SIMD3(Float(m.m31), Float(m.m32), Float(m.m33))])
        let gravity = SIMD3<Float>(Float(dm.gravity.x), Float(dm.gravity.y), Float(dm.gravity.z))
        let R = PanoUltraWidePose.rotation(attitude: attitude, gravity: gravity, needsTranspose: &attitudeNeedsTranspose)
        let rate = dm.rotationRate
        let angSpeed = simd_length(SIMD3<Float>(Float(rate.x), Float(rate.y), Float(rate.z)))
        poseHistory.append(time: dm.timestamp, rotation: R, angularSpeed: angSpeed)
        let forward = -SIMD3(R.columns.2.x, R.columns.2.y, R.columns.2.z)   // core −z
        let camRight = SIMD3(R.columns.0.x, R.columns.0.y, R.columns.0.z)
        let camUp = SIMD3(R.columns.1.x, R.columns.1.y, R.columns.1.z)
        let now = dm.timestamp

        let isLevel = levelState.update(forwardY: forward.y, gravityRoll: PanoUltraWidePose.roll(gravity: gravity), maxRoll: PanoUltraWidePose.maxRoll)
        let roll = levelState.previewRoll

        // Focal length in screen px for the portrait HUD projection. The preview is
        // `resizeAspectFill`: the landscape sensor image is rotated to portrait and scaled to the
        // screen HEIGHT, so the screen's vertical extent spans the sensor's horizontal (long-side)
        // field of view; the sides are cropped.
        let size = viewSize
        let fScreen = size.height > 0 ? Float(size.height) / 2 / tan(sensorHFOVdeg * .pi / 180 / 2) : 0

        var newDots: [Dot] = []
        newDots.reserveCapacity(targets.count)
        var nearest: (id: Int, angle: Float)?
        for t in targets {
            let dir = t.direction
            let cosA = simd_dot(dir, forward)
            let ang = acos(max(-1, min(1, cosA)))
            let fwd = cosA
            var pt = CGPoint(x: -1000, y: -1000)
            if fwd > 0.15, fScreen > 0 {
                // The preview renders the landscape sensor buffer rotated upright (connection
                // .portrait), so the sensor's image-right axis runs DOWN the screen and its
                // image-up axis runs to the RIGHT: screen x ← camera up, screen y ← camera right.
                let rx = simd_dot(dir, camRight)
                let uy = simd_dot(dir, camUp)
                let sx = CGFloat(Float(size.width) / 2 + uy / fwd * fScreen)
                let sy = CGFloat(Float(size.height) / 2 + rx / fwd * fScreen)
                pt = CGPoint(x: sx, y: sy)
            }
            let isCap = state.captured.contains(t.id)
            newDots.append(Dot(id: t.id, point: pt, visible: fwd > 0.15, captured: isCap, angle: ang, isNext: false))
            if !isCap, nearest == nil || ang < nearest!.angle { nearest = (t.id, ang) }
        }
        if let n = nearest, let i = newDots.firstIndex(where: { $0.id == n.id }) { newDots[i].isNext = true }

        // Chevron toward the next target, in the same (preview) space as the dots: screen x is the
        // camera's up axis, screen y its right axis. Works even when the target is behind the phone.
        var chevron: Double?
        if let n = nearest, n.angle > 9 * .pi / 180 {
            let dir = targets[n.id].direction
            let rx = simd_dot(dir, camRight)
            let uy = simd_dot(dir, camUp)
            if abs(rx) > 1e-6 || abs(uy) > 1e-6 { chevron = Double(atan2(rx, uy)) }
        }

        let dwell = dwellGate.update(targetID: nearest?.id, angle: nearest?.angle ?? 999,
                                     angularSpeed: angSpeed, levelOK: isLevel,
                                     enabled: ready && !isCapturing && active && !confirmationVisible, time: now)
        if dwell >= 1, let target = nearest { fire(targetId: target.id) }
        dots = newDots
        nearestAngle = nearest?.angle ?? 999
        dwellProgress = dwell
        levelOK = isLevel
        rollRadians = Double(roll)
        chevronAngle = chevron
        if !isLevel { message = s("uw_level", "Telefonni tik tuting") }
        else if message == s("uw_level", "Telefonni tik tuting") { message = "" }
    }

    private func fire(targetId: Int) {
        guard state.reserve(targetId: targetId) != nil else { return }
        isCapturing = true
        canUndo = false
        message = ""
        // Capture settings and capturePhoto must stay on the session queue.
        sessionQueue.async { [self] in
            let settings = photoOutput.availablePhotoCodecTypes.contains(.hevc)
                ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            if #available(iOS 16.0, *) { settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions }
            else { settings.isHighResolutionPhotoEnabled = true }
            DispatchQueue.main.async { [self] in
                guard active, state.pending?.targetId == targetId else { return }
                pendingPhotoID = settings.uniqueID
                sessionQueue.async { [self] in
                    guard session.isRunning else {
                        DispatchQueue.main.async {
                            self.fail(code: "CAMERA_INTERRUPTED", message: "Kamera to'xtatildi.")
                        }
                        return
                    }
                    photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let hostTime = session.synchronizationClock.map {
            CMSyncConvertTime(photo.timestamp, from: $0, to: CMClockGetHostTimeClock()).seconds
        }
        DispatchQueue.main.async { [self] in processPhoto(photo, hostTime: hostTime, error: error) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async { [self] in
            guard pendingPhotoID == resolvedSettings.uniqueID, active else { return }
            rejectPhoto(s("uw_retry", error.localizedDescription))
        }
    }

    private func rejectPhoto(_ error: String) {
        state.reject()
        pendingPhotoID = nil
        isCapturing = false
        canUndo = !state.metas.isEmpty
        dwellGate.reset()
        dwellProgress = 0
        message = error
    }

    private func processPhoto(_ photo: AVCapturePhoto, hostTime: TimeInterval?, error: Error?) {
        guard active, let shot = state.pending, photo.resolvedSettings.uniqueID == pendingPhotoID,
              let target = targets.first(where: { $0.id == shot.targetId }) else { return }
        if let error { rejectPhoto(s("uw_retry", error.localizedDescription)); return }
        guard let time = hostTime, let rotation = PanoUltraWidePose.atExposure(time: time, history: poseHistory, target: target) else {
            rejectPhoto(s("uw_retry", "Telefonni qimirlatmay nishonda qayta ushlab turing.")); return
        }
        // Consume the delegate latch. A duplicate/late final callback must not reject
        // this accepted exposure while its serialized disk transaction is in progress.
        pendingPhotoID = nil
        let calibration = videoQueue.sync { sensorIntrinsics }
        let fov = sensorHFOVdeg
        let previous = state.metas
        ioQueue.async { [self] in
            do {
                guard let data = photo.fileDataRepresentation(), let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(src, 0, nil), image.width >= image.height else {
                    throw NSError(domain: "PanoCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Foto piksel yo'nalishini o'qib bo'lmadi"])
                }
                let w = image.width, h = image.height
                let intrinsics: [Float]
                if let calibration {
                    guard let converted = calibration.forPhoto(width: w, height: h) else {
                        throw NSError(domain: "PanoCapture", code: 6, userInfo: [NSLocalizedDescriptionKey: "Foto kalibrovkasi o'lchamlarga mos emas"])
                    }
                    intrinsics = converted
                } else {
                    let fx = Float(w) / 2 / tan(fov * .pi / 180 / 2)
                    intrinsics = [fx, fx, Float(w) / 2, Float(h) / 2]
                }
                let meta = PanoUltraWidePose.metadata(shot: shot, target: target, rotation: rotation,
                                                     intrinsics: intrinsics, width: w, height: h, timestamp: time)
                try PanoUltraWideFiles.save(image: image, meta: meta, previous: previous, dir: dir)
                let thumb = UIImage(cgImage: image, scale: 1, orientation: .right)
                DispatchQueue.main.async { [self] in
                    guard active, state.accept(meta) else { return }
                    pendingPhotoID = nil
                    isCapturing = false
                    capturedCount = state.metas.count
                    canUndo = true
                    lastThumb = thumb
                    if capturedCount == 1 { sessionQueue.async { self.lockCameraSettings() } }
                    haptic.impactOccurred()
                }
            } catch {
                DispatchQueue.main.async { self.fail(code: "CAPTURE_IO", message: error.localizedDescription) }
            }
        }
    }

    func setConfirmationVisible(_ visible: Bool) {
        confirmationVisible = visible
        dwellGate.reset()
        dwellProgress = 0
    }

    func undoLast() {
        guard active, !isCapturing, !state.metas.isEmpty else { return }
        isCapturing = true
        canUndo = false
        let metas = state.metas
        ioQueue.async { [self] in
            do {
                try PanoUltraWideFiles.undo(metas: metas, dir: dir)
                DispatchQueue.main.async { [self] in
                    guard active else { return }
                    state.undo()
                    capturedCount = state.metas.count
                    canUndo = capturedCount > 0
                    lastThumb = nil
                    isCapturing = false
                    dwellGate.reset()
                    haptic.impactOccurred()
                }
            } catch { DispatchQueue.main.async { self.fail(code: "CAPTURE_IO", message: error.localizedDescription) } }
        }
    }

    func finish(confirmedEarly: Bool = false, completion: (Int) -> Void) {
        guard active, !isCapturing, let count = state.finish(confirmedEarly: confirmedEarly) else { return }
        stop()
        completion(count)
    }

    func cancel(completion: @escaping () -> Void) {
        guard !state.ended else { return }
        state.cancel()
        stop()
        // Serial with any in-flight photo write, so it cannot recreate a cancelled directory.
        ioQueue.async { [self] in
            try? FileManager.default.removeItem(at: dir)
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// After the first frame the scene is framed and metered: freeze exposure, white balance and
    /// focus for the rest of the capture. Auto mode re-meters every shot, and the measured spread
    /// across a room is ~30 % in brightness — which the blender turns into visible bands — while
    /// autofocus hunting both softens frames and changes the focal length (focus breathing), so the
    /// recorded intrinsics would stop matching the image.
    private func lockCameraSettings() {
        guard !settingsLocked, let device else { return }
        settingsLocked = true
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.unlockForConfiguration()
        } catch {
            settingsLocked = false
        }
    }

    // MARK: intrinsics

    /// Reads each camera intrinsic matrix attachment; focus changes can alter the calibration.
    /// The values describe the *current* format
    /// including geometric distortion correction, which the field-of-view figure does not.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer),
              let att = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                        attachmentModeOut: nil) as? Data,
              att.count >= MemoryLayout<matrix_float3x3>.size else { return }
        let m = att.withUnsafeBytes { $0.loadUnaligned(as: matrix_float3x3.self) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        guard m.columns.0.x > 1, w > 0, h > 0 else { return }
        sensorIntrinsics = CaptureIntrinsics(fx: m.columns.0.x, fy: m.columns.1.y,
                                             cx: m.columns.2.x, cy: m.columns.2.y, width: w, height: h)
    }

}

/// Kadastr presentation/storage contract; no Astra SessionStore or standalone navigation.
@available(iOS 15.4, *)
final class PanoUltraWideCaptureCoordinator {
    static let shared = PanoUltraWideCaptureCoordinator()
    private var pending: FlutterResult?
    private var host: UIViewController?
    private var finishing = false

    func start(from presenter: UIViewController, strings: [String: String], result: @escaping FlutterResult) {
        guard pending == nil, presenter.presentedViewController == nil else {
            result(FlutterError(code: "BUSY", message: "Kamera ekrani allaqachon ochiq", details: nil)); return
        }
        let capability = PanoUltraWideCapability.current()
        guard capability.available else {
            result(FlutterError(code: capability.reason ?? "UNSUPPORTED", message: "Ultra-keng suratga olish mavjud emas",
                                details: capability.channelValue)); return
        }
        pending = result
        if capability.cameraAuthorization == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self, weak presenter] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted, let presenter else {
                        self.finish(with: FlutterError(code: "CAMERA_PERMISSION", message: "Kameraga ruxsat berilmadi", details: nil)); return
                    }
                    self.present(from: presenter, strings: strings)
                }
            }
        } else { present(from: presenter, strings: strings) }
    }

    private func present(from presenter: UIViewController, strings: [String: String]) {
        guard presenter.presentedViewController == nil else {
            finish(with: FlutterError(code: "BUSY", message: "Kamera band", details: nil)); return
        }
        let dir = PanoCaptureCoordinator.panoRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try PanoUltraWideFiles.writeMetas([], dir: dir)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            finish(with: FlutterError(code: "IO", message: error.localizedDescription, details: nil)); return
        }
        let view = PanoUltraWideCaptureView(dir: dir, strings: strings,
            onFinish: { [weak self] count in self?.finish(with: ["dir": dir.path, "frames": count]) },
            onCancel: { [weak self] in self?.finish(with: nil) },
            onError: { [weak self] code, message in
                self?.finish(with: FlutterError(code: code, message: message, details: nil))
            })
        let controller = PanoUltraWideHostingController(rootView: view)
        controller.modalPresentationStyle = .fullScreen
        controller.isModalInPresentation = true
        host = controller
        presenter.present(controller, animated: true)
    }

    private func finish(with value: Any?) {
        guard let callback = pending, !finishing else { return }
        finishing = true
        let complete = { [self] in
            host = nil
            pending = nil
            finishing = false
            callback(value)
        }
        if let host { host.dismiss(animated: true, completion: complete) }
        else { complete() }
    }
}

@available(iOS 15.4, *)
private final class PanoUltraWideHostingController: UIHostingController<PanoUltraWideCaptureView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
}
