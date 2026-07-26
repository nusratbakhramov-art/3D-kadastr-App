/// Fetches the appraisal company's legal credentials (license, certificate,
/// insurance, …) shown on the AI Baholash credentials screen before payment.
/// Admin-managed on the backend (`GET /api/v1/appraiser/credentials`, public).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:http/http.dart' as http;

import '../../core/api_config.dart';

/// The service line a document is filed under — a section header on screen.
class CredentialCategory {
  const CredentialCategory({
    required this.slug,
    required this.nameUz,
    this.nameRu,
    this.nameEn,
    this.sortOrder = 0,
  });

  /// Stable key. Behaviour hangs off this, never off the display name, so the
  /// admin can rename or translate a category without breaking the app.
  final String slug;
  final String nameUz;
  final String? nameRu;
  final String? nameEn;
  final int sortOrder;

  /// Valuation documents — the only ones that justify the AI Baholash fee.
  static const String slugAppraiser = 'appraiser';

  /// Home for documents that arrive with no category, which means a backend
  /// older than this feature. The app and the API can never ship in lockstep —
  /// App Store review sees to that — so the screens must survive the window
  /// where the app knows about categories and the server doesn't. Dropping
  /// those documents renders an empty screen while the payload is full of
  /// them; filing them here at least shows the user what they came for.
  static const CredentialCategory other = CredentialCategory(
    slug: '',
    nameUz: 'Boshqa hujjatlar',
    nameRu: 'Другие документы',
    nameEn: 'Other documents',
  );

  String name(String lang) => switch (lang) {
    'ru' => (nameRu?.isNotEmpty ?? false) ? nameRu! : nameUz,
    'en' => (nameEn?.isNotEmpty ?? false) ? nameEn! : nameUz,
    _ => nameUz,
  };

  factory CredentialCategory.fromJson(Map<String, dynamic> j) =>
      CredentialCategory(
        slug: (j['slug'] as String?) ?? '',
        nameUz: (j['name_uz'] as String?) ?? '',
        nameRu: j['name_ru'] as String?,
        nameEn: j['name_en'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  // Value equality on `slug`, and it is load-bearing: every credential parses
  // its OWN category object, so with Dart's default identity equality five
  // Baholovchi documents would group into five separate "Baholovchi" sections.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CredentialCategory && other.slug == slug);

  @override
  int get hashCode => slug.hashCode;
}

class AppraiserCredential {
  const AppraiserCredential({
    required this.title,
    required this.imageUrl,
    this.previewUrl = '',
    this.isPdf = false,
    this.category,
  });

  final String title;

  /// Absolute, device-loadable URL ('' when no file is set yet).
  final String imageUrl;

  /// Absolute URL of a displayable thumbnail: the image itself, or a PDF's
  /// rendered first page. '' when the server hasn't produced one — the card
  /// then falls back to the PDF icon.
  final String previewUrl;

  /// A licence is often issued as a PDF. The server decides this (`kind`)
  /// rather than the app sniffing the URL, and it decides which viewer opens —
  /// handing a PDF to an image widget just renders a broken thumbnail.
  final bool isPdf;

  final CredentialCategory? category;
}

/// Groups documents into on-screen sections, preserving the server's ordering.
///
/// The API already sorts by category then document, so an insertion-ordered
/// map keeps that order without re-sorting — the admin's "Tartib" column stays
/// the single source of truth for sequence.
///
/// Documents with no category are filed under [CredentialCategory.other]
/// rather than skipped: skipping them turns a payload full of documents into a
/// blank screen, and the list is not empty so the empty-state note never fires
/// either.
Map<CredentialCategory, List<AppraiserCredential>> groupCredentialsByCategory(
  List<AppraiserCredential> creds,
) {
  final out = <CredentialCategory, List<AppraiserCredential>>{};
  for (final c in creds) {
    out.putIfAbsent(c.category ?? CredentialCategory.other, () => []).add(c);
  }
  return out;
}

/// Whether grouped sections should carry headers.
///
/// When nothing is categorised there is exactly one implicit group, and heading
/// it "Boshqa hujjatlar" marks it as other than something that isn't on screen
/// — the documents are the appraiser's licence and insurance, not leftovers.
/// The flat, unheaded list the design had before categories is the honest
/// rendering. Headers come back the moment the server files anything.
bool credentialSectionsAreLabelled(
  Map<CredentialCategory, List<AppraiserCredential>> grouped,
) =>
    !(grouped.length == 1 && grouped.keys.single == CredentialCategory.other);

/// The valuation documents, for the AI Baholash pre-payment screen.
///
/// That screen justifies *that* fee, so an architect's or lawyer's certificate
/// has no business on it — adding a document to another service line must not
/// silently change what the user sees before paying.
///
/// A payload carrying no category information at all comes from a backend
/// older than this feature, whose `/credentials` only ever served valuation
/// documents; every row in it is an appraiser credential by definition. Left
/// unhandled, the filter would empty this screen during the window between
/// shipping the app and deploying the API — and this is the one screen where a
/// blank list really costs something, being the trust the user is about to pay
/// on. Once any row is categorised the server is new and the filter is strict
/// again: a half-filed document is excluded, not guessed at.
List<AppraiserCredential> appraiserCredentialsOnly(
  List<AppraiserCredential> all,
) {
  if (all.every((c) => c.category == null)) return all;
  return all
      .where((c) => c.category?.slug == CredentialCategory.slugAppraiser)
      .toList();
}

class AppraiserService {
  AppraiserService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // Session cache — credentials rarely change, so we fetch them once per app
  // process and reuse the result across screen opens (About page, AI Baholash
  // step). Lives only in memory: killing the app clears it, so a fresh launch
  // fetches again. `_inflight` de-dupes concurrent first requests.
  static List<AppraiserCredential>? _cache;
  static Future<List<AppraiserCredential>>? _inflight;

  /// Clears the session cache so the next call re-fetches (e.g. pull-to-refresh
  /// or after an admin update).
  static void invalidateCache() {
    _cache = null;
    _inflight = null;
  }

  void dispose() => _client.close();

  Future<List<AppraiserCredential>> fetchCredentials({
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      // Warm cache → resolve synchronously so FutureBuilder renders instantly
      // (no loading-spinner flash on re-open).
      if (_cache != null) return SynchronousFuture(_cache!);
      if (_inflight != null) return _inflight!;
    }
    final future = _load().then((result) {
      _cache = result; // cache only successful results
      return result;
    });
    _inflight = future;
    future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
    return future;
  }

  Future<List<AppraiserCredential>> _load() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/appraiser/credentials');
    final res = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const [];
    return [
      for (final raw in data)
        if (raw is Map)
          AppraiserCredential(
            title: (raw['title'] as String?) ?? '',
            imageUrl: _resolve((raw['image_url'] as String?) ?? ''),
            previewUrl: _resolve((raw['preview_url'] as String?) ?? ''),
            isPdf: (raw['kind'] as String?) == 'pdf',
            category: raw['category'] is Map
                ? CredentialCategory.fromJson(
                    Map<String, dynamic>.from(raw['category'] as Map),
                  )
                : null,
          ),
    ];
  }

  static String _resolve(String url) =>
      url.isEmpty ? '' : ApiConfig.resolveUrl(url);
}
