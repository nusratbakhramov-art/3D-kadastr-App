import Foundation
import RoomPlan

/// M2 — Object Capture jarayonini boshqaruvchi ViewModel.
@MainActor
final class ReconstructionViewModel: ObservableObject {

    enum Stage: Equatable {
        case preparing
        case reconstructing
        case done
        case skipped(reason: String)
        case failed(reason: String)
    }

    @Published private(set) var stage: Stage = .preparing
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = "Tayyorlanmoqda…"

    private let service = PhotogrammetryService()

    /// Teksturalash. Asosiy yo'l: on-device depth fusion (TSDF).
    /// Depth ma'lumoti bo'lmasa (eski skan) — Object Capture zaxirasi.
    func run(paths: ScanPaths, room: CapturedRoom) async -> URL? {
        let log = DebugLog(url: paths.debugLog)
        let hasDepth = (try? FileManager.default.contentsOfDirectory(atPath: paths.depthFolder.path))?
            .contains { $0.hasPrefix("depth_") } ?? false

        if hasDepth {
            // 0. Pozalarni aniqlashtirish (point-to-plane ICP → yakuniy ARKit mesh).
            //    frames.json jonli (drift bilan) pozalarini yakuniy xaritaga
            //    tekislaydi — texrecon, depth-gate, carver va ekspozitsiya
            //    BARI muvofiq ma'lumot bilan ishlaydi (Polycam pose-optimization
            //    bosqichiga ekvivalent).
            stage = .reconstructing
            statusText = "Pozalar aniqlashtirilmoqda…"
            await Task.detached(priority: .userInitiated) {
                PoseRefiner.refineOnDisk(paths: paths) { log.log($0) }
                // Zich kesh pozalari ham (bo'lsa) — TSDF muvofiq ma'lumot olsin.
                PoseRefiner.refineDenseOnDisk(paths: paths) { log.log($0) }
            }.value

            // Asosiy: ARKit real-time mesh + texrecon (sanoat teksturasi, on-device).
            if let url = await runFusionTexRecon(paths: paths, room: room, log: log) {
                return url
            }
            // Zaxira 1: fusion'ning o'z rangli meshi.
            if let url = await runFusion(paths: paths, log: log) {
                return url
            }
            // Zaxira 2: Apple photogrammetriyasi.
            return await runFullRoomOC(paths: paths, log: log)
        }
        return await runObjectCapture(paths: paths, log: log)
    }

    /// ARKit mesh (tozalangan) + texrecon (graph-cut + seam leveling + atlas) → teksturali OBJ.
    private func runFusionTexRecon(paths: ScanPaths, room: CapturedRoom, log: DebugLog) async -> URL? {
        stage = .reconstructing
        statusText = "Xona tayyorlanmoqda…"
        let started = Date()
        log.log("TEXRECON START")
        do {
            // Texrecon — mesh tozalash + sanoat teksturasi (bitta detached task).
            let objURL = try await Task.detached(priority: .userInitiated) {
                try TexReconService.run(paths: paths, room: room) { fraction, text in
                    Task { @MainActor in
                        self.progress = fraction
                        self.statusText = text
                    }
                }
            }.value
            progress = 1
            stage = .done
            statusText = "Tayyor"
            log.log(String(format: "TEXRECON DONE dur=%.1fs -> %@",
                           Date().timeIntervalSince(started), objURL.lastPathComponent))
            return objURL
        } catch {
            log.log("TEXRECON ERROR \(error.localizedDescription) — zaxiraga o'tildi")
            return nil
        }
    }

    /// Apple PhotogrammetrySession + LiDAR depth sample'lar + masking o'chirilgan.
    private func runFullRoomOC(paths: ScanPaths, log: DebugLog) async -> URL? {
        stage = .reconstructing
        statusText = "To'liq xona qurilmoqda… (bir necha daqiqa)"
        let started = Date()
        log.log("FULLROOM-OC START (depth samples, masking off)")
        do {
            let url = try await service.reconstructFullRoom(paths: paths) { [weak self] fraction in
                Task { @MainActor in
                    self?.progress = fraction
                    self?.statusText = String(format: "To'liq xona qurilmoqda… %d%%", Int(fraction * 100))
                }
            }
            progress = 1
            stage = .done
            statusText = "Tayyor"
            log.log(String(format: "FULLROOM-OC DONE dur=%.1fs", Date().timeIntervalSince(started)))
            return url
        } catch {
            log.log("FULLROOM-OC ERROR \(error.localizedDescription) — fusion zaxiraga o'tildi")
            return nil
        }
    }

    /// On-device TSDF fusion — to'liq rangli xona meshi.
    private func runFusion(paths: ScanPaths, log: DebugLog) async -> URL? {
        stage = .reconstructing
        statusText = "Xona birlashtirilmoqda…"
        let started = Date()
        log.log("FUSION START")
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try FusionEngine.run(paths: paths) { fraction, text in
                    Task { @MainActor in
                        self.progress = fraction
                        self.statusText = text
                    }
                }
            }.value
            progress = 1
            stage = .done
            statusText = "Tayyor"
            log.log(String(format: "FUSION DONE dur=%.1fs %@", Date().timeIntervalSince(started), result.stats))
            return result.meshURL
        } catch {
            stage = .skipped(reason: error.localizedDescription)
            statusText = error.localizedDescription
            log.log("FUSION ERROR \(error.localizedDescription)")
            return nil
        }
    }

    /// Object Capture (fotogrammetriya) zaxirasi — eski skanlar uchun.
    private func runObjectCapture(paths: ScanPaths, log: DebugLog) async -> URL? {
        stage = .reconstructing
        statusText = "Real tekstura hisoblanmoqda… (bu bir necha daqiqa olishi mumkin)"
        let started = Date()
        log.log("OBJECTCAPTURE START detail=reduced featureSensitivity=high")

        do {
            let url = try await service.reconstruct(
                imagesFolder: paths.imagesFolder,
                outputURL: paths.modelURL,
                detail: .reduced,
                progress: { [weak self] fraction in
                    Task { @MainActor in self?.progress = fraction }
                }
            )
            progress = 1
            stage = .done
            statusText = "Tayyor"
            log.log(String(format: "OBJECTCAPTURE DONE dur=%.1fs -> %@",
                           Date().timeIntervalSince(started), url.lastPathComponent))
            return url
        } catch let error as PhotogrammetryService.ServiceError {
            stage = .skipped(reason: error.localizedDescription)
            statusText = error.localizedDescription
            log.log("OBJECTCAPTURE SKIPPED \(error.localizedDescription)")
            return nil
        } catch is CancellationError {
            stage = .failed(reason: "Bekor qilindi")
            log.log("OBJECTCAPTURE CANCELLED")
            return nil
        } catch {
            stage = .skipped(reason: error.localizedDescription)
            statusText = error.localizedDescription
            log.log("OBJECTCAPTURE ERROR \(error.localizedDescription)")
            return nil
        }
    }
}
