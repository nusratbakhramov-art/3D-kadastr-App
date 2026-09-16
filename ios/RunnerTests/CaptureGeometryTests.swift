import Foundation
import XCTest
import simd
@testable import Runner

final class CaptureGeometryTests: XCTestCase {
    // Existing ARKit meta.json schema: no poseSource or exposureDuration.
    private let legacyJSON = """
    [{"index":0,"targetId":3,"targetYaw":1.5707964,"targetPitch":0,
      "transform":[1,0,0,0,0,1,0,0,0,0,1,0,0.1,0.2,0.3,1],
      "intrinsics":[2800,2801,2016,1512],"imageWidth":4032,"imageHeight":3024,
      "pixelWidth":4032,"pixelHeight":3024,"timestamp":1234.5,
      "highRes":true,"file":"frame_0.jpg"}]
    """

    func testLegacyARKitMetadataDecodesAndReencodesWithoutNewKeys() throws {
        let data = Data(legacyJSON.utf8)
        let frames = try JSONDecoder().decode([PanoFrameMeta].self, from: data)
        let frame = try XCTUnwrap(frames.first)
        XCTAssertEqual(frames.count, 1)
        XCTAssertNil(frame.poseSource)
        XCTAssertNil(frame.exposureDuration)
        XCTAssertEqual(frame.transform.count, 16)
        XCTAssertEqual(frame.intrinsics, [2800, 2801, 2016, 1512])
        let encoded = try JSONEncoder().encode(frames)
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSArray)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSArray)
        XCTAssertEqual(after, before) // Every legacy field and value survives.
    }

    func testLegacyMemberwiseInitializerStillOmitsOptionalMetadata() throws {
        // Same argument list used by the unchanged ARKit capture controller.
        let frame = PanoFrameMeta(
            index: 0, targetId: 0, targetYaw: 0, targetPitch: 0,
            transform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            intrinsics: [2800, 2800, 2016, 1512], imageWidth: 4032, imageHeight: 3024,
            pixelWidth: 4032, pixelHeight: 3024, timestamp: 1,
            highRes: true, file: "frame_0.jpg"
        )
        let data = try JSONEncoder().encode(frame)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["poseSource"])
        XCTAssertNil(json["exposureDuration"])
    }

    func testAstraMetadataRoundTripsPoseSourceAndExposureDuration() throws {
        var frame = try XCTUnwrap(
            JSONDecoder().decode([PanoFrameMeta].self, from: Data(legacyJSON.utf8)).first
        )
        frame.poseSource = "sensors:coremotion"
        frame.exposureDuration = 1.0 / 120.0
        let data = try JSONEncoder().encode(frame)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["poseSource"] as? String, "sensors:coremotion")
        XCTAssertEqual(json["exposureDuration"] as? Double, 1.0 / 120.0)
        let decoded = try JSONDecoder().decode(PanoFrameMeta.self, from: data)
        XCTAssertEqual(decoded.poseSource, frame.poseSource)
        XCTAssertEqual(decoded.exposureDuration, frame.exposureDuration)
        XCTAssertEqual(decoded.transform, frame.transform)
        XCTAssertEqual(decoded.intrinsics, frame.intrinsics)
        XCTAssertEqual(decoded.timestamp, frame.timestamp)
        XCTAssertEqual(decoded.file, frame.file)
    }

    func testOptionalMetadataDecodesIndependentlyAndAcceptsExplicitNulls() throws {
        let legacy = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: Data(legacyJSON.utf8)) as? [[String: Any]])?.first
        )
        for source in [nil, "arkit", "sensors:coremotion"] as [String?] {
            for exposure in [nil, 0.01] as [Double?] {
                var json = legacy
                json["poseSource"] = source.map { $0 as Any } ?? NSNull()
                json["exposureDuration"] = exposure.map { $0 as Any } ?? NSNull()
                let data = try JSONSerialization.data(withJSONObject: json)
                let frame = try JSONDecoder().decode(PanoFrameMeta.self, from: data)
                XCTAssertEqual(frame.poseSource, source)
                XCTAssertEqual(frame.exposureDuration, exposure)
            }
        }
    }

    func testRequiredLegacyMetadataStillFailsWhenMissing() throws {
        var json = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: Data(legacyJSON.utf8)) as? [[String: Any]])?.first
        )
        json.removeValue(forKey: "transform")
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try JSONDecoder().decode(PanoFrameMeta.self, from: data))
    }

    func testUltraWideGridHasSeventeenRequiredUniqueTargetsWithAstraAngles() {
        let targets = PanoTargetGrid.ultraWide17()
        XCTAssertEqual(targets.count, 17)
        XCTAssertEqual(targets.map(\.id), Array(0..<17))
        XCTAssertTrue(targets.allSatisfy { !$0.optional })
        XCTAssertEqual(Set(targets.map(\.direction)).count, 17)
        let expected: [(Float, Float)] = [
            (0, 0), (45, 0), (90, 0), (135, 0), (180, 0), (225, 0), (270, 0), (315, 0),
            (45, 52), (135, 52), (225, 52), (315, 52),
            (45, -52), (135, -52), (225, -52), (315, -52), (0, 89),
        ]
        for (target, (yaw, pitch)) in zip(targets, expected) {
            XCTAssertEqual(target.yaw, yaw * .pi / 180, accuracy: 0.00001)
            XCTAssertEqual(target.pitch, pitch * .pi / 180, accuracy: 0.00001)
            XCTAssertEqual(simd_length(target.direction), 1, accuracy: 0.00001)
        }
        XCTAssertGreaterThan(targets[16].direction.y, 0.99)
    }

    func testDefaultARKitGridRemainsTwentyEightRequiredAndOptionalZenith() {
        let targets = PanoTargetGrid.build()
        XCTAssertEqual(targets.count, 29)
        XCTAssertEqual(targets.map(\.id), Array(0..<29))
        XCTAssertEqual(targets.filter { !$0.optional }.count, 28)
        let expected: [(Float, Float)] = [
            (0, 0), (30, 0), (60, 0), (90, 0), (120, 0), (150, 0),
            (180, 0), (210, 0), (240, 0), (270, 0), (300, 0), (330, 0),
            (22.5, 45), (67.5, 45), (112.5, 45), (157.5, 45),
            (202.5, 45), (247.5, 45), (292.5, 45), (337.5, 45),
            (22.5, -45), (67.5, -45), (112.5, -45), (157.5, -45),
            (202.5, -45), (247.5, -45), (292.5, -45), (337.5, -45), (0, 89),
        ]
        for (target, (yaw, pitch)) in zip(targets, expected) {
            XCTAssertEqual(target.yaw, yaw * .pi / 180, accuracy: 0.00001)
            XCTAssertEqual(target.pitch, pitch * .pi / 180, accuracy: 0.00001)
            XCTAssertEqual(target.optional, target.id == 28)
        }
    }

    func testTargetDirectionsUseNegativeZForwardAndPositivePitchUp() {
        let horizon = PanoTargetGrid.ultraWide17()
        assertVector(horizon[0].direction, [0, 0, -1])
        assertVector(horizon[2].direction, [1, 0, 0])
        assertVector(horizon[4].direction, [0, 0, 1])
        assertVector(horizon[6].direction, [-1, 0, 0])
        XCTAssertGreaterThan(horizon[8].direction.y, 0)
        XCTAssertLessThan(horizon[12].direction.y, 0)
    }

    func testExposurePoseInterpolatesAtPhotoTimeInsteadOfDeliveryTime() throws {
        var history = CapturePoseHistory()
        for i in 0...120 {
            let time = Double(i) / 60
            history.append(time: time, rotation: yaw(Float(time) * .pi / 6))
        }
        let actual = try XCTUnwrap(history.rotation(at: 1.125))
        assertRotation(actual, yaw(1.125 * .pi / 6))
        // Zero shutter lag may select an exposure from before the request.
        assertRotation(try XCTUnwrap(history.rotation(at: 0.5)), yaw(.pi / 12))
    }

    func testPoseInterpolationTakesShortestPathAcrossAngleWrap() throws {
        var history = CapturePoseHistory()
        history.append(time: 1, rotation: yaw(179 * .pi / 180))
        history.append(time: 1.02, rotation: yaw(-179 * .pi / 180))
        assertRotation(try XCTUnwrap(history.rotation(at: 1.01)), yaw(.pi))
    }

    func testMissingStaleOrInvalidPhotoTimeIsRejected() {
        var history = CapturePoseHistory()
        XCTAssertNil(history.rotation(at: 1))
        history.append(time: 1, rotation: matrix_identity_float3x3)
        history.append(time: 2, rotation: matrix_identity_float3x3)
        XCTAssertNil(history.rotation(at: 0.9))
        XCTAssertNil(history.rotation(at: 1.5)) // Motion updates stalled inside the history.
        XCTAssertNil(history.rotation(at: 2.1))
        XCTAssertNil(history.rotation(at: .nan))
        XCTAssertNil(history.rotation(at: .infinity))
    }

    func testNearbyEndpointPoseIsAllowedWithinTolerance() throws {
        var history = CapturePoseHistory()
        history.append(time: 1, rotation: yaw(0.2))
        history.append(time: 1.02, rotation: yaw(0.4))
        assertRotation(try XCTUnwrap(history.rotation(at: 0.98)), yaw(0.2))
        assertRotation(try XCTUnwrap(history.rotation(at: 1.04)), yaw(0.4))
        XCTAssertNil(history.rotation(at: 0.98, tolerance: 0.01))
        XCTAssertNil(history.rotation(at: 1.04, tolerance: 0.01))
    }

    func testPoseHistoryIgnoresInvalidDuplicateAndOutOfOrderSamples() throws {
        var history = CapturePoseHistory()
        history.append(time: 1, rotation: yaw(0.2))
        for time in [Double.nan, .infinity, 0.5, 1] {
            history.append(time: time, rotation: yaw(2))
        }
        history.append(time: 1.02, rotation: yaw(0.4))
        assertRotation(try XCTUnwrap(history.rotation(at: 1)), yaw(0.2))
        assertRotation(try XCTUnwrap(history.rotation(at: 1.01)), yaw(0.3))
    }

    func testPoseHistoryRetainsOnlyTenSeconds() {
        var history = CapturePoseHistory()
        for time in [0.0, 1, 11] {
            history.append(time: time, rotation: matrix_identity_float3x3)
        }
        XCTAssertNil(history.rotation(at: 0))
        XCTAssertNotNil(history.rotation(at: 1)) // Exact retention boundary.
        XCTAssertNotNil(history.rotation(at: 11))
    }

    func testMotionDuringExposureIsRejectedEvenWhenTriggerWasStable() {
        var history = CapturePoseHistory()
        history.append(time: 1, rotation: matrix_identity_float3x3, angularSpeed: 0.01)
        history.append(time: 1.016, rotation: matrix_identity_float3x3, angularSpeed: 0.4)
        XCTAssertNotNil(history.rotation(at: 1, maxAngularSpeed: 0.14))
        XCTAssertNil(history.rotation(at: 1.008, maxAngularSpeed: 0.14))
        XCTAssertNil(history.rotation(at: 1.016, maxAngularSpeed: 0.14))
        history.append(time: 1.032, rotation: matrix_identity_float3x3, angularSpeed: 0.01)
        XCTAssertNil(history.rotation(at: 1.024, maxAngularSpeed: 0.14))
    }

    func testVideoCentreCropDoesNotStretchFocalLength() throws {
        let video = CaptureIntrinsics(fx: 800, fy: 800, cx: 960, cy: 540, width: 1920, height: 1080)
        let k = try XCTUnwrap(video.forPhoto(width: 4032, height: 3024))
        for (actual, expected) in zip(k, [Float(1680), 1680, 2016, 1512]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
    }

    func testCropConversionKeepsOffCentrePrincipalPoint() throws {
        let video = CaptureIntrinsics(fx: 800, fy: 810, cx: 950, cy: 530, width: 1920, height: 1080)
        let k = try XCTUnwrap(video.forPhoto(width: 4032, height: 3024))
        for (actual, expected) in zip(k, [Float(1680), 1701, 1995, 1491]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
    }

    func testFullSensorScalingKeepsOffCentrePrincipalPoint() throws {
        let video = CaptureIntrinsics(fx: 400, fy: 401, cx: 500, cy: 380, width: 1008, height: 756)
        XCTAssertEqual(try XCTUnwrap(video.forPhoto(width: 4032, height: 3024)), [1600, 1604, 2000, 1520])
        XCTAssertNil(video.forPhoto(width: 1920, height: 1080)) // Unexpected narrower still crop.
    }

    func testIntrinsicsRejectInvalidDimensionsAndCalibration() {
        let valid = CaptureIntrinsics(fx: 800, fy: 800, cx: 960, cy: 540, width: 1920, height: 1080)
        XCTAssertNil(valid.forPhoto(width: 0, height: 3024))
        XCTAssertNil(valid.forPhoto(width: 4032, height: -1))
        let invalid = [
            CaptureIntrinsics(fx: 800, fy: 800, cx: 960, cy: 540, width: 0, height: 1080),
            CaptureIntrinsics(fx: 800, fy: 800, cx: 960, cy: 540, width: 1920, height: -1),
            CaptureIntrinsics(fx: 0, fy: 800, cx: 960, cy: 540, width: 1920, height: 1080),
            CaptureIntrinsics(fx: 800, fy: -1, cx: 960, cy: 540, width: 1920, height: 1080),
            CaptureIntrinsics(fx: .nan, fy: 800, cx: 960, cy: 540, width: 1920, height: 1080),
            CaptureIntrinsics(fx: 800, fy: .infinity, cx: 960, cy: 540, width: 1920, height: 1080),
            CaptureIntrinsics(fx: 800, fy: 800, cx: .nan, cy: 540, width: 1920, height: 1080),
            CaptureIntrinsics(fx: 800, fy: 800, cx: 960, cy: .infinity, width: 1920, height: 1080),
        ]
        for intrinsics in invalid {
            XCTAssertNil(intrinsics.forPhoto(width: 4032, height: 3024))
        }
    }

    func testBothPolesIgnoreUndefinedRollAndKeepPreviewStable() {
        for forwardY: Float in [-0.999, 0.999] {
            var level = CaptureLevelState()
            XCTAssertTrue(level.update(forwardY: 0.8, gravityRoll: 0.04, maxRoll: 0.2))
            for roll: Float in [-3.1, 2.9, -1.5, 0.7] {
                XCTAssertTrue(level.update(forwardY: forwardY, gravityRoll: roll, maxRoll: 0.2))
                XCTAssertEqual(level.previewRoll, 0.04)
            }
            XCTAssertFalse(level.update(forwardY: 0, gravityRoll: 0.5, maxRoll: 0.2))
            XCTAssertEqual(level.previewRoll, 0.5)
        }
    }

    func testRollThresholdAndPoleBoundary() {
        var level = CaptureLevelState()
        XCTAssertEqual(level.previewRoll, 0)
        for roll: Float in [-0.19, 0.19] {
            XCTAssertTrue(level.update(forwardY: 0, gravityRoll: roll, maxRoll: 0.2))
            XCTAssertEqual(level.previewRoll, roll)
        }
        for forwardY: Float in [-0.9, 0.9] {
            for roll: Float in [-0.2, 0.2] {
                XCTAssertFalse(level.update(forwardY: forwardY, gravityRoll: roll, maxRoll: 0.2))
            }
        }
        XCTAssertTrue(level.update(forwardY: 0.91, gravityRoll: 3, maxRoll: 0.2))
        XCTAssertEqual(level.previewRoll, 0.2)
    }

    private func yaw(_ angle: Float) -> simd_float3x3 {
        simd_float3x3(simd_quatf(angle: angle, axis: [0, 1, 0]))
    }

    private func assertRotation(_ actual: simd_float3x3, _ expected: simd_float3x3,
                                file: StaticString = #filePath, line: UInt = #line) {
        for column in 0..<3 {
            assertVector(actual[column], expected[column], file: file, line: line)
        }
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_length(actual - expected), 0.00001, file: file, line: line)
    }
}
