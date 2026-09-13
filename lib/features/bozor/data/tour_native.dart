/// Nativ tur (`PanoTour.swift`) ↔ Dart `TourLink` — konvertatsiya va
/// «Yangi xona» amalining havola mantig'i.
///
/// Sof funksiyalar: kanal ham, UI ham yo'q — `tour_native_test.dart`
/// qurilmasiz sinaydi. Burchak konvensiyasi ikkala tarafda Dart/backend'niki
/// (`yawDeg` 0..360 ekvirekt bo'ylama, `pitchDeg` −90..90); Uy360 sahna
/// konvensiyasiga o'tkazishni nativ taraf o'zi qiladi.
library;

import '../../panorama/data/pano_capture_channel.dart';
import '../models/tour_link.dart';

/// `TourLink` → kanal xaritasi (`yawDeg`/`pitchDeg` — camelCase, JSON
/// `yaw_deg` dan FARQLI: kanal shartnomasi Swift bilan kelishilgan).
Map<String, Object?> tourLinkToChannel(TourLink l) => <String, Object?>{
  'from': l.from,
  'to': l.to,
  'yawDeg': l.yawDeg,
  'pitchDeg': l.pitchDeg,
  'label': ?l.label,
};

List<Map<String, Object?>> tourLinksToChannel(Iterable<TourLink> links) =>
    <Map<String, Object?>>[
      for (final TourLink l in links) tourLinkToChannel(l),
    ];

/// Kanal xaritalari → `TourLink`. `from`/`to` bo'sh bo'lganlar tashlanadi.
List<TourLink> tourLinksFromChannel(Iterable<Map<String, Object?>> raw) =>
    <TourLink>[
      for (final Map<String, Object?> m in raw)
        if ((m['from'] ?? '').toString().isNotEmpty &&
            (m['to'] ?? '').toString().isNotEmpty)
          TourLink(
            from: m['from'].toString(),
            to: m['to'].toString(),
            yawDeg: (m['yawDeg'] as num?)?.toDouble() ?? 0,
            pitchDeg: (m['pitchDeg'] as num?)?.toDouble() ?? 0,
            label: (m['label'] as String?)?.trim().isEmpty ?? true
                ? null
                : (m['label'] as String).trim(),
          ),
    ];

/// Turdan «Yangi xona — hozir tushirish» tanlanib, xona tushirilib yuklangach
/// ([newKey]) havolalarni qo'shadi:
///
///  * to'g'ri: `action.fromKey → newKey` aynan foydalanuvchi bosgan joyda;
///  * teskari: `newKey → action.fromKey` — qarama-qarshi tomonda (yaw+180°,
///    pitch 0), tur ikki tomonga yurilsin (foydalanuvchi keyin ko'chirishi
///    mumkin) — nativ `addHotspot` dagi qoida bilan bir xil.
///
/// Chegara: bitta panoramadan ko'pi bilan [kMaxTourLinksPerPanorama] —
/// to'lgan bo'lsa o'sha tomon QO'SHILMAYDI (backend 400 bermasin).
/// Takror (`from→to` allaqachon bor) ham qo'shilmaydi.
List<TourLink> mergeNewRoomLinks(
  List<TourLink> links,
  PanoTourNewRoom action,
  String newKey,
) {
  final out = List<TourLink>.of(links);
  bool has(String from, String to) =>
      out.any((l) => l.from == from && l.to == to);
  int count(String from) => out.where((l) => l.from == from).length;

  if (!has(action.fromKey, newKey) &&
      count(action.fromKey) < kMaxTourLinksPerPanorama) {
    out.add(
      TourLink(
        from: action.fromKey,
        to: newKey,
        yawDeg: action.yawDeg % 360,
        pitchDeg: action.pitchDeg,
      ),
    );
  }
  if (!has(newKey, action.fromKey) &&
      count(newKey) < kMaxTourLinksPerPanorama) {
    out.add(
      TourLink(
        from: newKey,
        to: action.fromKey,
        yawDeg: (action.yawDeg + 180) % 360,
        pitchDeg: 0,
      ),
    );
  }
  return out;
}
