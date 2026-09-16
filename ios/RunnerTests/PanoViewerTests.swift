import SceneKit
import SwiftUI
import UIKit
import XCTest
@testable import Runner

@available(iOS 16.0, *)
final class PanoViewerTests: XCTestCase {
    @MainActor
    func testLocalFileThenDeletedFileFallsBackToEncodedRemoteURLAndCache() async throws {
        let dir = try makeCapture()
        let path = dir.appendingPathComponent("pano.jpg").path
        let url = "https://pano-viewer.invalid/\(UUID().uuidString)/room%20one.jpg?signature=a%2Bb&part=1"
        ViewerImageURLProtocol.jpeg = try Data(contentsOf: URL(fileURLWithPath: path))
        URLProtocol.registerClass(ViewerImageURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(ViewerImageURLProtocol.self)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: PanoImageLoader.cachedFile(for: url))
        }
        // Local-only viewing does not require a URL or upload.
        let local = try await PanoImageLoader.load(path: path, url: nil)
        XCTAssertEqual(local.size.width, 64)
        try FileManager.default.removeItem(at: dir)
        let remote = try await PanoImageLoader.load(path: path, url: url)
        XCTAssertEqual(remote.size, local.size)
        XCTAssertEqual(ViewerImageURLProtocol.lastURL?.absoluteString, url)
        // Reopening after cleanup uses the persistent viewer cache too.
        ViewerImageURLProtocol.status = 500
        defer { ViewerImageURLProtocol.status = 200 }
        let cached = try await PanoImageLoader.load(path: path, url: url)
        XCTAssertEqual(cached.size, local.size)
    }

    func testStorageKeyAndDeletedPathAreNotTreatedAsRemoteURLs() async throws {
        for value in ["listings/media/room.jpg", "/deleted/capture/pano.jpg", "file:///deleted/pano.jpg"] {
            do {
                _ = try await PanoImageLoader.load(path: nil, url: value)
                XCTFail("A storage key/file reference is not an HTTP image source: \(value)")
            } catch PanoImageLoader.LoadError.invalidSource {
                // Expected boundary error; no URLSession request.
            }
        }
        do {
            _ = try await PanoImageLoader.load(path: "/deleted/capture/pano.jpg", url: nil)
            XCTFail("A deleted local panorama must report missing")
        } catch PanoImageLoader.LoadError.missing {}
    }

    @MainActor
    func testMultipleRoomStartKeysSelectTheirOwnTexture() async throws {
        let blue = try makeCapture()
        let green = try makeCapture(color: .green)
        defer {
            try? FileManager.default.removeItem(at: blue)
            try? FileManager.default.removeItem(at: green)
        }
        let rooms = [
            TourRoom(key: "kitchen", name: "Kitchen", url: nil, path: blue.appendingPathComponent("pano.jpg").path),
            TourRoom(key: "living", name: "Living room", url: nil, path: green.appendingPathComponent("pano.jpg").path),
        ]
        for key in ["kitchen", "living"] {
            let host = UIHostingController(rootView: PanoTourView(
                rooms: rooms, links: [:], startKey: key, editable: true,
                strings: [:], onClose: { _, _ in }))
            let window = show(host)
            defer { window.isHidden = true; window.rootViewController = nil }
            let scene = try await sceneView(in: host.view)
            try assertCenterColor(scene.snapshot(), expected: key == "kitchen" ? [0, 0, 255] : [0, 255, 0])
            XCTAssertEqual(host.rootView.rooms.map(\.key), ["kitchen", "living"])
        }
    }

    @MainActor
    func testRemoteLoadNeverPresentsAnUntexturedSphere() async throws {
        try await assertNoEmptySphere(status: 200)
    }

    @MainActor
    func testFailedRemoteLoadDoesNotLeaveAWhiteSphere() async throws {
        try await assertNoEmptySphere(status: 404)
    }

    @MainActor
    private func assertNoEmptySphere(status: Int) async throws {
        let dir = try makeCapture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = "https://pano-viewer.invalid/\(UUID().uuidString)/pano.jpg"
        ViewerImageURLProtocol.jpeg = try Data(contentsOf: dir.appendingPathComponent("pano.jpg"))
        ViewerImageURLProtocol.status = status
        URLProtocol.registerClass(ViewerImageURLProtocol.self)
        defer {
            ViewerImageURLProtocol.status = 200
            URLProtocol.unregisterClass(ViewerImageURLProtocol.self)
            try? FileManager.default.removeItem(at: PanoImageLoader.cachedFile(for: url))
        }
        let host = UIHostingController(rootView: PanoTourView(
            rooms: [TourRoom(key: "room", name: "Kitchen", url: url, path: nil)],
            links: [:], startKey: "room", editable: true, strings: [:], onClose: { _, _ in }))
        let window = show(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(findScene(in: host.view), "Loading must not display an untextured white sphere")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        if status == 200 {
            let scene = try await sceneView(in: host.view)
            XCTAssertNotNil(texture(in: scene))
        } else {
            XCTAssertNil(findScene(in: host.view), "Failed loads must show a readable error, not a white sphere")
        }
    }
    @MainActor
    func testPreviewAcceptDismissThenPresentUploadedTour() async throws {
        let dir = try makeCapture()
        let data = try Data(contentsOf: dir.appendingPathComponent("pano.jpg"))
        let url = "https://pano-viewer.invalid/\(UUID().uuidString)/pano.jpg"
        ViewerImageURLProtocol.jpeg = data
        URLProtocol.registerClass(ViewerImageURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(ViewerImageURLProtocol.self)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: PanoImageLoader.cachedFile(for: url))
        }
        let presenter = UIViewController()
        let window = show(presenter)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 400_000_000)
        var accepted = false
        PanoTourCoordinator.shared.preview(args: ["path": dir.appendingPathComponent("pano.jpg").path], from: presenter) { _ in
            accepted = true
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        let preview = try XCTUnwrap(presenter.presentedViewController as? UIHostingController<PanoPreviewView>)
        preview.rootView.onAccept()
        for _ in 0..<100 {
            if accepted { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(accepted)
        try FileManager.default.removeItem(at: dir)
        PanoTourCoordinator.shared.tour(args: ["panoramas": [["key": "room", "url": url]], "startKey": "room"], from: presenter) { _ in }
        try await Task.sleep(nanoseconds: 500_000_000)
        let tour = try XCTUnwrap(presenter.presentedViewController as? UIHostingController<PanoTourView>)
        let scene = try await sceneView(in: tour.view)
        for _ in 0..<100 {
            if texture(in: scene) != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(texture(in: scene))
        try await Task.sleep(nanoseconds: 500_000_000)
        let onScreen = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try assertBlueCenter(onScreen)
        tour.rootView.onClose([:], nil)
        try await Task.sleep(nanoseconds: 400_000_000)
    }
    @MainActor
    func testLocalPreviewStartsWithTexture() async throws {
        let dir = try makeCapture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let host = UIHostingController(rootView: PanoPreviewView(
            path: dir.appendingPathComponent("pano.jpg").path, strings: [:],
            onAccept: {}, onRetake: {}))
        let window = show(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        let scene = try await sceneView(in: host.view)
        XCTAssertNotNil(texture(in: scene), "The synchronous local preview must have a panorama texture")
        try assertBluePixels(in: scene)
    }

    @MainActor
    func testTourLoadsLocalTextureAfterAsyncStart() async throws {
        let dir = try makeCapture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let room = TourRoom(key: "local:room", name: "Kitchen", url: nil,
                            path: dir.appendingPathComponent("pano.jpg").path)
        try await assertTourTexture(room)
    }

    @MainActor
    func testTourLoadsUploadedTextureAfterLocalCleanup() async throws {
        let dir = try makeCapture()
        let data = try Data(contentsOf: dir.appendingPathComponent("pano.jpg"))
        try FileManager.default.removeItem(at: dir)
        let url = "https://pano-viewer.invalid/\(UUID().uuidString)/pano.jpg?signature=a%2Bb"
        ViewerImageURLProtocol.jpeg = data
        URLProtocol.registerClass(ViewerImageURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(ViewerImageURLProtocol.self)
            try? FileManager.default.removeItem(at: PanoImageLoader.cachedFile(for: url))
        }
        let room = TourRoom(key: "listings/media/room.jpg", name: "Kitchen", url: url, path: nil)
        try await assertTourTexture(room)
    }

    @MainActor
    private func assertTourTexture(_ room: TourRoom) async throws {
        let host = UIHostingController(rootView: PanoTourView(
            rooms: [room], links: [:], startKey: room.key, editable: true,
            strings: [:], onClose: { _, _ in }))
        let window = show(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        let scene = try await sceneView(in: host.view)
        for _ in 0..<100 {
            if texture(in: scene) != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let image = try XCTUnwrap(texture(in: scene), "Tour showed its UI but never attached the loaded panorama to the sphere: \(room)")
        XCTAssertEqual(image.size.width / image.size.height, 2)
        try await Task.sleep(nanoseconds: 500_000_000)
        let onScreen = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try assertBlueCenter(onScreen)
        try assertBluePixels(in: scene)
    }

    @MainActor
    private func assertBluePixels(in scene: SCNView) throws {
        try assertBlueCenter(scene.snapshot())
    }

    private func assertBlueCenter(_ screenshot: UIImage) throws {
        try assertCenterColor(screenshot, expected: [0, 0, 255])
    }

    private func assertCenterColor(_ screenshot: UIImage, expected: [UInt8]) throws {
        let cg = try XCTUnwrap(screenshot.cgImage)
        let center = try XCTUnwrap(cg.cropping(to: CGRect(x: cg.width / 2, y: cg.height / 2, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        for i in 0..<3 {
            XCTAssertLessThan(abs(Int(pixel[i]) - Int(expected[i])), 40,
                              "The sphere must show the loaded texture, not white: \(pixel)")
        }
    }

    @MainActor
    private func show(_ host: UIViewController) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return window
    }

    @MainActor
    private func sceneView(in view: UIView) async throws -> SCNView {
        for _ in 0..<100 {
            if let found = findScene(in: view) { return found }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "PanoViewerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "No SceneKit view"])
    }

    @MainActor
    private func findScene(in view: UIView) -> SCNView? {
        if let scene = view as? SCNView { return scene }
        return view.subviews.compactMap { findScene(in: $0) }.first
    }

    private func texture(in scene: SCNView) -> UIImage? {
        scene.scene?.rootNode.childNode(withName: "sphere", recursively: true)?.geometry?.firstMaterial?.diffuse.contents as? UIImage
    }

    @MainActor
    private func makeCapture(color: UIColor = .blue) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 32), format: format).image {
            color.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: dir.appendingPathComponent("pano.jpg"))
        return dir
    }
}

private final class ViewerImageURLProtocol: URLProtocol {
    static var jpeg = Data()
    static var status = 200
    static var lastURL: URL?
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "pano-viewer.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastURL = request.url
        let status = Self.status
        let data = Self.jpeg
        let work = DispatchWorkItem { [weak self] in self?.respond(status: status, data: data) }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.75, execute: work)
    }
    private func respond(status: Int, data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/jpeg"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { work?.cancel() }
}
