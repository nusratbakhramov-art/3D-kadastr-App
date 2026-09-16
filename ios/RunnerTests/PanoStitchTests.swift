import Flutter
import UIKit
import XCTest
@testable import Runner

final class PanoStitchTests: XCTestCase {
    func testLegacyMetadataKeepsARKitDefaultsRegardlessOfFrameCount() throws {
        for count in [4, 17, 28, 29] {
            for source in [nil, "arkit", "sensors:unknown", "sensors:coremotion:unknown"] as [String?] {
                let metas = try metadata(count: count, poseSource: source)
                let options = PanoStitchCoordinator.ProcessingOptions(metas: metas, physicalMemory: 4_000_000_000)
                XCTAssertFalse(options.sensorPoses)
                XCTAssertFalse(options.highQuality)
                XCTAssertEqual(options.width, 4096)
                XCTAssertEqual(options.mode, "fast")
            }
        }
    }

    func testLegacyModeKeepsRAMThresholdAndExplicitOverrides() throws {
        let metas = try metadata()
        for (mode, memory, expected) in [
            ("auto", UInt64(5_499_999_999), "fast"),
            ("auto", UInt64(5_500_000_000), "mvs"),
            ("mvs", UInt64(4_000_000_000), "mvs"),
            ("fast", UInt64(8_000_000_000), "fast"),
        ] {
            let options = PanoStitchCoordinator.ProcessingOptions(metas: metas, mode: mode, physicalMemory: memory)
            XCTAssertEqual(options.mode, expected)
            XCTAssertFalse(options.sensorPoses)
            XCTAssertFalse(options.highQuality)
        }
    }

    func testCoreMotionSelectsSensorHighQualityPipelineRegardlessOfCountRAMOrRequestedMode() throws {
        for count in [4, 17, 28] {
            for mode in ["auto", "fast", "mvs"] {
                let metas = try metadata(count: count, poseSource: "sensors:coremotion")
                let options = PanoStitchCoordinator.ProcessingOptions(metas: metas, mode: mode,
                                                                     physicalMemory: 4_000_000_000)
                XCTAssertTrue(options.sensorPoses)
                XCTAssertTrue(options.highQuality)
                XCTAssertEqual(options.width, 6144)
                XCTAssertEqual(options.mode, "mvs")
            }
        }
        let mixed = try metadata() + metadata(poseSource: "sensors:coremotion")
        XCTAssertTrue(PanoStitchCoordinator.ProcessingOptions(metas: mixed).sensorPoses)
    }

    func testExplicitWidthOverridesAndInvalidWidthsUseMetadataDefaults() throws {
        for source in [nil, "sensors:coremotion"] as [String?] {
            let metas = try metadata(poseSource: source)
            for width in [1024, 6144] {
                XCTAssertEqual(PanoStitchCoordinator.ProcessingOptions(metas: metas, width: width).width, width)
            }
            for width in [0, -1] {
                XCTAssertEqual(PanoStitchCoordinator.ProcessingOptions(metas: metas, width: width).width,
                               source == nil ? 4096 : 6144)
            }
        }
    }

    @MainActor
    func testLegacyDefaultOutputRemains4096() async throws {
        let dir = try captureDirectory(textured: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let response = try await stitch(dir: dir, mode: "fast", width: nil)
        XCTAssertEqual(response["mode"] as? String, "fast")
        XCTAssertEqual(response["width"] as? Int, 4096)
        XCTAssertEqual(response["height"] as? Int, 2048)
        let image = try XCTUnwrap(UIImage(contentsOfFile: dir.appendingPathComponent("pano.jpg").path)?.cgImage)
        XCTAssertEqual(image.width, 4096)
        XCTAssertEqual(image.height, 2048)
    }

    @MainActor
    func testOutputPublicationRequiresBothCompleteJPEGsAndPreservesPriorResult() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let work = dir.appendingPathComponent(".stitch-test")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let prior = Data([1, 2, 3])
        let pano = dir.appendingPathComponent("pano.jpg")
        try prior.write(to: pano)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format)
            .image { UIColor.blue.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 1024, height: 512)) }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.85))
        try jpeg.write(to: work.appendingPathComponent("pano.jpg"))
        XCTAssertThrowsError(try PanoStitchCoordinator.publishOutput(from: work, to: dir, width: 1024))
        XCTAssertEqual(try Data(contentsOf: pano), prior)
        try jpeg.dropLast(2).write(to: work.appendingPathComponent("preview.jpg"))
        XCTAssertThrowsError(try PanoStitchCoordinator.publishOutput(from: work, to: dir, width: 1024))
        XCTAssertEqual(try Data(contentsOf: pano), prior)
        try jpeg.write(to: work.appendingPathComponent("preview.jpg"))
        XCTAssertThrowsError(try PanoStitchCoordinator.publishOutput(from: work, to: dir, width: 6144))
        try PanoStitchCoordinator.publishOutput(from: work, to: dir, width: 1024)
        XCTAssertEqual(try Data(contentsOf: pano), jpeg)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("preview.jpg")), jpeg)
    }

    @MainActor
    func testPreviewValidatesPathWithoutDependingOnCaptureHardware() {
        var response: FlutterError?
        PanoTourCoordinator.shared.preview(args: ["path": "/missing/pano.jpg"], from: UIViewController()) {
            response = $0 as? FlutterError
        }
        XCTAssertEqual(response?.code, "ARGS")
    }

    @MainActor
    func testCoreMotionDefaultOutputAndRotationFallbackThroughSavedMetadata() async throws {
        // Textureless input cannot support image-based translation or depth.
        let dir = try captureDirectory(poseSource: "sensors:coremotion", textured: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let metaURL = dir.appendingPathComponent("meta.json")
        let originalMetadata = try Data(contentsOf: metaURL)
        var messages: [String] = []
        let messenger = RecordingMessenger { messages.append($0) }
        let response = try await stitch(dir: dir, mode: "fast", width: nil, messenger: messenger)
        XCTAssertEqual(Set(response.keys), Set([
            "pano", "preview", "width", "height", "frames", "coverage", "seconds", "mode",
            "baSeconds", "mvsSeconds", "stitchSeconds",
        ]))
        XCTAssertEqual(response["mode"] as? String, "mvs") // Selected pipeline; it may fall back.
        XCTAssertEqual(response["width"] as? Int, 6144)
        XCTAssertEqual(response["height"] as? Int, 3072)
        XCTAssertGreaterThan(try XCTUnwrap(response["baSeconds"] as? Double), 0)
        XCTAssertEqual(response["mvsSeconds"] as? Double, 0)
        XCTAssertTrue(messages.contains("Chuqurlik uchun moslik kam: rotatsiya bilan tikish"))
        for (key, width, height) in [("pano", 6144, 3072), ("preview", 1024, 512)] {
            let path = try XCTUnwrap(response[key] as? String)
            XCTAssertEqual(path, dir.appendingPathComponent("\(key).jpg").path)
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            XCTAssertEqual(image.width, width)
            XCTAssertEqual(image.height, height)
        }
        XCTAssertEqual(try Data(contentsOf: metaURL), originalMetadata)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("frame_0.jpg").path))
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    @MainActor
    func testLegacyDirectoryProcessesAndKeepsFlutterOutputContract() async throws {
        let dir = try captureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let originalMetadata = try Data(contentsOf: dir.appendingPathComponent("meta.json"))
        // Resume directories can contain an entry whose image was removed by undo.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("frame_4.jpg"))
        let response = try await stitch(dir: dir, mode: "fast")
        XCTAssertEqual(Set(response.keys), Set([
            "pano", "preview", "width", "height", "frames", "coverage", "seconds", "mode",
            "baSeconds", "mvsSeconds", "stitchSeconds",
        ]))
        XCTAssertEqual(response["mode"] as? String, "fast")
        XCTAssertEqual(response["frames"] as? Int, 4)
        XCTAssertEqual(response["width"] as? Int, 1024)
        XCTAssertEqual(response["height"] as? Int, 512)
        for key in ["pano", "preview"] {
            let path = try XCTUnwrap(response[key] as? String)
            XCTAssertEqual(path, dir.appendingPathComponent("\(key).jpg").path)
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            XCTAssertEqual(image.width, 1024)
            XCTAssertEqual(image.height, 512)
        }
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("meta.json")), originalMetadata)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("frame_0.jpg").path))
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    @MainActor
    func testExistingKadastrNadirLogoIsLoadedAndStamped() async throws {
        let asset = "assets/branding/nadir_logo.png"
        let key = FlutterDartProject.lookupKey(forAsset: asset)
        let logoPath = try XCTUnwrap(Bundle.main.path(forResource: key, ofType: nil))
        let logo = try Data(contentsOf: URL(fileURLWithPath: logoPath))
        XCTAssertEqual(String(data: logo[12..<16], encoding: .ascii), "IHDR")
        let dir = try captureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = try await stitch(dir: dir, mode: "fast")
        let plainPath = try XCTUnwrap(plain["pano"] as? String)
        let before = try XCTUnwrap(UIImage(contentsOfFile: plainPath)?.cgImage)
        let bottom = CGRect(x: 0, y: 464, width: 1024, height: 48)
        let upper = CGRect(x: 0, y: 0, width: 1024, height: 256)
        // Decode before the next run overwrites pano.jpg; ImageIO can defer reads.
        let originalBottom = try pixels(before, rect: bottom)
        let originalUpper = try pixels(before, rect: upper)
        let branded = try await stitch(dir: dir, mode: "fast", logoAsset: asset)
        let brandedPath = try XCTUnwrap(branded["pano"] as? String)
        let after = try XCTUnwrap(UIImage(contentsOfFile: brandedPath)?.cgImage)
        XCTAssertNotEqual(originalBottom, try pixels(after, rect: bottom))
        XCTAssertEqual(originalUpper, try pixels(after, rect: upper))
    }

    @MainActor
    func testLegacyDirectoryStillProcessesInMeasuredPoseMVSMode() async throws {
        let dir = try captureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let response = try await stitch(dir: dir, mode: "mvs")
        XCTAssertEqual(response["mode"] as? String, "mvs")
        XCTAssertEqual(response["frames"] as? Int, 5)
        XCTAssertEqual(response["width"] as? Int, 1024)
        XCTAssertEqual(response["height"] as? Int, 512)
        XCTAssertGreaterThan(try XCTUnwrap(response["mvsSeconds"] as? Double), 0)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    @MainActor
    private func captureDirectory(poseSource: String? = nil, textured: Bool = true) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format).image { context in
            UIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            for y in stride(from: 0, to: 240, by: 20) where textured {
                for x in stride(from: 0, to: 320, by: 20) where (x + y) % 40 == 0 {
                    UIColor.white.setFill()
                    context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        for index in 0..<5 {
            let filename = "frame_\(index).jpg"
            try jpeg.write(to: dir.appendingPathComponent(filename))
        }
        try JSONEncoder().encode(metadata(count: 5, poseSource: poseSource))
            .write(to: dir.appendingPathComponent("meta.json"))
        return dir
    }

    private func metadata(count: Int = 1, poseSource: String? = nil) throws -> [PanoFrameMeta] {
        let rows: [[String: Any]] = (0..<count).map { index in
            var row: [String: Any] = [
                "index": index, "targetId": index, "targetYaw": 0, "targetPitch": 0,
                "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                "intrinsics": [240, 240, 160, 120], "imageWidth": 320, "imageHeight": 240,
                "pixelWidth": 320, "pixelHeight": 240, "timestamp": Double(index),
                "highRes": false, "file": "frame_\(index).jpg",
            ]
            if let poseSource { row["poseSource"] = poseSource }
            return row
        }
        // Legacy rows intentionally omit poseSource and exposureDuration.
        return try JSONDecoder().decode([PanoFrameMeta].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    @MainActor
    private func stitch(dir: URL, mode: String, width: Int? = 1024, logoAsset: String? = nil,
                        messenger: RecordingMessenger = RecordingMessenger()) async throws -> [String: Any] {
        let completed = expectation(description: "Native stitching completes")
        let channel = FlutterMethodChannel(name: "kadastr/pano_capture", binaryMessenger: messenger)
        var args: [String: Any] = ["dir": dir.path, "mode": mode]
        if let width { args["width"] = width }
        if let logoAsset { args["logoAsset"] = logoAsset }
        var output: Any?
        PanoStitchCoordinator.shared.stitch(args: args, channel: channel) { value in
            output = value
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 120)
        XCTAssertFalse(output is FlutterError, "\(String(describing: output))")
        return try XCTUnwrap(output as? [String: Any])
    }

    private func pixels(_ image: CGImage, rect: CGRect) throws -> Data {
        let cropped = try XCTUnwrap(image.cropping(to: rect))
        return try XCTUnwrap(UIImage(cgImage: cropped).pngData())
    }
}

// Allows the deterministic C++ image fixture to exercise the production Swift
// metadata adapter as well as the native core. This driver is test-target only.
@objcMembers public final class PanoStitchTestDriver: NSObject {
    public static func stitchDirectory(_ directory: String, width: Int, completion: @escaping (NSDictionary) -> Void) {
        DispatchQueue.main.async {
            let channel = FlutterMethodChannel(name: "kadastr/pano_capture", binaryMessenger: RecordingMessenger())
            PanoStitchCoordinator.shared.stitch(args: ["dir": directory, "width": width, "mode": "fast"],
                                               channel: channel) { value in
                completion(value as? NSDictionary ?? ["error": String(describing: value)])
            }
        }
    }
}

private final class RecordingMessenger: NSObject, FlutterBinaryMessenger {
    private let progress: (String) -> Void
    init(progress: @escaping (String) -> Void = { _ in }) { self.progress = progress }
    func send(onChannel channel: String, message: Data?) {
        guard let message else { return }
        let call = FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message)
        if call.method == "progress", let args = call.arguments as? [String: Any], let msg = args["msg"] as? String {
            progress(msg)
        }
    }
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        send(onChannel: channel, message: message)
        callback?(nil)
    }
    func setMessageHandlerOnChannel(_ channel: String,
                                   binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
        1
    }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
