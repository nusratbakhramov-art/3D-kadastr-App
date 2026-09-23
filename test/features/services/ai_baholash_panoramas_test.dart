import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/models/tour_link.dart';
import 'package:kadastr/features/services/api_cadastre_service.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';

/// 360° xonalar AI Baholash bundle'ida: yuborish shakli (backend
/// `panorama_keys` / `panorama_names` / `tour_links`) va qoralama round-trip.
void main() {
  const a = 'ai-baholash/panorama/7/a/pano_1.jpg';
  const b = 'ai-baholash/panorama/7/b/pano_2.jpg';

  AiBaholashBundle bundle() => AiBaholashBundle(
    kadastr: const CadastreLookupResult(cadastreNumber: '10:01:01:01:01:0001'),
    panoramaKeys: [a, b],
    panoramaPaths: {a: '/support/ai_pano/pano_1.jpg'},
    panoramaNames: {a: 'Oshxona'},
    tourLinks: const [
      TourLink(from: a, to: b, yawDeg: 370, pitchDeg: -5, label: 'Zalga'),
      TourLink(from: b, to: a, yawDeg: 200, pitchDeg: 0),
      // O'chirilgan xonaga ishora — yuborilmaydi.
      TourLink(from: a, to: 'gone.jpg', yawDeg: 10, pitchDeg: 0),
    ],
  );

  test('submit payload: kalitlar, nomlar, tozalangan havolalar', () {
    final j = bundle().toJson();
    expect(j['panorama_keys'], [a, b]);
    expect(j['panorama_names'], {a: 'Oshxona'});
    final links = j['tour_links'] as List;
    expect(links, hasLength(2), reason: 'yetim havola tashlanadi');
    expect(links.first, {
      'from_key': a,
      'to_key': b,
      'yaw_deg': 10.0, // 370 % 360 — backend 0..360 ni talab qiladi
      'pitch_deg': -5.0,
      'label': 'Zalga',
    });
    expect(
      j.containsKey('panorama_paths'),
      isFalse,
      reason: 'lokal yo\'l faqat qoralamaga',
    );
  });

  test('qoralama round-trip: yo\'llar ham qaytadi', () {
    final restored = AiBaholashBundle.fromJson(bundle().toJson(forDraft: true));
    expect(restored.panoramaKeys, [a, b]);
    expect(restored.panoramaPaths, {a: '/support/ai_pano/pano_1.jpg'});
    expect(restored.panoramaNames, {a: 'Oshxona'});
    expect(restored.tourLinks.map((l) => (l.from, l.to)).toList(), [
      (a, b),
      (b, a),
    ]);
  });

  test('360 yo\'q — payload o\'zgarmaydi (eski shakl)', () {
    final j = AiBaholashBundle(
      kadastr: const CadastreLookupResult(cadastreNumber: '10:01:01:01:01:0001'),
      imageKeys: const ['x.jpg'],
    ).toJson();
    expect(j.containsKey('panorama_keys'), isFalse);
    expect(j.containsKey('tour_links'), isFalse);
    expect(j.containsKey('panorama_names'), isFalse);
  });
}
