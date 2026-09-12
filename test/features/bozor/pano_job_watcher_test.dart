import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/bozor/data/pano_job_watcher.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/panorama/data/pano_api.dart';

/// Fonda tikilayotgan panoramani kim kutib oladi.
///
/// ⚠️ ENG NOZIK JOYI — O'RNIGA QO'YISH. Tayyor bo'lgan panorama
/// `panoramas` ro'yxatida AYNAN O'Z O'RNIDA haqiqiy kalitga almashishi
/// kerak: foydalanuvchi tartibni ko'rib turibdi va tur havolalari ham shu
/// tartibga tayanadi. Oxiriga qo'shib yuborilsa xonalar joy almashadi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BozorDraft draftWith(List<String> refs, Map<String, PendingPano> pending) {
    final d = BozorDraft(
      deal: DealType.rent,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    );
    d.description.panoramas.addAll(refs);
    d.description.pendingPanoramas.addAll(pending);
    return d;
  }

  PendingPano pend(int id, {DateTime? at}) =>
      PendingPano(jobId: id, startedAt: at ?? DateTime.now());

  /// `status` uchun javob beruvchi soxta klient.
  http.Client client(Map<int, Map<String, Object?>> byJob) =>
      MockClient((req) async {
        final id = int.tryParse(req.url.pathSegments.last) ?? 0;
        return http.Response(
          jsonEncode(byJob[id] ?? {'id': id, 'status': 'stitching'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

  /// Saqlashni kuzatamiz — u haqiqiy qoralamada `shared_preferences` ga
  /// boradi, testda esa faqat CHAQIRILGANI muhim.
  late List<WizardStep> saves;

  PanoJobWatcher watcher(http.Client c, {Duration? deadline}) => PanoJobWatcher(
    api: PanoApi(client: c),
    interval: const Duration(days: 1), // taymer testda kerak emas
    deadline: deadline ?? const Duration(minutes: 45),
    save: (_, reached) => saves.add(reached),
  );

  setUp(() => saves = <WizardStep>[]);

  test('TAYYOR bo\'lgani O\'Z O\'RNIDA kalitga almashadi', () async {
    final d = draftWith(
      ['a', 'job:7', 'c'],
      {'job:7': pend(7)},
    );
    final w = watcher(client({
      7: {
        'id': 7,
        'status': 'done',
        'storage_key': 'listings/media/3/pano_7.jpg',
        'url': 'https://cdn.test/p7.jpg',
      },
    }));
    w.watch(d);
    await w.poll();

    expect(d.description.panoramas, ['a', 'listings/media/3/pano_7.jpg', 'c'],
        reason: 'tartib buzildi');
    expect(d.description.pendingPanoramas, isEmpty);
    expect(d.description.panoramaUrls['listings/media/3/pano_7.jpg'],
        'https://cdn.test/p7.jpg');
    // Busiz `bozor_submit` kalitni fayl yo'li deb bilib yiqiladi.
    expect(d.description.uploadedMedia['listings/media/3/pano_7.jpg'],
        'listings/media/3/pano_7.jpg');
    expect(w.takeReady(), ['listings/media/3/pano_7.jpg']);
    // ⚠️ Saqlanmasa ilova yopilib ochilganda `job:7` havolasi qaytib kelardi
    // va e'lon abadiy yuborib bo'lmas holga tushardi.
    expect(saves, isNotEmpty, reason: 'qoralama saqlanmadi');
    w.dispose();
  });

  test('XATO — yozuv qoladi va sababi saqlanadi', () async {
    final d = draftWith(['job:8'], {'job:8': pend(8)});
    final w = watcher(client({
      8: {'id': 8, 'status': 'error', 'error': 'kadrlar topilmadi'},
    }));
    w.watch(d);
    await w.poll();

    final p = d.description.pendingPanoramas['job:8'];
    expect(p, isNotNull);
    expect(p!.failed, isTrue);
    expect(p.error, 'kadrlar topilmadi');
    // Havola ro'yxatda QOLADI — foydalanuvchi uni ko'rib, qayta urinishi
    // yoki o'chirishi kerak.
    expect(d.description.panoramas, ['job:8']);
    expect(w.takeReady(), isEmpty);
    w.dispose();
  });

  test('hali ishlayapti — hech narsa o\'zgarmaydi', () async {
    final d = draftWith(['job:9'], {'job:9': pend(9)});
    final w = watcher(client({9: {'id': 9, 'status': 'stitching', 'progress': 0.4}}));
    w.watch(d);
    await w.poll();

    expect(d.description.pendingPanoramas['job:9']!.failed, isFalse);
    expect(d.description.panoramas, ['job:9']);
    w.dispose();
  });

  test('YIQILGANI qayta so\'ralmaydi — qayta urinish QO\'LDA', () async {
    var calls = 0;
    final c = MockClient((req) async {
      calls++;
      return http.Response('{"id":8,"status":"done","storage_key":"k"}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final d = draftWith(
      ['job:8'],
      {'job:8': PendingPano(jobId: 8, startedAt: DateTime.now(), error: 'xato')},
    );
    final w = watcher(c);
    w.watch(d);
    await w.poll();

    expect(calls, 0, reason: 'yiqilgan ish so\'ralmasligi kerak edi');
    w.dispose();
  });

  test('MUDDAT o\'tsa yiqilgan deb belgilanadi', () async {
    // ⚠️ Busiz `queued` da qotib qolgan ish (worker o'lgan) abadiy
    // «tayyorlanmoqda» bo'lib turardi va e'lon hech qachon yuborilmasdi.
    final d = draftWith(
      ['job:10'],
      {'job:10': pend(10, at: DateTime.now().subtract(const Duration(hours: 2)))},
    );
    final w = watcher(
      client({10: {'id': 10, 'status': 'queued'}}),
      deadline: const Duration(minutes: 45),
    );
    w.watch(d);
    await w.poll();

    expect(d.description.pendingPanoramas['job:10']!.failed, isTrue);
    w.dispose();
  });

  test('tarmoq yiqilsa kuzatuv TO\'XTAMAYDI', () async {
    final d = draftWith(['job:11'], {'job:11': pend(11)});
    final w = watcher(MockClient((_) async => throw Exception('tarmoq yo\'q')));
    w.watch(d);
    await w.poll();

    // Hali ishlayotgan deb qoladi — keyingi tikda qayta so'raladi.
    expect(d.description.pendingPanoramas['job:11']!.failed, isFalse);
    w.dispose();
  });

  group('muddat — PRODDA o\'lchangan vaqtga qarab qo\'yilgan', () {
    test('eng uzun tikishdan ANCHA katta', () {
      // ⚠️ Prod `celery-panorama` logi (2026-09-12, 30 kadr → 4096×2048):
      //     420.5 · 451.2 · 459.4 · 474.1 · 567.1 s
      // Sintetik o'lchov ham shuni tasdiqladi: 4096 → 421.5 s.
      // Muddat undan kichik bo'lsa ISHLAYOTGAN tikish yiqilgan deb
      // belgilanardi va foydalanuvchi tayyor panoramani yo'qotardi.
      const worstMeasured = Duration(seconds: 567);
      final w = PanoJobWatcher(api: PanoApi(client: MockClient((_) async =>
          http.Response('{}', 200))));
      expect(w.deadline.inSeconds, greaterThan(worstMeasured.inSeconds * 3));
      // Cheksiz ham emas: worker o'lgan bo'lsa foydalanuvchi e'lonini
      // qachondir yubora olishi kerak.
      expect(w.deadline.inHours, lessThanOrEqualTo(2));
      w.dispose();
    });

    test('so\'rash oralig\'i tez-tez EMAS', () {
      // Tikish daqiqalar bilan o'lchanadi — sekundiga bir so'rash faqat
      // batareya va trafik yeydi.
      final w = PanoJobWatcher(api: PanoApi(client: MockClient((_) async =>
          http.Response('{}', 200))));
      expect(w.interval.inSeconds, greaterThanOrEqualTo(5));
      expect(w.interval.inSeconds, lessThanOrEqualTo(60));
      w.dispose();
    });
  });
}
