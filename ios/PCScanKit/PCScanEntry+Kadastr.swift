import UIKit

/// `PCScanEntry`'ning Kadastr AI Baholash uchun natija-qaytaruvchi yuzasi
/// (`PCScanFacade` muvofiqligi). Runner PCScanKit'ni link qilmagani uchun bu
/// kit-ichidagi conformance dlopen'dan keyin `as? PCScanFacade` bilan topiladi.
///
/// P0: BO'SH stub'lar — xatti-harakat P1+ da to'ldiriladi (P1 presentCapture,
/// P2 processScan, P3 GLB, P4 USDZ, P5 listScanFiles/viewer, P7 list/delete).
/// Provider-flag hozir `.roomScan` bo'lgani uchun bular hali chaqirilmaydi;
/// baribir xavfsiz (crash'siz) qiymat qaytaradi.
extension PCScanEntry: PCScanFacade {
    public func presentCapture(from presenter: UIViewController,
                               onFinished: @escaping ([String: Any]?) -> Void) {
        // TODO(P1): capture-only oqim + guard'langan completion.
        onFinished(nil)
    }

    public func processScan(_ savedScanId: Int,
                            completion: @escaping ([String: Any]?, NSError?) -> Void) {
        // TODO(P2): headless texturing → GLB path.
        completion(nil, NSError(domain: "PCScanKit", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "processScan not implemented (P2)"]))
    }

    public func listScanFiles(_ savedScanId: Int) -> [[String: Any]] { [] }   // TODO(P5)

    public func presentViewer(from presenter: UIViewController, path: String) {}  // TODO(P5)

    public func availableScanIds() -> [NSNumber] { [] }   // TODO(P7)

    public func deleteScan(_ savedScanId: Int) -> Bool { false }   // TODO(P7)

    public func outputPath(_ savedScanId: Int) -> String? { nil }   // TODO(P7)
}
