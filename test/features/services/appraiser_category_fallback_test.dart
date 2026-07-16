/// Version skew: the app and the API cannot deploy in lockstep, so both
/// credential screens have to survive a backend older than categories. These
/// pin that, using the exact payload api.3dkadastr.uz serves today.
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/services/api_appraiser_service.dart';

/// The live pre-categories response: no `category`, no `kind`.
const _oldBackendJson = '''
[{"id":1,"title":"Litsenziya","image_url":"/static/a/01.png","sort_order":0},
 {"id":2,"title":"Sug'urta polisi","image_url":"/static/a/05.png","sort_order":4}]
''';

/// A categories-aware response.
const _newBackendJson = '''
[{"id":1,"title":"Litsenziya","image_url":"/static/a/01.png","kind":"image",
  "category":{"slug":"appraiser","name_uz":"Baholovchi","sort_order":10}},
 {"id":9,"title":"Yuridik guvohnoma","image_url":"/static/a/09.png","kind":"image",
  "category":{"slug":"legal","name_uz":"Yuridik xizmat","sort_order":30}}]
''';

AppraiserService _serviceReturning(String body) {
  return AppraiserService(
    client: MockClient(
      (_) async => http.Response(body, 200, headers: {
        'content-type': 'application/json; charset=utf-8',
      }),
    ),
  );
}

void main() {
  setUp(AppraiserService.invalidateCache);
  tearDown(AppraiserService.invalidateCache);

  group('parsing', () {
    test('an old payload yields documents with no category', () async {
      final creds = await _serviceReturning(_oldBackendJson).fetchCredentials();

      expect(creds, hasLength(2));
      expect(creds.every((c) => c.category == null), isTrue);
    });

    test('a new payload carries the category through', () async {
      final creds = await _serviceReturning(_newBackendJson).fetchCredentials();

      expect(creds.first.category?.slug, 'appraiser');
      expect(creds.last.category?.slug, 'legal');
    });
  });

  group('About — grouping', () {
    // The bug this replaces: uncategorised rows were skipped, so a full
    // payload rendered a blank screen and the empty-state note never fired
    // because the list itself was not empty.
    test('files uncategorised documents under a fallback instead of '
        'dropping them', () async {
      final creds = await _serviceReturning(_oldBackendJson).fetchCredentials();

      final grouped = groupCredentialsByCategory(creds);

      expect(grouped, hasLength(1));
      expect(grouped.keys.single, CredentialCategory.other);
      expect(grouped.values.single, hasLength(2));
    });

    test('groups a categorised payload one section per category', () async {
      final creds = await _serviceReturning(_newBackendJson).fetchCredentials();

      final grouped = groupCredentialsByCategory(creds);

      expect(grouped.keys.map((c) => c.slug), ['appraiser', 'legal']);
      expect(grouped.values.every((v) => v.length == 1), isTrue);
    });

    // Every credential parses its own category object, so identity equality
    // would open one section per document.
    test('same-slug documents collapse into one section', () async {
      final creds = await _serviceReturning('''
        [{"id":1,"title":"A","image_url":"/a.png",
          "category":{"slug":"appraiser","name_uz":"Baholovchi"}},
         {"id":2,"title":"B","image_url":"/b.png",
          "category":{"slug":"appraiser","name_uz":"Baholovchi"}}]
      ''').fetchCredentials();

      final grouped = groupCredentialsByCategory(creds);

      expect(grouped, hasLength(1));
      expect(grouped.values.single, hasLength(2));
    });

    test('the fallback category is named in all three locales', () {
      expect(CredentialCategory.other.name('uz'), "Boshqa hujjatlar");
      expect(CredentialCategory.other.name('ru'), 'Другие документы');
      expect(CredentialCategory.other.name('en'), 'Other documents');
    });
  });

  group('AI Baholash — pre-payment filter', () {
    test('an old payload shows every document rather than nothing', () async {
      final creds = await _serviceReturning(_oldBackendJson).fetchCredentials();

      expect(appraiserCredentialsOnly(creds), hasLength(2));
    });

    test('a new payload is filtered strictly to appraiser', () async {
      final creds = await _serviceReturning(_newBackendJson).fetchCredentials();

      final shown = appraiserCredentialsOnly(creds);

      expect(shown, hasLength(1));
      expect(shown.single.title, 'Litsenziya');
    });

    // Fail closed: once the server is categories-aware, a document that was
    // never filed must not be passed off as a valuation credential.
    test('a half-filed payload excludes the uncategorised document', () async {
      final creds = await _serviceReturning('''
        [{"id":1,"title":"Litsenziya","image_url":"/a.png",
          "category":{"slug":"appraiser","name_uz":"Baholovchi"}},
         {"id":2,"title":"Nomalum","image_url":"/b.png"}]
      ''').fetchCredentials();

      final shown = appraiserCredentialsOnly(creds);

      expect(shown.map((c) => c.title), ['Litsenziya']);
    });
  });

  test('kind drives the viewer choice, not the URL', () async {
    final creds = await _serviceReturning('''
      [{"id":1,"title":"Litsenziya","image_url":"/a/licence.pdf","kind":"pdf"},
       {"id":2,"title":"Polis","image_url":"/a/policy.png","kind":"image"}]
    ''').fetchCredentials();

    expect(creds.first.isPdf, isTrue);
    expect(creds.last.isPdf, isFalse);
  });
}
