/// Ariza bo'yicha olingan xona videolarining lokal ro'yxati.
///
/// Nega kerak: bitta ariza bir nechta xonadan iborat, har bir xona alohida
/// video va alohida 3DGS ishi. Foydalanuvchi bitta xonani olib, status
/// ekranidan qaytganda ro'yxat yo'qolmasligi va ilova yopilib qayta
/// ochilganda ham qaysi xona olingani ko'rinishi kerak.
///
/// Bu VAQTINCHA lokal nusxa: haqiqiy manba — 3DGS serverdagi `ariza_id`
/// bo'yicha so'rov (`GET /api/models?ariza_id=`). Server o'sha filtrni olgach
/// bu do'kon faqat "yuborilgan, lekin javob hali kelmagan" holat uchun
/// zaxira bo'lib qoladi.
library;

import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_baholash_bundle.dart';
import 'v2m_client.dart';

/// Serverdagi ish yorlig'i (`name` maydoni) — odam o'qiydigan matn, admin
/// ro'yxatida ko'rinadi. Format ATAYLAB qat'iy: `Ariza 123 · Xona nomi`.
///
/// v2m'da xona nomi uchun alohida ustun yo'q — faqat `room` (turning wire
/// qiymati). Shu sababli "Boshqa" xonaga foydalanuvchi bergan nom AYNAN shu
/// maydonda saqlanadi va [roomNameFromJobName] uni shu formatdan qaytarib
/// oladi. Ikkala funksiya birga o'zgarishi shart.
String v2mJobName({int? arizaId, required String room}) =>
    arizaId == null ? room : 'Ariza $arizaId · $room';

const _jobNameSeparator = ' · ';

/// [v2mJobName] ning teskarisi: yorliqdan xona nomini ajratib oladi.
/// Format mos kelmasa `null` — chaqiruvchi turning tarjimasiga qaytadi.
String? roomNameFromJobName(String jobName) {
  final i = jobName.lastIndexOf(_jobNameSeparator);
  final name =
      (i < 0 ? jobName : jobName.substring(i + _jobNameSeparator.length)).trim();
  return name.isEmpty ? null : name;
}

/// Bitta olingan xona.
class CapturedRoom {
  const CapturedRoom({
    required this.room,
    required this.createdAt,
    this.customName,
    this.videoPath,
    this.modelId,
    this.status,
  });

  final RoomKind room;

  /// Foydalanuvchi kiritgan nom — faqat [RoomKind.other] da. Ro'yxatda va
  /// kuzatuv ekranida turning tarjimasi o'rniga shu ko'rsatiladi.
  final String? customName;

  /// Lokal video fayli. OS temp/cache'ni tozalashi mumkin — mavjudligiga
  /// tayanmang, faqat qayta yuborish urinishida ishlating.
  ///
  /// `null` — yozuv serverdan kelgan (boshqa qurilmada olingan yoki ilova
  /// qayta o'rnatilgan): model bor, lekin lokal video yo'q.
  final String? videoPath;

  final DateTime createdAt;

  /// 3DGS serverdagi model id (`0826-a1b2c3`). Yuklash tugamaguncha null.
  final String? modelId;

  /// Oxirgi ko'rilgan holat: `queued` | `processing` | `ready` | `done` |
  /// `failed`. Faqat ko'rsatish uchun — haqiqiy holat serverdan olinadi.
  final String? status;

  bool get isUploaded => modelId != null;
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  /// Qayta yuborish faqat lokal video saqlanib qolgan bo'lsa mumkin.
  bool get canRetry => videoPath != null;

  /// Tur + nom juftligi. Nomni turning tarjimasiga qaytarish qoidasi bir
  /// joyda — [RoomChoice] da — turishi uchun.
  RoomChoice get choice => RoomChoice(room, name: customName);

  /// Ro'yxatda ko'rinadigan nom.
  String label(Locale l) => choice.label(l);

  CapturedRoom copyWith({String? modelId, String? status}) => CapturedRoom(
        room: room,
        customName: customName,
        videoPath: videoPath,
        createdAt: createdAt,
        modelId: modelId ?? this.modelId,
        status: status ?? this.status,
      );

  /// Serverdagi yozuvdan quriladi — lokal video yo'q.
  /// Serverdagi model yo'q bo'lib qolganda (o'chirilgan) — qatorni saqlab
  /// qolamiz, lekin uni "yuklanmagan" holatiga qaytaramiz. [copyWith] buni
  /// qilolmaydi, chunki u `?? this.x` ishlatadi va null uzatib bo'lmaydi.
  CapturedRoom forgetModel() => CapturedRoom(
        room: room,
        customName: customName,
        videoPath: videoPath,
        createdAt: createdAt,
      );

  static CapturedRoom? fromV2m(V2mModel m) {
    final room = RoomKind.values.where((r) => r.wire == m.room).firstOrNull;
    if (room == null) return null;
    return CapturedRoom(
      room: room,
      // Nom faqat "Boshqa" da qayta tiklanadi: qolgan turlar tarjimasi bilan
      // ko'rsatiladi, serverdagi o'zbekcha yorliq ularni qotirib qo'yardi.
      customName:
          room == RoomKind.other ? roomNameFromJobName(m.name) : null,
      createdAt: DateTime.now(),
      modelId: m.id,
      status: m.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'room': room.wire,
        if (customName != null) 'customName': customName,
        if (videoPath != null) 'videoPath': videoPath,
        'createdAt': createdAt.toIso8601String(),
        if (modelId != null) 'modelId': modelId,
        if (status != null) 'status': status,
      };

  static CapturedRoom? fromJson(Map<String, dynamic> m) {
    final wire = m['room'] as String?;
    final room = RoomKind.values.where((r) => r.wire == wire).firstOrNull;
    if (room == null) return null;
    return CapturedRoom(
      room: room,
      customName: m['customName'] as String?,
      videoPath: m['videoPath'] as String?,
      createdAt:
          DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      modelId: m['modelId'] as String?,
      status: m['status'] as String?,
    );
  }
}

class RoomCaptureStore {
  const RoomCaptureStore._();

  /// Ariza id bo'lmasa (draft yaratilmagan holat) alohida "draftsiz" kalit —
  /// shunda ro'yxat yo'qolmaydi va ariza paydo bo'lgach ko'chirib olinadi.
  static String _key(int? arizaId) =>
      'v2m_rooms_${arizaId?.toString() ?? 'no_ariza'}';

  static Future<List<CapturedRoom>> load(int? arizaId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(arizaId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(CapturedRoom.fromJson)
          .whereType<CapturedRoom>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(int? arizaId, List<CapturedRoom> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(arizaId),
      jsonEncode(rooms.map((r) => r.toJson()).toList()),
    );
  }

  /// Lokal ro'yxatni serverdagi holat bilan birlashtiradi.
  ///
  /// Server — haqiqiy manba: holat, tayyor fayllar, hatto qaysi xonalar
  /// borligi ham. Lokal do'kon esa server hali bilmaydigan narsani saqlaydi:
  /// yozib olingan, lekin yuklanmagan video (`modelId == null`) va qayta
  /// yuborish uchun kerak bo'ladigan fayl yo'li.
  static List<CapturedRoom> merge(
    List<CapturedRoom> local,
    List<V2mModel> remote,
  ) {
    final byId = {
      for (final r in local)
        if (r.modelId != null) r.modelId!: r,
    };
    final out = <CapturedRoom>[];
    // Hali yuklanmaganlar — faqat lokalda bor.
    out.addAll(local.where((r) => r.modelId == null));
    for (final m in remote) {
      final known = byId.remove(m.id);
      if (known != null) {
        out.add(known.copyWith(status: m.status));
      } else {
        final fresh = CapturedRoom.fromV2m(m);
        if (fresh != null) out.add(fresh);
      }
    }
    // Serverda topilmaganlar. Bu ro'yxat MUVAFFAQIYATLI so'rovdan keyin
    // to'ldiriladi (chaqiruvchi tarmoq xatosida merge'ni umuman chaqirmaydi),
    // ya'ni model haqiqatan yo'q — o'chirilgan.
    //
    // Ilgari bunday qator o'zgarishsiz saqlanardi va ro'yxatda yashil
    // "Tayyor" bo'lib turaverardi, bosilganda esa hech qachon tugamaydigan
    // kutish ekrani ochilardi. Endi:
    //   lokal video bor  -> "yuklanmagan" holatiga qaytadi (qayta yuborish
    //                       mumkin);
    //   lokal video yo'q -> qator olib tashlanadi, ko'rsatadigan narsa yo'q.
    for (final orphan in byId.values) {
      if (orphan.videoPath != null) out.add(orphan.forgetModel());
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  /// Bitta qatorni do'kondan olib tashlaydi. Model id bo'yicha, chunki
  /// [CapturedRoom] da qiymat bo'yicha tenglik yo'q.
  static Future<List<CapturedRoom>> removeByModelId(
    int? arizaId,
    String modelId,
  ) async {
    final rooms = await load(arizaId);
    final next = rooms.where((r) => r.modelId != modelId).toList();
    await save(arizaId, next);
    return next;
  }

  /// "Draftsiz" yig'ilgan ro'yxatni ariza id paydo bo'lgach ko'chiradi.
  /// Ariza kaliti allaqachon to'la bo'lsa tegmaydi.
  static Future<List<CapturedRoom>> adoptOrphans(int arizaId) async {
    final orphans = await load(null);
    if (orphans.isEmpty) return load(arizaId);
    final existing = await load(arizaId);
    final merged = [...existing, ...orphans];
    await save(arizaId, merged);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(null));
    return merged;
  }
}
