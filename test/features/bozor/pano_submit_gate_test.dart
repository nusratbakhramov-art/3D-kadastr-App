import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/pano_submit_gate.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/tour_link.dart';

/// E'lonni panorama tayyor bo'lmasdan yuborib bo'lmasin.
///
/// ⚠️ NEGA. `bozor_submit` kaliti yo'q yozuvni `if (key == null) continue;`
/// bilan JIMGINA o'tkazib yuboradi — e'lon xatosiz ketadi, panorama esa
/// unda bo'lmaydi. Foydalanuvchi 30 nishonni aylanib chiqqan mehnati
/// yo'qoladi va buni hech kim sezmaydi.
void main() {
  DescriptionDraft draft({
    List<String> panoramas = const [],
    Map<String, PendingPano> pending = const {},
    List<TourLink> tour = const [],
  }) {
    final d = DescriptionDraft();
    d.panoramas.addAll(panoramas);
    d.pendingPanoramas.addAll(pending);
    d.tourLinks.addAll(tour);
    return d;
  }

  PendingPano p(int id, {String? error}) =>
      PendingPano(jobId: id, startedAt: DateTime.now(), error: error);

  TourLink link(String a, String b) =>
      TourLink(from: a, to: b, yawDeg: 0, pitchDeg: 0);

  test('panorama yo\'q — to\'siq yo\'q', () {
    expect(panoSubmitBlocker(draft()), isNull);
  });

  test('bitta TAYYOR panorama — tur talab qilinmaydi', () {
    expect(panoSubmitBlocker(draft(panoramas: ['k1'])), isNull);
  });

  test('hali tikilayotgan panorama TO\'SADI', () {
    final d = draft(panoramas: ['job:7'], pending: {'job:7': p(7)});
    expect(panoSubmitBlocker(d), 'bozor.pano.gate.pending');
  });

  test('YIQILGAN panorama to\'sadi — va u tikilayotgandan MUHIMROQ', () {
    // Ikkalasi bo'lsa foydalanuvchiga avval HARAKAT talab qiladigani
    // aytilishi kerak: kutish o'z-o'zidan o'tadi, xato esa o'tmaydi.
    final d = draft(
      panoramas: ['job:7', 'job:8'],
      pending: {'job:7': p(7), 'job:8': p(8, error: 'tikib boʻlmadi')},
    );
    expect(panoSubmitBlocker(d), 'bozor.pano.gate.failed');
  });

  group('2+ panorama — tur to\'liq bo\'lsin', () {
    test('havolasiz — to\'sadi', () {
      final d = draft(panoramas: ['a', 'b']);
      expect(panoSubmitBlocker(d), 'bozor.pano.gate.tour');
    });

    test('a→b bog\'langan — o\'tadi', () {
      final d = draft(panoramas: ['a', 'b'], tour: [link('a', 'b')]);
      expect(panoSubmitBlocker(d), isNull);
    });

    test('OROL to\'sadi: a↔b va c↔d', () {
      // ⚠️ Shu holat uchun «har birida kamida bitta havola bor» qoidasi
      // YETMAYDI: to'rttasida ham havola bor, lekin `a` dan boshlagan
      // ko'ruvchi `c` va `d` ga hech qachon yetolmaydi.
      final d = draft(
        panoramas: ['a', 'b', 'c', 'd'],
        tour: [link('a', 'b'), link('b', 'a'), link('c', 'd'), link('d', 'c')],
      );
      expect(panoSubmitBlocker(d), 'bozor.pano.gate.tour');
    });

    test('zanjir a→b→c — hammasiga yetiladi, o\'tadi', () {
      final d = draft(
        panoramas: ['a', 'b', 'c'],
        tour: [link('a', 'b'), link('b', 'c')],
      );
      expect(panoSubmitBlocker(d), isNull);
    });

    test('tur to\'liq, lekin bittasi hali tikilyapti — KUTISH to\'sadi', () {
      final d = draft(
        panoramas: ['a', 'b', 'job:9'],
        pending: {'job:9': p(9)},
        tour: [link('a', 'b')],
      );
      expect(panoSubmitBlocker(d), 'bozor.pano.gate.pending');
    });
  });
}
