import Foundation

/// Qurilma-adaptiv xotira byudjeti — jetsam (OOM) crash'ini oldini olish uchun.
///
/// Muammo: butun reconstruction pipeline QAT'IY xotira cheklovlari ishlatardi
/// (maxVoxels 20M, Poisson depth 9 ≈ 378MB, texrecon 300 ko'rinish ≈ 2.5-3.5GB,
/// scan encode-backlog cheksiz). Kam xotirali qurilmada (yoki katta xonada) peak
/// jetsam limitidan oshib app JIMGINA o'ldirilardi (Swift `catch` ushlamaydi).
///
/// Yechim: `os_proc_available_memory()` (jetsam'gacha qolgan bayt) o'qib, har
/// bosqich cheklovini qurilma imkoniga moslaymiz — "qurilma ko'targancha ishlaydi,
/// sekin bo'lsa ham, crash bermaydi". Har og'ir bosqich BOSHIDA `current()` chaqiriladi
/// (scan va processing alohida — capture xotirani allaqachon yegan bo'ladi).
enum MemoryBudget {

    /// Bir bosqich uchun hisoblangan cheklovlar.
    struct Caps: Equatable {
        var maxVoxels: Int          // TSDF voxel qopqog'i
        var poissonDepth: Int32     // Poisson oktree chuqurligi (7..9)
        var maxTexViews: Int        // texrecon ko'rinishlari (native peak = asosiy OOM)
        var texImageMaxDim: Int     // kadr kichraytirish o'lchami (1024/2048)
        var maxInFlightFrames: Int  // scan: bir vaqtda ushlab turiladigan pixelBuffer
        var denseEnabled: Bool      // scan: zich depth-kesh yoqilsinmi
        var atlasFloatBudget: Int   // bayt; AtlasSharpen bundan oshsa tile/skip
        /// Native texrecon ~350MB fixed overhead oladi; bundan kam xotira qolsa
        /// (juda band qurilma) YENGIL fallback'ga (FusionEngine, rangli mesh) o'tiladi.
        var canRunNativeTexrecon: Bool
    }

    // MARK: - OS o'qish (iOS jetsam headroom)

    /// Jetsam'gacha qolgan bayt (`os_proc_available_memory`, iOS 13+). 0/mavjud emas
    /// bo'lsa — umumiy RAM'ning ~45% (taxminiy jetsam limiti) zaxira sifatida.
    static func availableBytes() -> UInt64 {
        #if os(iOS)
        let a = os_proc_available_memory()   // <os/proc.h> (bridging header)
        if a > 0 { return UInt64(a) }
        #endif
        return UInt64(Double(ProcessInfo.processInfo.physicalMemory) * 0.45)
    }

    /// Joriy qurilma holati bo'yicha cheklovlar.
    static func current() -> Caps {
        caps(availableBytes: availableBytes(),
             physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    // MARK: - SOF cap-hisoblash (harness'da test qilinadi, OS'ga bog'liq emas)

    /// `A` = jetsam'gacha qolgan bayt, `ram` = umumiy RAM. Determinik, sof funksiya.
    static func caps(availableBytes A: UInt64, physicalMemory ram: UInt64) -> Caps {
        let MB: UInt64 = 1 << 20
        // Jetsam transient RESIDENT spike'da ishlaydi + kompressor kechikadi, shuning
        // uchun A ning HAMMASINI rejalashtirmaymiz. Katta RAM'da margin kattaroq.
        let marginFloor: UInt64 = ram >= 4 * 1024 * MB ? 350 * MB : 250 * MB
        // Byudjet: A ning 60% yoki (A − margin) — kichigi. margin ostida 0 (minimal caps).
        // Bu min(0.6A, A−margin) monoton VA uzluksiz (A=2.5·margin da ikki bo'lak tutashadi);
        // margin ostida 0 — qurilma juda band, faqat pol-caplar (4M voxel, 48 view).
        let B = min(A * 6 / 10, A > marginFloor ? A - marginFloor : 0)
        let bMB = B / MB

        // ── texrecon (ASOSIY OOM manbai): per-view ∝ dim² (kvadratik) ──
        // Konstantalar TAXMINIY (qurilma profilидан) — qurilmada test bilan sozlanadi.
        let texDim = A < 1600 * MB ? 1024 : 2048
        let perViewMB: UInt64 = texDim == 1024 ? 5 : 20
        let fixedNativeMB: UInt64 = 350     // atlaslar + patch-graf + mesh adjacency
        let rawViews = bMB > fixedNativeMB ? Int((bMB - fixedNativeMB) / perViewMB) : 0
        // Pol 48 — minimal-lekin-ishlaydigan qamrov; NO-CRASH ustuvor, shuning uchun
        // 80 emas (80 juda-kam-xotirali qurilmada byudjetdan oshardi). Shift 300.
        let maxTexViews = min(300, max(48, rawViews))

        // ── TSDF voxel: ~15 B/voxel co-resident (tsdf+wsum+cellVertex+rang) ──
        let maxVoxels = min(20_000_000, max(4_000_000, Int(B / 15)))

        // ── Poisson oktree: d7≈54, d8≈143, d9≈378 MB. (B−100MB) ga sig'gan eng balandi ──
        let octreeMB: [Int32: UInt64] = [7: 54, 8: 143, 9: 378]
        var poissonDepth: Int32 = 7
        let poissonBudgetMB = bMB > 100 ? bMB - 100 : 0
        for d: Int32 in [8, 9] where (octreeMB[d] ?? .max) <= poissonBudgetMB { poissonDepth = d }

        // ── Scan: bir vaqtda uchib turgan pixelBuffer (~16MB = 4MB buffer + 11MB JPEG) ──
        let inflight = A > 250 * MB ? Int((A - 250 * MB) / (16 * MB)) : 1
        let maxInFlightFrames = min(24, max(2, inflight))
        // Zich kesh — sifat oshirgich, majburiy emas; kam xotirada o'chiramiz.
        let denseEnabled = A > 400 * MB

        // Native texrecon fixed ~350MB + eng kam 48 ko'rinish. 700MB'dan kam qolsa
        // hatto minimal sozlama ham sig'maydi -> yengil fallback'ga o'tamiz.
        let canRunNativeTexrecon = A > 700 * MB

        return Caps(maxVoxels: maxVoxels, poissonDepth: poissonDepth,
                    maxTexViews: maxTexViews, texImageMaxDim: texDim,
                    maxInFlightFrames: maxInFlightFrames, denseEnabled: denseEnabled,
                    atlasFloatBudget: Int(B), canRunNativeTexrecon: canRunNativeTexrecon)
    }
}
