/// AI Baholash wizard'ining 3D skan qadami natijasi.
///
/// Oqim: skan (saved_raw) → mesh ko'rish → USDZ ga ishlash. Zanjir oxirida
/// (process tugagach) to'ldiriladi va `AiCadastreScreen` orqali
/// `AiBaholashBundle.scan` ga uzatiladi.
///
/// Hozir "mobil-only" faza: skan qurilmada saqlanadi va USDZ lokalda
/// generatsiya qilinadi. Serverga yuklash + baholash payload'iga qo'shish
/// keyingi faza (shu sababli `usdzKey` hozircha null bo'lishi mumkin va
/// `AiBaholashBundle.toJson()` skan blokini hali yubormaydi).
library;

class AiScanResult {
  const AiScanResult({
    required this.savedScanId,
    required this.version,
    required this.usdzPath,
    this.usdzKey,
    this.floorAreaSqm,
    this.walls = 0,
    this.doors = 0,
    this.windows = 0,
    this.objects = 0,
  });

  /// Documents/saved_scans/scan_NNN — saqlangan xom skan ID si.
  final int savedScanId;

  /// Texturing natijasi versiyasi (process'dan keyin, v1, v2, ...).
  final int version;

  /// Qayta ishlangan teksturali USDZ ning qurilmadagi to'liq yo'li.
  final String usdzPath;

  /// USDZ serverga yuklangach qaytgan S3 object key. Mobil-only fazada null.
  final String? usdzKey;

  /// Skan o'lchagan pol maydoni (m²) — agar mavjud bo'lsa.
  final double? floorAreaSqm;

  final int walls;
  final int doors;
  final int windows;
  final int objects;

  /// Backend payload uchun (keyingi faza). Hozir `AiBaholashBundle.toJson()`
  /// buni yubormaydi — faqat backend skan maydonlarini qabul qilgach ulanadi.
  Map<String, dynamic> toJson() => {
        'saved_scan_id': savedScanId,
        'version': version,
        if (usdzKey != null) 'usdz_key': usdzKey,
        if (floorAreaSqm != null) 'floor_area_sqm': floorAreaSqm,
        'walls': walls,
        'doors': doors,
        'windows': windows,
        'objects': objects,
      };
}
