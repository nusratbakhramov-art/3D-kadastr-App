import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/api_cadastre_service.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';

/// Draft resume round-trip: a fully-filled bundle must survive
/// toJson() → (server storage) → fromJson() with every step's data intact.
/// This proves the DRAFT persistence itself is lossless — if only the kadastr
/// step comes back on resume, the draft simply never had the later steps saved
/// (each step persists only when you tap "Davom etish"), not a serialization bug.
void main() {
  test('full bundle survives toJson → fromJson (all steps)', () {
    final original = AiBaholashBundle(
      kadastr: const CadastreLookupResult(
        cadastreNumber: '10:09:01:01:02:5942',
        address: 'Toshkent sh., Chilonzor 12',
        objectTypeHint: 'apartment',
        totalArea: 78.5,
        livingArea: 52.0,
        cadastreValue: 1200000000,
      ),
      draftId: 42,
      areaM2: 78.5,
      purpose: ValuationPurpose.mortgage,
      purposeBasis: 'Bank garovi uchun',
      addressee: 'Ipoteka banki',
      floor: 3,
      totalFloors: 9,
      client: const AiClientInfo(
        name: 'Ali Valiyev',
        stir: '12345678901234',
        phone: '998901234567',
        email: 'ali@example.com',
      ),
      location: const AiLocationInfo(
        lat: 41.2995,
        lng: 69.2401,
        addressText: 'Chilonzor 12-uy',
      ),
      imageKeys: const ['img/a.jpg', 'img/b.jpg'],
      kadastrKeys: const ['doc/k.pdf'],
      passportKeys: const ['doc/p.jpg'],
    );

    // Simulate the server: store toJson() and read it back on resume.
    final restored = AiBaholashBundle.fromJson(
      original.toJson(),
      draftId: original.draftId,
    );

    // kadastr
    expect(restored.kadastr.cadastreNumber, '10:09:01:01:02:5942');
    expect(restored.kadastr.address, 'Toshkent sh., Chilonzor 12');
    expect(restored.areaM2, 78.5);
    // client
    expect(restored.client, isNotNull, reason: 'client step lost on resume');
    expect(restored.client!.name, 'Ali Valiyev');
    expect(restored.client!.stir, '12345678901234');
    expect(restored.client!.phone, '998901234567');
    // location
    expect(restored.location, isNotNull, reason: 'location step lost on resume');
    expect(restored.location!.lat, 41.2995);
    expect(restored.location!.lng, 69.2401);
    expect(restored.location!.addressText, 'Chilonzor 12-uy');
    // purpose
    expect(restored.purpose, ValuationPurpose.mortgage);
    expect(restored.purposeBasis, 'Bank garovi uchun');
    expect(restored.addressee, 'Ipoteka banki');
    // intake
    expect(restored.floor, 3);
    expect(restored.totalFloors, 9);
    expect(restored.imageKeys, ['img/a.jpg', 'img/b.jpg']);
    expect(restored.kadastrKeys, ['doc/k.pdf']);
    expect(restored.passportKeys, ['doc/p.jpg']);
  });
}
