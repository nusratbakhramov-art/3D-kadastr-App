/// 360° «house tour» — panoramalarni bir-biriga bog'lovchi o'tish nuqtalari.
///
/// Foydalanuvchi bir panoramani ochadi, eshik ko'ringan yo'nalishga qaraydi
/// va o'sha joyga tugma qo'yadi; tugmani bosgan odam keyingi xonaga o'tadi.
/// Shu havolalar yig'indisi yurib bo'ladigan turni tashkil qiladi.
///
/// ⚠️ HAVOLA IKKI XIL NARSAGA ISHORA QILISHI MUMKIN. Sehrgarda panorama
/// hali yuklanmagan lokal FAYL YO'LI, tahrirlashda esa serverdagi S3
/// KALITI bo'ladi. Ikkalasini bitta maydonda saqlash ataylab: havola
/// yasalgan paytda fayl yuklanganmi yoki yo'qmi — bu foydalanuvchi
/// uchun ham, UI uchun ham ahamiyatsiz, va yuborishdan oldin
/// [resolveTourLinks] ularni bir xil kalitga keltiradi.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Bitta panoramadan chiqadigan havolalar chegarasi.
///
/// Backenddagi `MAX_TOUR_LINKS_PER_PANORAMA` bilan BIR XIL bo'lishi
/// kerak. Mobil tomonda cheklash foydalanuvchini 400 xatosidan asraydi:
/// server rad etganda butun e'lon yuborilmay qolardi va sabab
/// tushunarsiz bo'lardi.
const int kMaxTourLinksPerPanorama = 8;

/// Ikki tugma orasidagi eng kichik burchak masofasi (gradus).
///
/// Bundan yaqin qo'yilgan ikki tugma sferada ustma-ust tushadi va
/// pastdagisini bosib bo'lmaydi. Bu QAT'IY taqiq emas — ogohlantirish:
/// tor yo'lakda ikki eshik haqiqatan yonma-yon bo'lishi mumkin.
const double kMinHotspotSeparationDeg = 12;

@immutable
class TourLink {
  const TourLink({
    required this.from,
    required this.to,
    required this.yawDeg,
    required this.pitchDeg,
    this.label,
  });

  /// Havola QAYSI panoramada turadi — lokal yo'l yoki S3 kaliti.
  final String from;

  /// QAYSI panoramaga olib boradi — lokal yo'l yoki S3 kaliti.
  final String to;

  /// Tugma yo'nalishi, 0..360. Ekvirektangulyar kelishuv: tasvirning
  /// chap chetidan o'ngga.
  final double yawDeg;

  /// Balandlik, −90..+90. Musbat — yuqoriga.
  final double pitchDeg;

  /// Ixtiyoriy yozuv — «Oshxona», «Yotoqxona».
  final String? label;

  TourLink copyWith({String? from, String? to, String? label}) => TourLink(
    from: from ?? this.from,
    to: to ?? this.to,
    yawDeg: yawDeg,
    pitchDeg: pitchDeg,
    label: label ?? this.label,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'from': from,
    'to': to,
    'yaw_deg': yawDeg,
    'pitch_deg': pitchDeg,
    if (label != null) 'label': label,
  };

  static TourLink fromJson(Map<String, Object?> j) => TourLink(
    from: (j['from'] ?? j['from_key'] ?? '').toString(),
    to: (j['to'] ?? j['to_key'] ?? '').toString(),
    yawDeg: (j['yaw_deg'] as num?)?.toDouble() ?? 0,
    pitchDeg: (j['pitch_deg'] as num?)?.toDouble() ?? 0,
    label: (j['label'] as String?)?.trim().isEmpty ?? true
        ? null
        : (j['label'] as String).trim(),
  );

  @override
  bool operator ==(Object other) =>
      other is TourLink &&
      other.from == from &&
      other.to == to &&
      other.yawDeg == yawDeg &&
      other.pitchDeg == pitchDeg &&
      other.label == label;

  @override
  int get hashCode => Object.hash(from, to, yawDeg, pitchDeg, label);

  @override
  String toString() =>
      'TourLink(${from.split('/').last} → ${to.split('/').last} '
      '@${yawDeg.toStringAsFixed(0)}°)';
}

/// Havolalarni YUBORISHGA tayyorlaydi: lokal yo'llarni S3 kalitiga
/// o'giradi va o'girib bo'lmaganini TASHLAB YUBORADI.
///
/// [uploaded] — qurilma yo'li → S3 kaliti (`DescriptionDraft.uploadedMedia`).
/// [allowedKeys] — AYNI SHU so'rovda yuborilayotgan panorama kalitlari.
///
/// ⚠️ [allowedKeys] SHART va u yuborilayotgan `media` dan olinadi, umumiy
/// "bilinadigan kalitlar" ro'yxatidan EMAS. Server havolani o'sha
/// so'rovdagi media bilan solishtiradi, ya'ni ro'yxatga tushmagan
/// panoramaga ishora qilgan havola 400 beradi — va o'shanda BUTUN e'lon
/// yuborilmay qoladi, bitta tugma uchun.
///
/// ⚠️ TASHLAB YUBORISH ATAYLAB, xato emas. Sabablari normal: fayl
/// yuklanmadi (tarmoq uzildi), yoki foydalanuvchi panoramani o'chirdi.
/// Foydalanuvchiga buni [danglingLinks] oldindan ko'rsatadi.
List<Map<String, Object?>> resolveTourLinks(
  List<TourLink> links, {
  required Map<String, String> uploaded,
  required Set<String> allowedKeys,
}) {
  String? key(String ref) {
    // Lokal yo'l bo'lsa — yuklangan kaliti; allaqachon kalit bo'lsa — o'zi.
    final String k = uploaded[ref] ?? ref;
    return allowedKeys.contains(k) ? k : null;
  }

  final out = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final TourLink l in links) {
    final String? a = key(l.from);
    final String? b = key(l.to);
    if (a == null || b == null || a == b) continue;
    // Server takrorni rad etadi — bu yerda jimgina tashlaymiz, chunki
    // takror UI'da ham ko'rinmaydi (ustma-ust tushadi).
    if (!seen.add('$a→$b')) continue;
    out.add(<String, Object?>{
      'from_key': a,
      'to_key': b,
      'yaw_deg': l.yawDeg % 360,
      'pitch_deg': l.pitchDeg.clamp(-90.0, 90.0),
      if (l.label != null) 'label': l.label,
    });
  }
  return out;
}

/// Ikki uchidan biri MAVJUD panoramalar ro'yxatida bo'lmagan havolalar.
///
/// Panorama o'chirilganda uning havolalari yetim qoladi. Ularni jimgina
/// tashlash foydalanuvchi uchun «tugmam yo'qolibdi» bo'lardi, shuning
/// uchun UI avval ko'rsatadi.
List<TourLink> danglingLinks(List<TourLink> links, List<String> panoramas) {
  final set = panoramas.toSet();
  return <TourLink>[
    for (final TourLink l in links)
      if (!set.contains(l.from) || !set.contains(l.to)) l,
  ];
}

/// [panoramas] dagi qaysilariga [start] dan YURIB yetib bo'ladi.
///
/// Tur — yo'naltirilgan graf, ya'ni A→B havolasi B→A ni bermaydi.
/// Yetib bo'lmaydigan panorama e'londa bor, lekin turda YO'Q: uni faqat
/// ro'yxatdan ochish mumkin. Bu xato emas, lekin deyarli har doim
/// foydalanuvchi unutgan havola bo'ladi.
Set<String> reachableFrom(
  String start,
  List<TourLink> links,
) {
  final out = <String>{start};
  final queue = <String>[start];
  while (queue.isNotEmpty) {
    final String cur = queue.removeLast();
    for (final TourLink l in links) {
      if (l.from == cur && out.add(l.to)) queue.add(l.to);
    }
  }
  return out;
}

/// Birinchi panoramadan yetib bo'lmaydigan panoramalar.
List<String> unreachablePanoramas(
  List<String> panoramas,
  List<TourLink> links,
) {
  if (panoramas.length < 2) return const <String>[];
  final Set<String> seen = reachableFrom(panoramas.first, links);
  return <String>[
    for (final String p in panoramas)
      if (!seen.contains(p)) p,
  ];
}

/// Sferadagi ikki yo'nalish orasidagi burchak (gradus).
///
/// Oddiy `yaw` ayirmasi YARAMAYDI: qutbga yaqin joyda yaw farqi katta
/// bo'lsa ham ikki nuqta yonma-yon turadi, ya'ni ikki tugma baribir
/// ustma-ust tushardi.
double angularSeparationDeg(
  double yaw1,
  double pitch1,
  double yaw2,
  double pitch2,
) {
  const double d = math.pi / 180;
  final double p1 = pitch1 * d;
  final double p2 = pitch2 * d;
  final double dy = (yaw1 - yaw2) * d;
  final double cos =
      math.sin(p1) * math.sin(p2) +
      math.cos(p1) * math.cos(p2) * math.cos(dy);
  return math.acos(cos.clamp(-1.0, 1.0)) / d;
}

/// Yangi tugma [yaw]/[pitch] ga qo'yilsa, USTMA-UST tushadigan mavjud
/// havola bormi.
TourLink? overlappingLink(
  List<TourLink> links,
  String from,
  double yaw,
  double pitch, {
  double minSepDeg = kMinHotspotSeparationDeg,
}) {
  for (final TourLink l in links) {
    if (l.from != from) continue;
    if (angularSeparationDeg(l.yawDeg, l.pitchDeg, yaw, pitch) < minSepDeg) {
      return l;
    }
  }
  return null;
}

/// [from] panoramasidan chiqadigan havolalar.
List<TourLink> linksFrom(List<TourLink> links, String from) =>
    <TourLink>[for (final TourLink l in links) if (l.from == from) l];

/// [from] dan [to] ga havola ALLAQACHON bormi.
bool hasLink(List<TourLink> links, String from, String to) =>
    links.any((TourLink l) => l.from == from && l.to == to);
