import Foundation
import RoomPlan

/// Ilovaning yuqori darajadagi bosqichlari (M0–M3 oqimi).
enum AppPhase: Equatable {
    case onboarding
    case library
    case scanning
    case processing
    case viewer
}

/// Skanerlash natijasida yig'ilgan artefaktlar (bir sessiya bo'yicha).
struct ScanArtifacts {
    /// RoomPlan yakuniy strukturaviy modeli.
    var capturedRoom: CapturedRoom
    /// Object Capture uchun yig'ilgan RGB kadrlar papkasi.
    var imagesFolder: URL
    /// Object Capture natijasi (teksturali USDZ). Muvaffaqiyatsiz bo'lsa nil.
    var texturedModelURL: URL?
    /// Fayl tizimidagi sessiya yo'llari.
    var paths: ScanPaths
}

/// Butun ilova oqimini boshqaruvchi markaziy holat.
@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .onboarding
    @Published var artifacts: ScanArtifacts?

    let permissions = PermissionsService()
    let library = ScanLibrary()

    /// KADASTR-LOCAL (re-sync'da SAQLANADI): AI Baholash "capture-only" hook.
    /// O'rnatilgan bo'lsa, xom skan saqlangach `scanningFinished` viewer'ga
    /// O'TMASDAN shu closure'ni chaqiradi (Flutter modal'iga qaytadi).
    /// `PCScanEntry+Kadastr.presentCapture` o'rnatadi. Qarang: PoissonService gate'lari
    /// kabi mahalliy moslashtirish — upstream sync ustiga yozmasin.
    var captureOnlyCompletion: ((ScanRecord) -> Void)?

    /// KADASTR-LOCAL: capture-only rejimda BEKOR yo'li (X tugmasi olib tashlangani
    /// uchun). Masalan kamera ruxsati rad etilsa Flutter modal'iga `nil` bilan qaytadi.
    /// `presentCapture` `{ finish(nil) }` ga bog'laydi.
    var captureCancelled: (() -> Void)?

    /// Qayta ishlanayotgan mavjud skan papkasi (bo'lsa — yangi yozuv yaratilmaydi).
    private var reprocessingFolder: String?

    // MARK: - Bosqichlararo o'tishlar

    func beginScanning() {
        artifacts = nil
        phase = .scanning
    }

    /// Skanerlash tugadi: RoomPlan modeli + kadrlar papkasi tayyor.
    func scanningFinished(room: CapturedRoom, imagesFolder: URL, paths: ScanPaths) {
        let arts = ScanArtifacts(
            capturedRoom: room,
            imagesFolder: imagesFolder,
            texturedModelURL: nil,
            paths: paths
        )
        artifacts = arts
        // Xom skanni DARHOL ro'yxatga saqlaymiz — OG'IR qayta ishlashdan OLDIN.
        // Shunda qayta ishlash paytida ilova crash bo'lsa ham skan ro'yxatда
        // qoladi va keyin qayta ishlash mumkin (ma'lumot yo'qolmaydi).
        let saved = library.save(artifacts: arts)
        // KADASTR-LOCAL: capture-only rejimda (AI Baholash) viewer'ga O'TMAYMIZ —
        // xom skan saqlangach modal Flutter'ga qaytadi.
        if let completion = captureOnlyCompletion {
            completion(saved)
            return
        }
        // Avtomatik qayta ishlash YO'Q — foydalanuvchi "Natijani ishlash"
        // tugmasini bosgandan keyin boshlanadi (viewer'da xom ko'rinish ko'rsatiladi).
        phase = .viewer
    }

    /// Object Capture tugadi (yoki o'tkazib yuborildi): saqlaymiz va viewer'ga o'tamiz.
    func processingFinished(texturedModelURL: URL?) {
        artifacts?.texturedModelURL = texturedModelURL
        if let artifacts {
            if let folder = reprocessingFolder {
                library.updateAfterReprocess(folderName: folder, artifacts: artifacts)
            } else {
                library.save(artifacts: artifacts)
            }
        }
        reprocessingFolder = nil
        phase = .viewer
    }

    // MARK: - Qayta ishlash (qayta skan qilmasdan)

    /// Hozir ko'rilayotgan skanni saqlangan kadrlardan qayta ishlaydi.
    func reprocessCurrent() {
        guard let artifacts else { return }
        reprocessingFolder = artifacts.paths.folderName
        phase = .processing
    }

    /// Ro'yxatdagi saqlangan skanni qayta ishlaydi.
    func reprocess(_ record: ScanRecord) {
        guard let loaded = library.loadArtifacts(record) else { return }
        artifacts = loaded
        reprocessingFolder = record.folderName
        phase = .processing
    }

    func startNewScan() {
        artifacts = nil
        phase = .scanning
    }

    func backToOnboarding() {
        artifacts = nil
        phase = .onboarding
    }

    // MARK: - Kutubxona

    func openLibrary() {
        library.reload()
        phase = .library
    }

    /// Saqlangan skanni ochadi.
    func openSaved(_ record: ScanRecord) {
        guard let loaded = library.loadArtifacts(record) else { return }
        artifacts = loaded
        phase = .viewer
    }
}
