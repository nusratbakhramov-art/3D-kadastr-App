import AVFoundation
import Flutter
import ImageIO
import UIKit
import XCTest
import simd
@testable import Runner

final class PanoUltraWideCaptureTests: XCTestCase {
    private let upright = PanoUltraWidePose.sensorToDevice

    private func meta(_ shot: PanoUltraWideCaptureState.Shot) -> PanoFrameMeta {
        let target = PanoTargetGrid.ultraWide17().first { $0.id == shot.targetId }!
        return PanoUltraWidePose.metadata(shot: shot, target: target, rotation: upright,
                                          intrinsics: [240, 241, 160, 120], width: 320, height: 240, timestamp: 12.5)
    }

    private func accept(_ target: Int, into state: inout PanoUltraWideCaptureState) throws {
        let shot = try XCTUnwrap(state.reserve(targetId: target))
        XCTAssertTrue(state.accept(meta(shot)))
    }

    func testDefaultAndExplicitModeSelectionRejectsInvalidModes() {
        XCTAssertEqual(PanoCaptureMode.resolve(nil), .arkit)
        XCTAssertEqual(PanoCaptureMode.resolve("arkit"), .arkit)
        XCTAssertEqual(PanoCaptureMode.resolve("ultrawide"), .ultrawide)
        XCTAssertNil(PanoCaptureMode.resolve("auto"))
        XCTAssertNil(PanoCaptureMode.resolve(17))
    }

    @MainActor
    func testSimulatorRoutesExplicitUltraWideToControlledError() {
        #if targetEnvironment(simulator)
        var responses = 0
        PanoCaptureMode.ultrawide.start(from: UIViewController(), strings: [:]) { value in
            responses += 1
            XCTAssertEqual((value as? FlutterError)?.code, "NO_ULTRAWIDE_CAMERA")
        }
        XCTAssertEqual(responses, 1)
        PanoCaptureMode.resolve(nil)?.start(from: UIViewController(), strings: [:]) { value in
            XCTAssertEqual((value as? FlutterError)?.code, "UNSUPPORTED") // ARKit, not UW capability
        }
        #endif
    }

    func testCapabilitySeparatesHardwareMotionOSAndAuthorization() {
        let cases: [(Bool, Bool, Bool, AVAuthorizationStatus, String?)] = [
            (false, true, true, .authorized, "UNSUPPORTED_IOS"),
            (true, false, true, .authorized, "NO_ULTRAWIDE_CAMERA"),
            (true, true, false, .authorized, "NO_DEVICE_MOTION"),
            (true, true, true, .denied, "CAMERA_PERMISSION"),
            (true, true, true, .restricted, "CAMERA_PERMISSION"),
            (true, true, true, .notDetermined, nil),
            (true, true, true, .authorized, nil),
        ]
        for (os, camera, motion, authorization, reason) in cases {
            let capability = PanoUltraWideCapability(supportedOS: os, hasCamera: camera,
                                                     hasMotion: motion, authorization: authorization)
            XCTAssertEqual(capability.reason, reason)
            XCTAssertEqual(capability.available, reason == nil)
            XCTAssertEqual(capability.channelValue["available"] as? Bool, reason == nil)
        }
    }

    func testSensorMetadataUsesActualDimensionsZeroTranslationAndAcquisitionIndex() throws {
        let frame = meta(.init(index: 2, targetId: 16))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any])
        XCTAssertEqual(frame.index, 2)
        XCTAssertEqual(frame.targetId, 16)
        XCTAssertEqual(frame.targetPitch, 89 * .pi / 180, accuracy: 0.0001)
        XCTAssertEqual(frame.poseSource, "sensors:coremotion")
        XCTAssertEqual(Array(frame.transform[12...15]), [0, 0, 0, 1])
        XCTAssertEqual(frame.transform.count, 16)
        XCTAssertEqual(frame.intrinsics, [240, 241, 160, 120])
        XCTAssertEqual(frame.imageWidth, frame.pixelWidth)
        XCTAssertEqual(frame.imageHeight, frame.pixelHeight)
        XCTAssertEqual(frame.timestamp, 12.5)
        XCTAssertEqual(frame.file, "frame_2.jpg")
        XCTAssertTrue(frame.highRes)
        XCTAssertNil(json["exposureDuration"]) // Astra leaves duration absent.
        XCTAssertEqual(json["poseSource"] as? String, "sensors:coremotion")
    }

    func testARKitFallbackRequiresTrackingAndRequestableCameraPermission() {
        for authorization: AVAuthorizationStatus in [.authorized, .notDetermined, .denied, .restricted] {
            XCTAssertFalse(PanoCaptureCoordinator.canCapture(trackingSupported: false, authorization: authorization))
            XCTAssertEqual(PanoCaptureCoordinator.canCapture(trackingSupported: true, authorization: authorization),
                           authorization == .authorized || authorization == .notDetermined)
        }
    }

    func testSeventeenRequiredTargetsCompleteOnlyAfterZenithInAcquisitionOrder() throws {
        var state = PanoUltraWideCaptureState()
        XCTAssertEqual(state.targets.count, 17)
        XCTAssertTrue(state.targets.allSatisfy { !$0.optional })
        let order = [7, 2, 12, 4, 9, 0, 15, 6, 10, 13, 1, 14, 3, 11, 5, 8]
        for id in order { try accept(id, into: &state) }
        XCTAssertFalse(state.complete)
        XCTAssertNil(state.finish(confirmedEarly: false))
        try accept(16, into: &state)
        XCTAssertTrue(state.complete)
        XCTAssertEqual(state.metas.map(\.index), Array(0..<17))
        XCTAssertEqual(state.metas.map(\.targetId), order + [16])
        XCTAssertEqual(state.finish(confirmedEarly: false), 17)
        XCTAssertNil(state.finish(confirmedEarly: false))
    }

    func testEarlyFinishRequiresFourAcceptedShotsAndConfirmation() throws {
        var state = PanoUltraWideCaptureState()
        for id in 0..<3 { try accept(id, into: &state) }
        XCTAssertNil(state.finish(confirmedEarly: true))
        let pending = try XCTUnwrap(state.reserve(targetId: 9))
        XCTAssertNil(state.finish(confirmedEarly: true))
        XCTAssertTrue(state.accept(meta(pending)))
        XCTAssertNil(state.finish(confirmedEarly: false))
        XCTAssertEqual(state.finish(confirmedEarly: true), 4)
    }

    func testUndoRecapturesLastTargetWithoutConfusingIndexAndID() throws {
        var state = PanoUltraWideCaptureState()
        try accept(16, into: &state)
        try accept(7, into: &state)
        XCTAssertNil(state.reserve(targetId: 16))
        XCTAssertEqual(state.undo()?.targetId, 7)
        XCTAssertEqual(state.captured, [16])
        let recapture = try XCTUnwrap(state.reserve(targetId: 7))
        XCTAssertEqual(recapture.index, 2)
        XCTAssertNil(state.undo()) // in-flight acquisition cannot be undone halfway
        XCTAssertTrue(state.accept(meta(recapture)))
        XCTAssertEqual(state.metas.map(\.targetId), [16, 7])
        XCTAssertEqual(state.metas.map(\.index), [0, 2])
    }

    func testCancelRejectsLatePhotoAndFurtherMutations() throws {
        var state = PanoUltraWideCaptureState()
        let shot = try XCTUnwrap(state.reserve(targetId: 5))
        state.cancel()
        XCTAssertFalse(state.accept(meta(shot)))
        XCTAssertNil(state.reserve(targetId: 5))
        XCTAssertNil(state.undo())
        XCTAssertNil(state.finish(confirmedEarly: true))
        XCTAssertTrue(state.metas.isEmpty)
    }

    func testRejectedPhotoDoesNotMarkTargetCaptured() throws {
        var state = PanoUltraWideCaptureState()
        let old = try XCTUnwrap(state.reserve(targetId: 8))
        XCTAssertNil(state.reserve(targetId: 9))
        state.reject()
        let next = try XCTUnwrap(state.reserve(targetId: 8))
        XCTAssertFalse(state.accept(meta(old)))
        XCTAssertTrue(state.accept(meta(next)))
        XCTAssertEqual(state.captured, [8])
    }

    func testAttitudeConversionHandlesBothDirectionsAndKeepsCoreConvention() {
        let a = PanoUltraWidePose.referenceToWorld.transpose
        var direct: Bool?
        var inverse: Bool?
        let gravity = SIMD3<Float>(0, -1, 0)
        let r = PanoUltraWidePose.rotation(attitude: a, gravity: gravity, needsTranspose: &direct)
        let rt = PanoUltraWidePose.rotation(attitude: a.transpose, gravity: gravity, needsTranspose: &inverse)
        XCTAssertEqual(direct, false)
        XCTAssertEqual(inverse, true)
        for column in 0..<3 { XCTAssertLessThan(simd_length(r[column] - rt[column]), 0.00001) }
        XCTAssertEqual(-r.columns.2, SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(r.transpose * SIMD3<Float>(0, 1, 0), SIMD3<Float>(-1, 0, 0))
        XCTAssertEqual(PanoUltraWidePose.roll(gravity: gravity), 0, accuracy: 0.00001)
    }

    func testExposureUsesHistoricalPoseEvenIfPhoneMovedAfterShutter() throws {
        var history = CapturePoseHistory()
        history.append(time: 10, rotation: upright)
        history.append(time: 10.02, rotation: upright)
        let turned = simd_float3x3(simd_quatf(angle: 30 * .pi / 180, axis: [0, 1, 0])) * upright
        history.append(time: 10.04, rotation: turned, angularSpeed: 1)
        let target = PanoTargetGrid.ultraWide17()[0]
        let exposure = try XCTUnwrap(PanoUltraWidePose.atExposure(time: 10.01, history: history, target: target))
        XCTAssertLessThan(simd_length(exposure.columns.2 - upright.columns.2), 0.00001)
        XCTAssertNil(PanoUltraWidePose.atExposure(time: 10.04, history: history, target: target))
        XCTAssertNil(PanoUltraWidePose.atExposure(time: 11, history: history, target: target))
        XCTAssertNil(PanoUltraWidePose.atExposure(time: 10, history: CapturePoseHistory(), target: target))
    }

    func testPhotoTimeAimRollAndPoleValidation() {
        func accepted(yaw: Float = 0, pitch: Float = 0, roll: Float = 0, speed: Float = 0, targetID: Int = 0) -> Bool {
            let rotation = simd_float3x3(simd_quatf(angle: yaw * .pi / 180, axis: [0, 1, 0])) *
                simd_float3x3(simd_quatf(angle: pitch * .pi / 180, axis: [1, 0, 0])) * upright *
                simd_float3x3(simd_quatf(angle: roll * .pi / 180, axis: [0, 0, 1]))
            var history = CapturePoseHistory()
            history.append(time: 10, rotation: rotation, angularSpeed: speed * .pi / 180)
            return PanoUltraWidePose.atExposure(time: 10, history: history, target: PanoTargetGrid.ultraWide17()[targetID]) != nil
        }
        XCTAssertTrue(accepted(yaw: 5, roll: 11, speed: 7))
        XCTAssertFalse(accepted(yaw: 7))
        XCTAssertFalse(accepted(roll: 13))
        XCTAssertFalse(accepted(speed: 9))
        XCTAssertTrue(accepted(pitch: 89, roll: 70, targetID: 16))
        XCTAssertFalse(accepted(pitch: 89, roll: 70, speed: 9, targetID: 16))
    }

    func testDwellRequiresContinuousStableAimAndResetsOnPauseOrTargetChange() {
        var gate = PanoUltraWideDwellGate()
        func update(_ time: Double, target: Int = 0, angle: Float = 0, speed: Float = 0,
                    level: Bool = true, enabled: Bool = true) -> Double {
            gate.update(targetID: target, angle: angle * .pi / 180, angularSpeed: speed * .pi / 180,
                        levelOK: level, enabled: enabled, time: time)
        }
        XCTAssertEqual(update(0), 0)
        for time in [0.05, 0.1, 0.15, 0.2, 0.25, 0.3] { XCTAssertLessThan(update(time), 1) }
        XCTAssertEqual(update(0.36), 1)
        XCTAssertEqual(update(0.4, speed: 8), 0)
        XCTAssertEqual(update(0.45), 0)
        XCTAssertEqual(update(0.5, angle: 6), 0)
        XCTAssertEqual(update(0.55), 0)
        XCTAssertEqual(update(0.6, level: false), 0)
        XCTAssertEqual(update(0.65), 0)
        XCTAssertEqual(update(0.7, enabled: false), 0)
        XCTAssertEqual(update(0.75), 0)
        XCTAssertEqual(update(0.8, target: 1), 0)
        XCTAssertEqual(update(2, target: 1), 0) // motion delivery stalled
    }

    @MainActor
    func testJPEGMetadataPersistenceAndUndoKeepLandscapePixelsAndOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 240))
            UIColor.blue.setFill(); context.fill(CGRect(x: 160, y: 0, width: 160, height: 240))
        }
        let cg = try XCTUnwrap(image.cgImage)
        let first = meta(.init(index: 0, targetId: 16))
        let second = meta(.init(index: 1, targetId: 7))
        try PanoUltraWideFiles.save(image: cg, meta: first, previous: [], dir: dir)
        try PanoUltraWideFiles.save(image: cg, meta: second, previous: [first], dir: dir)
        let bytes = try Data(contentsOf: dir.appendingPathComponent(first.file))
        XCTAssertEqual(Array(bytes.prefix(2)), [0xff, 0xd8])
        let src = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 320)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 240)
        // ImageIO may omit the identity EXIF tag; decoded pixels must still be upright.
        XCTAssertEqual((props[kCGImagePropertyOrientation] as? Int) ?? 1, 1)
        XCTAssertEqual(UIImage(data: bytes)?.imageOrientation, .up)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8,
                                            bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.draw(decoded, in: CGRect(x: 0, y: 0, width: 320, height: 240))
        let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        let left = (120 * 320 + 80) * 4, right = (120 * 320 + 240) * 4
        XCTAssertGreaterThan(pixels[left], 200) // red stays left, blue stays right
        XCTAssertLessThan(pixels[left + 2], 30)
        XCTAssertGreaterThan(pixels[right + 2], 200)
        XCTAssertLessThan(pixels[right], 30)
        func load() throws -> [PanoFrameMeta] {
            try JSONDecoder().decode([PanoFrameMeta].self, from: Data(contentsOf: dir.appendingPathComponent("meta.json")))
        }
        XCTAssertEqual(try load().map(\.targetId), [16, 7])
        try PanoUltraWideFiles.undo(metas: [first, second], dir: dir)
        XCTAssertEqual(try load().map(\.targetId), [16])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(second.file).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(first.file).path))
    }

    @MainActor
    func testFailedMetadataCommitRemovesUnacceptedJPEG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("meta.json"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { $0.fill(CGRect(x: 0, y: 0, width: 32, height: 24)) }
        let frame = meta(.init(index: 0, targetId: 1))
        XCTAssertThrowsError(try PanoUltraWideFiles.save(image: XCTUnwrap(image.cgImage), meta: frame, previous: [], dir: dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(frame.file).path))
    }
}
