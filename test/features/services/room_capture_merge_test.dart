import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/data/room_capture_store.dart';
import 'package:kadastr/features/services/data/v2m_client.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';

/// `RoomCaptureStore.merge` — lokal ro'yxat va 3DGS serverdagi holatni
/// birlashtiradi. O'chirish funksionali aynan shu joyga tayanadi: model
/// serverdan o'chirilgach qator qayta "Tayyor" bo'lib paydo bo'lmasligi kerak.
///
/// Ilgari shunday bo'lardi: `merge` serverda topilmagan qatorni o'zgarishsiz
/// saqlab qolardi, ro'yxatda yashil "Tayyor" turardi, bosilganda esa hech
/// qachon tugamaydigan kutish ekrani ochilardi.

V2mModel _model(
  String id, {
  String status = 'done',
  String room = 'living',
  String? name,
}) =>
    V2mModel.fromMap({
      'id': id,
      'name': name ?? 'Ariza 1 · $room',
      'status': status,
      'stage': status,
      'progress': status == 'done' ? 100 : 40,
      'room': room,
      'ariza_id': '1',
      'files': const <String, dynamic>{},
    });

CapturedRoom _local({
  required RoomKind room,
  String? customName,
  String? modelId,
  String? status,
  String? videoPath,
  int day = 1,
}) =>
    CapturedRoom(
      room: room,
      customName: customName,
      modelId: modelId,
      status: status,
      videoPath: videoPath,
      createdAt: DateTime.utc(2026, 1, day),
    );

void main() {
  test('serverdagi holat lokal qatorga ko\'chadi, video yo\'li saqlanadi', () {
    final merged = RoomCaptureStore.merge(
      [
        _local(
          room: RoomKind.living,
          modelId: 'm1',
          status: 'processing',
          videoPath: '/tmp/a.mov',
        ),
      ],
      [_model('m1', status: 'done')],
    );

    expect(merged, hasLength(1));
    expect(merged.single.modelId, 'm1');
    expect(merged.single.status, 'done');
    expect(merged.single.videoPath, '/tmp/a.mov',
        reason: 'qayta yuborish uchun lokal fayl yo\'li kerak');
  });

  test('yuklanmagan qator serverda yo\'q bo\'lsa ham qoladi', () {
    final merged = RoomCaptureStore.merge(
      [_local(room: RoomKind.kitchen, videoPath: '/tmp/b.mov')],
      const [],
    );

    expect(merged, hasLength(1));
    expect(merged.single.modelId, isNull);
    expect(merged.single.videoPath, '/tmp/b.mov');
  });

  test('serverda faqat masofadagi model bo\'lsa yangi qator paydo bo\'ladi', () {
    final merged = RoomCaptureStore.merge(const [], [_model('m9')]);

    expect(merged, hasLength(1));
    expect(merged.single.modelId, 'm9');
    expect(merged.single.videoPath, isNull);
  });

  group('o\'chirilgan model', () {
    test('lokal video bor: qator "yuklanmagan" holatiga qaytadi', () {
      final merged = RoomCaptureStore.merge(
        [
          _local(
            room: RoomKind.living,
            modelId: 'gone',
            status: 'done',
            videoPath: '/tmp/c.mov',
          ),
        ],
        const [], // server bu modelni bilmaydi — o'chirilgan
      );

      expect(merged, hasLength(1));
      expect(merged.single.modelId, isNull,
          reason: 'o\'chirilgan model id qolib ketmasligi kerak');
      expect(merged.single.status, isNull,
          reason: '"done" qolsa qator yashil "Tayyor" bo\'lib turaverardi');
      expect(merged.single.videoPath, '/tmp/c.mov',
          reason: 'video bor — qayta yuborish mumkin bo\'lishi kerak');
      expect(merged.single.isDone, isFalse);
      expect(merged.single.isUploaded, isFalse);
    });

    test('lokal video yo\'q: qator butunlay olib tashlanadi', () {
      final merged = RoomCaptureStore.merge(
        [_local(room: RoomKind.balcony, modelId: 'gone', status: 'done')],
        const [],
      );

      expect(merged, isEmpty,
          reason: 'na model, na video — ko\'rsatadigan narsa yo\'q');
    });

    test('bir nechta xonadan faqat o\'chirilgani ketadi', () {
      final merged = RoomCaptureStore.merge(
        [
          _local(room: RoomKind.living, modelId: 'keep', status: 'done'),
          _local(room: RoomKind.kitchen, modelId: 'gone', status: 'done'),
        ],
        [_model('keep')],
      );

      expect(merged.map((r) => r.modelId), ['keep']);
    });
  });

  test('natija createdAt bo\'yicha tartiblanadi', () {
    final merged = RoomCaptureStore.merge(
      [
        _local(room: RoomKind.living, videoPath: '/tmp/late.mov', day: 5),
        _local(room: RoomKind.kitchen, videoPath: '/tmp/early.mov', day: 2),
      ],
      const [],
    );

    expect(
      merged.map((r) => r.videoPath),
      ['/tmp/early.mov', '/tmp/late.mov'],
    );
  });

  test('forgetModel faqat server maydonlarini tozalaydi', () {
    final row = _local(
      room: RoomKind.bathroom,
      customName: 'Hammom 2',
      modelId: 'm1',
      status: 'done',
      videoPath: '/tmp/d.mov',
    );
    final forgotten = row.forgetModel();

    expect(forgotten.modelId, isNull);
    expect(forgotten.status, isNull);
    expect(forgotten.room, RoomKind.bathroom);
    expect(forgotten.customName, 'Hammom 2');
    expect(forgotten.videoPath, '/tmp/d.mov');
    expect(forgotten.createdAt, row.createdAt);
  });

  /// "Boshqa" xonaga berilgan nom. v2m'da nom uchun alohida ustun yo'q —
  /// yagona kanal ish yorlig'i (`name`), shu sababli uni yozish va qaytarib
  /// o'qish bir-biriga aynan mos kelishi kerak.
  group('foydalanuvchi kiritgan xona nomi', () {
    test('lokal saqlashda yo\'qolmaydi', () {
      final row = _local(
        room: RoomKind.other,
        customName: 'Ish xonasi',
        videoPath: '/tmp/e.mov',
      );
      final back = CapturedRoom.fromJson(row.toJson());

      expect(back, isNotNull);
      expect(back!.room, RoomKind.other);
      expect(back.customName, 'Ish xonasi');
      expect(back.choice.labelUz, 'Ish xonasi');
    });

    test('nomsiz qator turning o\'zbekcha nomini yuboradi', () {
      expect(_local(room: RoomKind.kitchen).choice.labelUz, 'Oshxona');
    });

    test('server yorlig\'idan qaytib o\'qiladi', () {
      expect(v2mJobName(arizaId: 42, room: 'Ish xonasi'),
          'Ariza 42 · Ish xonasi');
      expect(roomNameFromJobName('Ariza 42 · Ish xonasi'), 'Ish xonasi');
      // Ariza id hali yo'q edi — yorliq faqat nomdan iborat.
      expect(roomNameFromJobName(v2mJobName(room: 'Ayvon')), 'Ayvon');
    });

    test('faqat masofadagi "Boshqa" qatorda nom tiklanadi', () {
      final merged = RoomCaptureStore.merge(
        const [],
        [
          _model('m1', room: 'other', name: 'Ariza 1 · Ish xonasi'),
          _model('m2', room: 'kitchen'),
        ],
      );

      expect(merged, hasLength(2));
      expect(merged.first.customName, 'Ish xonasi');
      // Oddiy turlar tarjimasi bilan ko'rsatiladi — serverdagi o'zbekcha
      // yorliq ularni bir tilga qotirib qo'yardi.
      expect(merged.last.customName, isNull);
    });

    test('lokal qatordagi nom server holati ko\'chganda saqlanadi', () {
      final merged = RoomCaptureStore.merge(
        [
          _local(
            room: RoomKind.other,
            customName: 'Ayvon',
            modelId: 'm1',
            status: 'processing',
          ),
        ],
        [_model('m1', room: 'other', name: 'Ariza 1 · Ayvon')],
      );

      expect(merged.single.status, 'done');
      expect(merged.single.customName, 'Ayvon');
    });
  });
}
