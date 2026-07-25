import UIKit

/// PCScanKit ("#2") va Runner o'rtasidagi dlopen chegarasi uchun UMUMIY @objc protokol.
///
/// Runner PCScanKit'ni import/link QILMAYDI (Runner iOS 15, kit iOS 17). Kit ish
/// vaqtida `Bundle.load()` bilan yuklanadi; `PCScanEntry` shu protokolga muvofiq
/// bo'lgani uchun Runner uni `as? PCScanFacade` bilan cast qilib, escaping
/// completion block'lar va Bool/массив qaytaruvchi metodlarni to'g'ridan chaqira
/// oladi — `perform(NSSelectorFromString:)` bularni eplay olmaydi (blok/qiymat
/// o'tkazolmaydi).
///
/// ⚠️ Bu fayl IKKALA target'ga ham kiritiladi (Runner + PCScanKit). ObjC runtime
/// protokolni NOMI bo'yicha ro'yxatga oladi, shuning uchun ikki modulda bir xil
/// nomli protokol bitta runtime-protokol sifatida ishlaydi — kit `PCScanEntry`
/// unga muvofiqligini e'lon qiladi, Runner esa `as? PCScanFacade` bilan tekshiradi.
@objc public protocol PCScanFacade {
    /// Skanni FAQAT capture rejimida ochadi (viewer/processing'ga o'tmaydi) va
    /// tugagach yoki bekor qilinganda `onFinished` chaqiradi. Muvaffaqiyatda
    /// `saved_raw` map, bekor/xatoda `nil` — `RoomScanBridge.startCapture` ga mos.
    func presentCapture(from presenter: UIViewController,
                        onFinished: @escaping ([String: Any]?) -> Void)

    /// Saqlangan xom skanni (id) headless teksturalaydi → asosiy model yo'li.
    func processScan(_ savedScanId: Int,
                     completion: @escaping ([String: Any]?, NSError?) -> Void)

    /// Skanning yuklanadigan artefaktlarini backend-tiplari bilan sanaydi:
    /// `[{path, rel, type, sizeBytes}]` (kamida `glb`(+`usdz`)).
    func listScanFiles(_ savedScanId: Int) -> [[String: Any]]

    /// Ishlab chiqilgan model (OBJ/GLB) uchun viewer ochadi.
    func presentViewer(from presenter: UIViewController, path: String)

    /// Barcha PCScan skanlar — "Skanlarim" ro'yxati uchun (scanMap massivi).
    func listScans() -> [[String: Any]]

    /// Bitta skan xulosasi (scanMap) yoki nil.
    func scanSummary(_ savedScanId: Int) -> [String: Any]?

    /// Skanni butunlay o'chiradi.
    func deleteScan(_ savedScanId: Int) -> Bool

    /// Skanning chiqish modellarini (glb/usdz) o'chiradi.
    func deleteOutput(_ savedScanId: Int) -> Bool

    /// Skanning asosiy model faylining yo'li (agar mavjud bo'lsa).
    func outputPath(_ savedScanId: Int) -> String?
}
