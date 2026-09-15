// The one rule that decides both what the user sees and what we log.
//
// davreestr never answers "not found" with an error. A rejected search form
// (it replies `302 → /uz`) and a parser that no longer matches the site's
// markup BOTH come back as a result whose every field is empty. So
// `hasUsableData` is what separates "here is your property" from
// "Ma'lumot olib bo'lmadi" — and, since the client only reports a failure when
// the lookup delivered nothing, it is also what separates a logged failure
// from silence.
//
// Get it wrong in one direction and the admin Logs page stays empty while
// users complain; wrong in the other and every successful lookup files a
// failure report.
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/data/davreestr_client.dart';

void main() {
  group('DavreestrLookupResult.hasUsableData', () {
    test('all-empty result is NOT usable — this is the 302 / stale-parser case',
        () {
      const result = DavreestrLookupResult(
        cadastreNumber: '10:10:41:05:02:0200',
      );
      expect(result.hasUsableData, isFalse);
    });

    test('any one populated field is enough', () {
      const number = '10:10:41:05:02:0200';
      expect(
        const DavreestrLookupResult(
          cadastreNumber: number,
          address: 'Toshkent sh., Chilonzor t.',
        ).hasUsableData,
        isTrue,
      );
      expect(
        const DavreestrLookupResult(cadastreNumber: number, totalArea: 92.4)
            .hasUsableData,
        isTrue,
      );
      expect(
        const DavreestrLookupResult(cadastreNumber: number, livingArea: 61.0)
            .hasUsableData,
        isTrue,
      );
      expect(
        const DavreestrLookupResult(
          cadastreNumber: number,
          cadastreValue: 412000000,
        ).hasUsableData,
        isTrue,
      );
      expect(
        const DavreestrLookupResult(
          cadastreNumber: number,
          objectTypeHint: 'Turar joy',
        ).hasUsableData,
        isTrue,
      );
    });

    test('whitespace-only text does not count as data', () {
      // The parser strips tags and collapses whitespace, so a matched-but-empty
      // cell arrives as "" or " " rather than null. Treating that as data would
      // let the wizard continue with a blank address.
      const result = DavreestrLookupResult(
        cadastreNumber: '10:10:41:05:02:0200',
        address: '   ',
        objectTypeHint: '',
      );
      expect(result.hasUsableData, isFalse);
    });

    test('the cadastre number alone is not data', () {
      // It was typed by the user (or picked off the map) — it says nothing
      // about whether the registry answered.
      const result = DavreestrLookupResult(cadastreNumber: '10:10:41:05:02:0200');
      expect(result.hasUsableData, isFalse);
    });

    test('a zero area still counts — 0 is an answer, absence is not', () {
      const result = DavreestrLookupResult(
        cadastreNumber: '10:10:41:05:02:0200',
        totalArea: 0,
      );
      expect(result.hasUsableData, isTrue);
    });
  });
}
