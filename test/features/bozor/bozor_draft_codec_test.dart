import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/bozor_resume.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/widgets/pano_ready_banner.dart';
import 'package:kadastr/features/bozor/models/bozor_listing.dart';
import 'package:kadastr/features/bozor/models/parcel_boundary.dart';
import 'package:kadastr/features/bozor/screens/bozor_address_step_screen.dart';
import 'package:kadastr/features/bozor/screens/bozor_params_step_screen.dart';
import 'package:kadastr/features/bozor/screens/bozor_price_step_screen.dart';
import 'package:latlong2/latlong.dart';

/// Qoralama kodeki — yozish (`submit` payload'i) va o'qish (resume) bir xil
/// kalitlarni ishlatishini qotiradi.
///
/// Nega round-trip testi: sehrgar 7 qadamda ~30 maydon to'playdi, ular
/// payload'ga chiqib qaytib keladi. Bitta kalit nomi noto'g'ri bo'lsa
/// foydalanuvchi qoralamaga qaytganda o'sha maydon JIMGINA bo'sh chiqadi —
/// hech qanday xato ko'rinmaydi, shuning uchun faqat test ushlaydi.
BozorDraft _fullDraft() {
  final d = BozorDraft(
    deal: DealType.rent,
    kind: PropertyKind.residential,
    type: PropertyType.apartment,
  );
  d.title = 'Chilonzorda 3 xonali';
  d.address
    ..regionId = 14
    ..regionName = 'Toshkent'
    ..districtId = 141
    ..districtName = 'Chilonzor'
    ..address = 'Chilonzor 5, 12-uy'
    ..landmark = 'Metro yonida'
    ..apartmentNumber = '42'
    ..entrance = '3'
    ..houseNumber = '12'
    ..floor = '5'
    ..totalFloors = '9'
    ..lat = 41.2995
    ..lng = 69.2401
    ..cadastreNumber = '10:09:01:01:02:5942'
    ..boundary = ParcelBoundary.fromRings(const [
      [
        LatLng(41.311081, 69.240562),
        LatLng(41.311081, 69.240800),
        LatLng(41.311300, 69.240800),
      ],
    ]);
  d.params.addAll({
    'rooms_count': '3',
    'total_area': 72.5,
    'repair': 'euro',
    'security': ['guard', 'cctv'],
    'gas': true,
  });
  d.price
    ..amount = '4500000'
    ..unit = 'UZS/oy'
    ..negotiable = false
    ..dailyAmount = '300000'
    ..dailyUnit = 'UZS';
  d.description
    ..text = 'Yorug‘ kvartira'
    ..youtubeUrl = 'https://youtu.be/abc'
    ..photos.addAll(['/data/a.jpg', '/data/b.jpg'])
    ..planFiles.add('/data/plan.pdf')
    ..panoramas.add('/data/360.jpg');
  d.contacts
    ..name = 'Ali'
    ..email = 'ali@example.com';
  d.contacts.phones
    ..clear()
    ..addAll(['901234567', '939998877']);
  d.terms
    ..tier = PlacementTier.top
    ..accepted = true;
  return d;
}

void main() {
  group('draftToDraftPayload → draftFromPayload', () {
    test('to‘liq qoralama round-trip: hamma maydon qaytadi', () {
      final before = _fullDraft();
      final after = draftFromPayload(draftToDraftPayload(before), draftId: 7);

      expect(after.draftId, 7);
      expect(after.deal, DealType.rent);
      expect(after.kind, PropertyKind.residential);
      expect(after.type, PropertyType.apartment);
      expect(after.title, 'Chilonzorda 3 xonali');

      expect(after.address.regionId, 14);
      expect(after.address.districtId, 141);
      expect(after.address.address, 'Chilonzor 5, 12-uy');
      expect(after.address.landmark, 'Metro yonida');
      expect(after.address.apartmentNumber, '42');
      expect(after.address.entrance, '3');
      expect(after.address.houseNumber, '12');
      expect(after.address.floor, '5');
      expect(after.address.totalFloors, '9');
      expect(after.address.lat, closeTo(41.2995, 1e-9));
      expect(after.address.lng, closeTo(69.2401, 1e-9));
      // Geoportaldan tanlangan uchastka — qoralamaga qaytganda u ham
      // tiklanishi kerak, aks holda chegara JIMGINA yo'qolardi.
      expect(after.address.cadastreNumber, '10:09:01:01:02:5942');
      expect(after.address.boundary, isNotNull);
      expect(after.address.boundary!.parts.single, hasLength(3));
      expect(
        after.address.boundary!.parts.single.first.latitude,
        closeTo(41.311081, 1e-9),
      );

      expect(after.params['rooms_count'], '3');
      expect(after.params['total_area'], 72.5);
      expect(after.params['repair'], 'euro');
      expect(after.params['security'], ['guard', 'cctv']);
      expect(after.params['gas'], true);

      expect(after.price.amount, '4500000');
      expect(after.price.unit, 'UZS/oy');
      expect(after.price.negotiable, isFalse);
      expect(after.price.dailyAmount, '300000');
      expect(after.price.dailyUnit, 'UZS');

      expect(after.description.text, 'Yorug‘ kvartira');
      expect(after.description.youtubeUrl, 'https://youtu.be/abc');
      expect(after.description.photos, ['/data/a.jpg', '/data/b.jpg']);
      expect(after.description.planFiles, ['/data/plan.pdf']);
      expect(after.description.panoramas, ['/data/360.jpg']);

      expect(after.contacts.name, 'Ali');
      expect(after.contacts.email, 'ali@example.com');
      expect(after.contacts.phones, ['901234567', '939998877']);

      expect(after.terms.tier, PlacementTier.top);
    });

    test('telefonda saqlangan tushirish (LocalPano) round-trip', () {
      final before = _fullDraft();
      before.description.panoramas.add('local:abc');
      before.description.localPanoramas['local:abc'] = const LocalPano(
        dir: '/x/pano/abc',
        stage: LocalPanoStage.failed,
        error: 'kam kadr',
      );
      final after = draftFromPayload(draftToDraftPayload(before), draftId: 1);
      final lp = after.description.localPanoramas['local:abc'];
      expect(lp, isNotNull);
      expect(lp!.dir, '/x/pano/abc');
      expect(lp.stage, LocalPanoStage.failed);
      expect(lp.error, 'kam kadr');
      expect(after.description.panoramas, contains('local:abc'));
      expect(after.description.isPending('local:abc'), isTrue);
    });

    test('xona nomlari (panoramaNames) round-trip', () {
      final before = _fullDraft();
      before.description.panoramas.add('listings/media/3/p.jpg');
      before.description.panoramaNames['listings/media/3/p.jpg'] = 'Oshxona';
      before.description.panoramaNames['local:x'] = '   '; // bo'sh — tashlanadi
      final after = draftFromPayload(draftToDraftPayload(before), draftId: 1);
      expect(after.description.roomName('listings/media/3/p.jpg'), 'Oshxona');
      expect(after.description.roomName('local:x'), isNull);
      expect(after.description.panoramaNames.containsKey('local:x'), isFalse);
    });

    test('payload IKKI marta o‘girilganda o‘zgarmaydi (barqaror)', () {
      final once = draftToDraftPayload(_fullDraft());
      final twice = draftToDraftPayload(draftFromPayload(once));
      // Rozilik ataylab tiklanmaydi, shuning uchun uni solishtirmaymiz.
      (once['terms'] as Map)['accepted'] = false;
      expect(twice, once);
    });

    test('rozilik TIKLANMAYDI — har yuborishda qaytadan belgilanadi', () {
      final after = draftFromPayload(draftToDraftPayload(_fullDraft()));
      expect(after.terms.accepted, isFalse);
    });
  });

  group('to‘liq bo‘lmagan qoralama', () {
    test('bo‘sh qoralama istisno tashlamaydi va null kodlar yozadi', () {
      final payload = draftToDraftPayload(BozorDraft());
      expect(payload['deal_type'], isNull);
      expect(payload['property_kind'], isNull);
      expect(payload['property_type'], isNull);
      // Server `submit` da bunga 400 beradi — bu KUTILGAN xatti-harakat.
      final back = draftFromPayload(payload);
      expect(back.deal, isNull);
      expect(back.type, isNull);
      expect(back.contacts.phones, ['']); // forma kamida bitta qatorni kutadi
    });

    test('noma‘lum kodlar null bo‘ladi, ilova yiqilmaydi', () {
      final back = draftFromPayload({
        'deal_type': 'barter',
        'property_kind': 'mixed',
        'property_type': 'dacha',
        'terms': {'tier': 'platinum'},
      });
      expect(back.deal, isNull);
      expect(back.kind, isNull);
      expect(back.type, isNull);
      // Tarif — enum, `null` bo‘lolmaydi: xavfsiz sukut qiymati.
      expect(back.terms.tier, PlacementTier.standard);
    });

    test('shakli buzilgan payload istisno tashlamaydi', () {
      // Har bir ichki obyekt kutilganidan BOSHQA turda.
      final back = draftFromPayload({
        'address': 'satr, obyekt emas',
        'params': [1, 2, 3],
        'price': 42,
        'description': null,
        'contacts': {'phones': 'satr, ro‘yxat emas'},
        'terms': [],
        '_local_media': 'satr',
      });
      expect(back.address.address, '');
      expect(back.params, isEmpty);
      expect(back.price.amount, '');
      expect(back.description.photos, isEmpty);
      expect(back.contacts.phones, ['']);
    });
  });

  group('maydon shakllari', () {
    test('butun son matn maydonida 3, «3.0» emas', () {
      final back = draftFromPayload({
        'address': {'floor': 3, 'total_floors': 9.0},
        'price': {'amount': 4500000},
      });
      expect(back.address.floor, '3');
      expect(back.address.totalFloors, '9');
      expect(back.price.amount, '4500000');
    });

    test('kasrli maydon kasrligicha qoladi', () {
      final back = draftFromPayload({
        'price': {'amount': 72.5},
      });
      expect(back.price.amount, '72.5');
    });

    test('narx birligi: valyuta + davr → token', () {
      expect(unitFromCurrency('UZS', 'month'), 'UZS/oy');
      expect(unitFromCurrency('USD', 'month'), 'USD/oy');
      expect(unitFromCurrency('USD', null), 'USD');
      // Teskarisi — `bozor_price_step_screen.dart` dagi qat'iy tokenlar.
      expect(currencyOfUnit('USD/oy'), 'USD');
      expect(periodOfUnit('USD/oy'), 'month');
      expect(periodOfUnit('USD'), isNull);
    });

    test('«savdolashish mumkin» sukut bo‘yicha yoqilgan', () {
      // `PriceDraft.negotiable` sukuti `true`; payload'da maydon yo'q bo'lsa
      // uni `false` ga tushirib qo'ymaslik kerak.
      expect(draftFromPayload(const {}).price.negotiable, isTrue);
      expect(
        draftFromPayload(const {
          'price': {'negotiable': false},
        }).price.negotiable,
        isFalse,
      );
    });
  });

  group('wizardStepFromName', () {
    test('nomlar qadamlarga to‘g‘ri tushadi', () {
      expect(wizardStepFromName('price'), WizardStep.price);
      expect(wizardStepFromName('terms'), WizardStep.terms);
    });

    test('noma‘lum yoki null — 1-qadam', () {
      expect(wizardStepFromName('payment'), WizardStep.type);
      expect(wizardStepFromName(null), WizardStep.type);
    });
  });

  _editTests();

  group('bozorStepScreenSafe — resume', () {
    /// ⚠️ Ekran `PanoReadyBanner` ga O'RALGAN: fonda tikilayotgan panorama
    /// tayyor bo'lganda lenta sehrgarning ISTALGAN qadamida chiqishi kerak,
    /// va har qadam o'z `Scaffold` iga ega bo'lgani uchun o'ram shu yerda.
    /// Test o'ram ICHIGA qaraydi — kafolat o'sha-o'sha: to'g'ri ekran.
    Widget screen(BozorDraft d, WizardStep step) {
      final w = bozorStepScreenSafe(d, step);
      return w is PanoReadyBanner ? w.child : w;
    }

    test('saqlangan qadam ekranga tushadi', () {
      final d = BozorDraft(
        deal: DealType.rent,
        kind: PropertyKind.residential,
        type: PropertyType.apartment,
      );
      expect(screen(d, WizardStep.params), isA<BozorParamsStepScreen>());
      expect(screen(d, WizardStep.price), isA<BozorPriceStepScreen>());
    });

    test('turda YO‘Q qadam — eng yaqin oldingi qadamga tushadi', () {
      // "Boshqa noturar joy" da `params` qadami umuman yo'q. Qoralama o'sha
      // qadamda saqlangan bo'lsa (tur keyin o'zgargan), foydalanuvchi mavjud
      // bo'lmagan ekranga tushib qolmasligi kerak.
      final d = BozorDraft(
        deal: DealType.rent,
        kind: PropertyKind.nonResidential,
        type: PropertyType.otherNonResidential,
      );
      expect(d.wizardSteps.contains(WizardStep.params), isFalse);
      expect(screen(d, WizardStep.params), isA<BozorAddressStepScreen>());
    });
  });
}

/// Tahrirlash (M1-9) — `BozorListing` → `BozorDraft` → `PATCH` tanasi.
///
/// Nega test SHART: konvertor QO'LDA yozilgan ~25 maydonli ko'chirma. Bitta
/// maydon tushib qolsa `PATCH` uni **NULL ga tushirib yuboradi** — ya'ni
/// foydalanuvchi faqat narxni tahrirlab, mo'ljalini yoki qavatini yo'qotadi.
/// Hech qanday xato ko'rinmaydi, faqat test ushlaydi.
BozorListing _listing({
  String status = 'rejected',
  List<BozorListingMedia> media = const [],
}) => BozorListing(
  id: 42,
  statusCode: status,
  title: 'Chilonzorda 3 xonali',
  dealType: 'rent',
  propertyKind: 'residential',
  propertyType: 'apartment',
  address: 'Chilonzor 5, 12-uy',
  priceAmount: 4500000,
  priceCurrency: 'UZS',
  pricePeriod: 'month',
  negotiable: false,
  contactName: 'Ali',
  contactPhone: '901234567',
  contactPhones: const ['901234567', '939998877'],
  contactEmail: 'ali@example.com',
  createdAt: DateTime.utc(2026, 9, 10),
  regionId: 7,
  regionName: 'Toshkent shahri',
  districtId: 8,
  districtName: 'Chilonzor',
  landmark: 'Metro yonida',
  apartmentNumber: '42',
  entrance: '3',
  floor: 5,
  totalFloors: 9,
  latitude: 41.2995,
  longitude: 69.2401,
  rooms: 3,
  areaSqm: 72.5,
  params: const {'rooms_count': '3', 'total_area': 72.5, 'renovation': 'euro'},
  description: 'Yorugʻ kvartira',
  youtubeUrl: 'https://youtu.be/abc',
  media: media,
);

void _editTests() {
  group('draftFromListing', () {
    test('hamma maydon qoralamaga ko‘chadi', () {
      final d = draftFromListing(_listing());
      expect(d.editingListingId, 42);
      expect(d.isEditing, isTrue);
      expect(d.draftId, isNull); // tahrirlash qoralamadan boshlanmaydi
      expect(d.deal, DealType.rent);
      expect(d.type, PropertyType.apartment);
      expect(d.title, 'Chilonzorda 3 xonali');
      expect(d.address.regionId, 7);
      expect(d.address.districtId, 8);
      expect(d.address.landmark, 'Metro yonida');
      expect(d.address.apartmentNumber, '42');
      expect(d.address.entrance, '3');
      expect(d.address.floor, '5');
      expect(d.address.totalFloors, '9');
      expect(d.address.lat, closeTo(41.2995, 1e-9));
      expect(d.params['renovation'], 'euro');
      expect(d.price.amount, '4500000');
      expect(d.price.unit, 'UZS/oy');
      expect(d.price.negotiable, isFalse);
      expect(d.description.text, 'Yorugʻ kvartira');
      expect(d.description.youtubeUrl, 'https://youtu.be/abc');
      expect(d.contacts.name, 'Ali');
      expect(d.contacts.email, 'ali@example.com');
      expect(d.contacts.phones, ['901234567', '939998877']);
      // Rozilik tahrirlashda ham qaytadan belgilanadi (Z5).
      expect(d.terms.accepted, isFalse);
    });

    test('mavjud fayllar KALIT bilan olinadi', () {
      final d = draftFromListing(
        _listing(
          media: const [
            BozorListingMedia(
              id: 1,
              role: 'photo',
              storageKey: 'listings/media/3/a.jpg',
              url: 'http://x/a.jpg',
              isCover: true,
              sortOrder: 0,
            ),
            // Kalitsiz (bayroqdan oldingi server) — ro'yxatga QO'SHILMAYDI:
            // bo'sh kalit yuborilsa server 400 berardi.
            BozorListingMedia(
              id: 2,
              role: 'photo',
              storageKey: '',
              url: 'http://x/b.jpg',
            ),
          ],
        ),
      );
      expect(d.description.existingMedia.length, 1);
      expect(d.description.existingMedia.first.key, 'listings/media/3/a.jpg');
      expect(d.description.existingMedia.first.isCover, isTrue);
    });
  });

  group('draftToUpdatePayload', () {
    test('mulk turi YUBORILMAYDI — `ListingUpdateRequest` da u yo‘q', () {
      final p = draftToUpdatePayload(draftFromListing(_listing()), const []);
      expect(p.containsKey('deal_type'), isFalse);
      expect(p.containsKey('property_kind'), isFalse);
      expect(p.containsKey('property_type'), isFalse);
      expect(p.containsKey('terms'), isFalse);
      // Qolgan bo'limlar joyida.
      expect(
        p.keys,
        containsAll(<String>[
          'title',
          'address',
          'params',
          'price',
          'description',
          'contacts',
        ]),
      );
    });

    test('media bo‘sh bo‘lsa `media` kaliti UMUMAN yuborilmaydi', () {
      // Bu MUHIM: bo'sh ro'yxat server uchun "hamma rasmni o'chir" degani.
      final p = draftToUpdatePayload(draftFromListing(_listing()), const []);
      final d = p['description'] as Map;
      expect(d.containsKey('media'), isFalse);
      expect(d['text'], 'Yorugʻ kvartira');
    });

    test('media berilsa `media` yuboriladi', () {
      final p = draftToUpdatePayload(draftFromListing(_listing()), const [
        {
          'key': 'listings/media/3/a.jpg',
          'role': 'photo',
          'sort_order': 0,
          'is_cover': true,
        },
      ]);
      final d = p['description'] as Map;
      expect((d['media'] as List).length, 1);
    });
  });
}
