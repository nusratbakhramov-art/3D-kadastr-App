import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/tour_native.dart';
import 'package:kadastr/features/bozor/models/tour_link.dart';
import 'package:kadastr/features/panorama/data/pano_capture_channel.dart';

/// Nativ tur ↔ Dart `TourLink` konvertatsiyasi va «Yangi xona» havola qoidasi.
void main() {
  const a = 'listings/media/3/a.jpg';
  const b = 'listings/media/3/b.jpg';

  group('kanal konvertatsiyasi', () {
    test('to → from aynan qaytadi (label bilan va label\'siz)', () {
      final links = <TourLink>[
        const TourLink(
          from: a,
          to: b,
          yawDeg: 250.5,
          pitchDeg: -3,
          label: 'Oshxona',
        ),
        const TourLink(from: b, to: a, yawDeg: 70.5, pitchDeg: 0),
      ];
      final back = tourLinksFromChannel(tourLinksToChannel(links));
      expect(back, links);
      // Kanal kalitlari camelCase — JSON `yaw_deg` bilan ADASHMASIN.
      final m = tourLinkToChannel(links.first);
      expect(
        m.keys,
        containsAll(<String>['from', 'to', 'yawDeg', 'pitchDeg', 'label']),
      );
      expect(m.containsKey('yaw_deg'), isFalse);
      expect(tourLinkToChannel(links.last).containsKey('label'), isFalse);
    });

    test('bo\'sh from/to tashlanadi, bo\'sh label null', () {
      final got = tourLinksFromChannel(<Map<String, Object?>>[
        <String, Object?>{'from': a, 'to': '', 'yawDeg': 1, 'pitchDeg': 1},
        <String, Object?>{
          'from': a,
          'to': b,
          'yawDeg': 1,
          'pitchDeg': 1,
          'label': '  ',
        },
      ]);
      expect(got, hasLength(1));
      expect(got.single.label, isNull);
    });

    test('PanoTourResult — newRoom amali o\'qiladi', () {
      final r = PanoTourResult.fromChannel(<Object?, Object?>{
        'links': <Object?>[
          <Object?, Object?>{
            'from': a,
            'to': b,
            'yawDeg': 10.0,
            'pitchDeg': 2.0,
          },
        ],
        'action': <Object?, Object?>{
          'type': 'newRoom',
          'fromKey': a,
          'yawDeg': 300.0,
          'pitchDeg': -5.0,
        },
      });
      expect(r.links, hasLength(1));
      expect(r.newRoom, isNotNull);
      expect(r.newRoom!.fromKey, a);
      expect(r.newRoom!.yawDeg, 300);
      expect(
        PanoTourResult.fromChannel(<Object?, Object?>{
          'links': <Object?>[],
        }).newRoom,
        isNull,
      );
    });
  });

  group('mergeNewRoomLinks', () {
    const action = PanoTourNewRoom(fromKey: a, yawDeg: 300, pitchDeg: -5);
    const c = 'listings/media/3/c.jpg';

    test("to'g'ri havola bosilgan joyda, teskarisi qarama-qarshi tomonda", () {
      final out = mergeNewRoomLinks(const <TourLink>[], action, c);
      expect(out, hasLength(2));
      final fwd = out.firstWhere((l) => l.from == a);
      final back = out.firstWhere((l) => l.from == c);
      expect(fwd.to, c);
      expect(fwd.yawDeg, 300);
      expect(fwd.pitchDeg, -5);
      expect(back.to, a);
      expect(back.yawDeg, 120); // 300 + 180 mod 360
      expect(back.pitchDeg, 0);
    });

    test('mavjud havolalar saqlanadi, takror qo\'shilmaydi', () {
      final existing = <TourLink>[
        const TourLink(from: a, to: b, yawDeg: 10, pitchDeg: 0),
        const TourLink(from: a, to: c, yawDeg: 90, pitchDeg: 0),
      ];
      final out = mergeNewRoomLinks(existing, action, c);
      expect(out.where((l) => l.from == a && l.to == c), hasLength(1));
      expect(out.where((l) => l.from == c && l.to == a), hasLength(1));
      expect(out.first, existing.first);
    });

    test(
      'chegara: 8 ta bo\'lsa o\'sha tomon qo\'shilmaydi, teskarisi qo\'shiladi',
      () {
        final full = <TourLink>[
          for (var i = 0; i < kMaxTourLinksPerPanorama; i++)
            TourLink(from: a, to: 'k$i', yawDeg: i * 10.0, pitchDeg: 0),
        ];
        final out = mergeNewRoomLinks(full, action, c);
        expect(
          out.where((l) => l.from == a),
          hasLength(kMaxTourLinksPerPanorama),
        );
        expect(out.where((l) => l.from == c && l.to == a), hasLength(1));
      },
    );
  });
}
