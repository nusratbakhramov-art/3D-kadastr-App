/// On-device port of `app/integrations/davreestr.py`.
///
/// The backend used to scrape davreestr.uz, but its single IP got rate-limited.
/// We now run the scrape from each user's phone — distributed source IPs,
/// no rate limit. The only thing the backend still owns is captcha OCR, which
/// runs via [POST /api/v1/davreestr/solve-captcha].
///
/// Flow (mirrors the Python original):
///   1. GET  /uz                         → session cookie + Laravel `_token`
///   2. GET  /captcha/default            → captcha PNG bytes
///   3. POST [backend]/davreestr/solve-captcha (multipart) → 4-digit code
///   4. POST /data/get-info/search       → result HTML
///   5. Parse HTML for address / total_area / living_area / cadastre_value
///
/// Wrong captcha → loop up to [maxCaptchaRetries] times.
///
/// ## Failure reporting
///
/// Because all of the above runs on the phone, a failure used to be rendered
/// on screen and thrown away — the backend saw nothing, and support got
/// "Ma'lumot olib bo'lmadi" screenshots with no way to tell a wrong captcha
/// from a rejected form from a stale parser. So every failed attempt of a
/// lookup is collected (stage, request, response, status, timing) and, IF the
/// lookup ends without usable data, POSTed to
/// [POST /api/v1/davreestr/logs]. The admin panel shows it under
/// "Loglar → Davreestr xatolari", per user.
///
/// A lookup that recovers on a later captcha retry reports NOTHING: the user
/// got their data, so there is nothing to investigate. Reporting is
/// fire-and-forget — it can never fail or delay the lookup it is describing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../../core/app_version.dart';
import '../../auth/auth_http_client.dart';

/// One davreestr.uz response — status and headers included.
///
/// The helpers used to return just the body, which is why a `302` (how
/// davreestr answers a REJECTED search form) was indistinguishable from a
/// real result page. Now the status travels with the body so it can be both
/// classified and logged.
class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;

  bool get isRedirect => statusCode >= 300 && statusCode < 400;
}

/// Failure kinds — must match `DavreestrErrorKind` in the backend
/// (`app/models/davreestr_log.py`). Unknown values are still accepted there,
/// so a new one can ship from the app first.
class _Kind {
  static const httpRedirect = 'http_redirect';
  static const httpError = 'http_error';
  static const captchaWrong = 'captcha_wrong';
  static const ocrFailed = 'ocr_failed';
  static const rateLimited = 'rate_limited';
  static const notFound = 'not_found';
  static const parseEmpty = 'parse_empty';
  static const csrfMissing = 'csrf_missing';
  static const network = 'network';
  static const timeout = 'timeout';
  static const captchaExhausted = 'captcha_exhausted';
  static const unknown = 'unknown';
}

/// The 5 pipeline steps — matches `DavreestrLogStage` in the backend.
class _Stage {
  static const home = 'home';
  static const captchaImage = 'captcha_image';
  static const captchaOcr = 'captcha_ocr';
  static const search = 'search';
  static const parse = 'parse';
}

/// Everything that went wrong during ONE lookup, held until we know whether
/// the lookup as a whole failed.
class _FailureReport {
  _FailureReport(this.cadastreNumber);

  final String cadastreNumber;

  /// Ties every attempt of this lookup together, so the admin panel shows one
  /// story ("burned 8 captchas, then gave up") instead of 8 unrelated rows.
  final String correlationId = _newCorrelationId();

  final List<Map<String, dynamic>> entries = [];

  /// The backend rejects a batch over 20 (`DavreestrLogReport`). A lookup can
  /// legitimately produce 17 (1 home + 8 OCR + 8 search), so this only bites
  /// on something pathological — and then the first 20 are the useful ones.
  static const _maxEntries = 20;

  /// davreestr's own pages run to 65 KB and say nothing new; the interesting
  /// bodies (the 302 stub, an error alert) are a few hundred bytes. The
  /// backend clips to 8 KB anyway, so send that much and no more.
  static const _maxBody = 8000;

  static String _newCorrelationId() {
    final rnd = Random.secure();
    return List.generate(
      16,
      (_) => rnd.nextInt(16).toRadixString(16),
    ).join();
  }

  static String? _clip(String? text) {
    if (text == null || text.isEmpty) return null;
    return text.length <= _maxBody ? text : text.substring(0, _maxBody);
  }

  /// The form body with the CSRF token stripped. The backend redacts it too,
  /// but there is no reason to put a session token on the wire at all. The
  /// captcha CODE is deliberately kept — "which digits did OCR read" is the
  /// single most useful field here.
  static String? _redact(String? body) => body?.replaceAll(
        RegExp(r'(_token=)[^&]*'),
        r'$1<redacted>',
      );

  void add({
    required String stage,
    required String kind,
    String? message,
    int? attempt,
    String? method,
    String? url,
    Map<String, String>? requestHeaders,
    String? requestBody,
    int? status,
    Map<String, String>? responseHeaders,
    String? responseBody,
    int? durationMs,
  }) {
    if (entries.length >= _maxEntries) return;
    final entry = <String, dynamic>{
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'mobile',
      'stage': stage,
      'error_kind': kind,
      'cadastre_number': cadastreNumber,
      'correlation_id': correlationId,
      // Hand-maintained constants (`lib/core/app_version.dart`), guarded
      // against pubspec by `test/core/app_version_test.dart`. If that test is
      // red, this field ships a stale version and "which release broke it"
      // stops being answerable — it is red as of this commit (1.0.4+27 vs
      // pubspec 1.0.5+37), which is a two-line fix of its own.
      'app_version': '$kAppVersion+$kAppBuild',
      'platform': Platform.isIOS ? 'ios' : 'android',
      'device_info': Platform.operatingSystemVersion,
    };
    // Omitted rather than sent as null — the backend leaves absent fields
    // NULL, and a payload of explicit nulls only makes the log harder to read.
    void put(String key, Object? value) {
      if (value != null) entry[key] = value;
    }

    put('error_message', message);
    put('attempt', attempt);
    put('request_method', method);
    put('request_url', url);
    put('request_headers', requestHeaders);
    put('request_body', _redact(_clip(requestBody)));
    put('response_status', status);
    put('response_headers', responseHeaders);
    put('response_body', _clip(responseBody));
    put('duration_ms', durationMs);
    entries.add(entry);
  }
}

/// Bitta ta'qiq/cheklov yozuvi — davreestr natija sahifasidagi `ban-table`
/// jadvalining bir qatori.
///
/// Hamma maydon matn: reyestr ularni erkin shaklda chiqaradi (sana `19.12.2025`
/// ko'rinishida, tur esa ba'zan ruscha — `Ограничение`, `Письмо`). Bu yerda
/// ular AYNAN reyestrdagidek saqlanadi va ekranda ham shundayligicha
/// ko'rsatiladi: tarjima yoki normallashtirish yuridik ma'noni o'zgartirib
/// yuborishi mumkin.
class DavreestrRestriction {
  const DavreestrRestriction({
    this.number = '',
    this.kind = '',
    this.authority = '',
    this.date = '',
    this.documentNumber = '',
    this.exchangeCode = '',
  });

  /// "Taqiq/cheklov raqami" — masalan `T6-1009-25-30048`.
  final String number;

  /// "Taqiq/cheklov turi" — masalan `Ограничение`, `Письмо`.
  final String kind;

  /// "Kim tomonidan" — masalan `Ген ПРОКУРАТУРА`, `Банк_запретов`.
  final String authority;

  /// "Sana" — `19.12.2025` ko'rinishida.
  final String date;

  /// "Ijro xujjatining raqami".
  final String documentNumber;

  /// "Ma'lumot almashuv orqali qo'yilganligi (almashuv kodi)" — ko'pincha bo'sh.
  final String exchangeCode;

  bool get isEmpty =>
      number.isEmpty &&
      kind.isEmpty &&
      authority.isEmpty &&
      date.isEmpty &&
      documentNumber.isEmpty &&
      exchangeCode.isEmpty;
}

/// Successful davreestr.uz lookup. Shape matches the existing
/// `CadastreLookupResult` so the rest of the app needs no changes.
class DavreestrLookupResult {
  const DavreestrLookupResult({
    required this.cadastreNumber,
    this.address,
    this.objectTypeHint,
    this.totalArea,
    this.livingArea,
    this.landArea,
    this.cadastreValue,
    this.hasRestrictions,
    this.restrictions = const [],
  });

  final String cadastreNumber;
  final String? address;
  final String? objectTypeHint;
  final double? totalArea;
  final double? livingArea;

  /// Yer uchastkasining maydoni (m²) — "Hujjat bo'yicha umumiy yer maydoni".
  ///
  /// Faqat YERI BOR obyektlarda bo'ladi (yakka tartibdagi uy, uchastka);
  /// ko'p qavatli uydagi xonadonda reyestr bu qatorni chizmaydi va bu yerda
  /// `null` qoladi. [totalArea] dan alohida: u BINONING foydali maydoni.
  final double? landArea;

  final double? cadastreValue;

  /// Obyektga ta'qiq/cheklov qo'yilganmi.
  ///
  /// * `true`  — natija sahifasida "Obyektga nisbatan ta'qiq va cheklovlar"
  ///   qatori bor (va odatda [restrictions] ham to'lgan);
  /// * `false` — obyekt topildi, lekin o'sha qator YO'Q. Reyestr toza
  ///   obyektda bu qatorni umuman chizmaydi, ya'ni yo'qligi = "taqiq yo'q";
  /// * `null`  — noma'lum. Backend keshidan kelgan javob shunday: kesh bu
  ///   maydonni saqlamaydi, ta'qiq esa bugun qo'yilib ertaga olinadi —
  ///   eskirgan "toza" javobni ko'rsatgandan ko'ra bilmaslikni tan olgan
  ///   ma'qul. Ta'qiqni tekshirish ekrani shu sababli HAR DOIM
  ///   `forceRefresh: true` bilan so'raydi.
  final bool? hasRestrictions;

  /// Ta'qiq yozuvlari — [hasRestrictions] `true` bo'lganda to'ladi.
  final List<DavreestrRestriction> restrictions;

  /// Did the registry actually give us something the wizard can use?
  ///
  /// davreestr does not answer "not found" with an error — a rejected form or
  /// a stale parser both come back as a result with every field empty. So this
  /// is the test that decides whether the user sees data or
  /// "Ma'lumot olib bo'lmadi", and therefore also whether the lookup reports
  /// itself as failed (`lookup`'s `finally`). The two must never disagree.
  ///
  /// `ai_cadastre_screen.dart` and `cadastre_lookup_field.dart` apply the same
  /// rule to their own `CadastreLookupResult`; keep them in step.
  bool get hasUsableData =>
      (address?.trim().isNotEmpty ?? false) ||
      totalArea != null ||
      livingArea != null ||
      cadastreValue != null ||
      (objectTypeHint?.trim().isNotEmpty ?? false);
}

/// Thrown for every recoverable failure: rate limit, not-found, captcha
/// exhausted, network. `statusCode` populated when the cause was an HTTP
/// non-2xx from davreestr.uz; left null for client-side failures.
class DavreestrLookupException implements Exception {
  const DavreestrLookupException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'DavreestrLookupException: $message';
}

class DavreestrClient {
  DavreestrClient({
    required this.backendBaseUrl,
    required this.authToken,
    String? davreestrBaseUrl,
    http.Client? backendClient,
  })  : davreestrBaseUrl =
            (davreestrBaseUrl ?? 'https://davreestr.uz').replaceAll(
          RegExp(r'/+$'),
          '',
        ),
        _injectedClient = backendClient,
        _backendClient = backendClient ?? AuthHttpClient();

  /// Backend root (e.g. `https://api.3dkadastr.uz/api/v1`) — used only for
  /// the captcha-solve call.
  final String backendBaseUrl;

  /// User's session bearer token — captcha-solve endpoint is auth-gated.
  final String authToken;

  final String davreestrBaseUrl;

  /// Backend OCR client (multipart upload). Davreestr itself uses a raw
  /// `dart:io` HttpClient below because we need fine-grained cookie control.
  final http.Client _backendClient;

  /// The caller-supplied client, or null when we made our own. Only the
  /// failure reporter needs to tell the difference — see [_reportFailure].
  final http.Client? _injectedClient;

  /// Backend OCR accuracy is ~70% — at 8 tries the success probability is
  /// ~99.94 %. Matches the Python original.
  static const int maxCaptchaRetries = 8;

  static const Duration _timeout = Duration(seconds: 30);

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  // Error-detection patterns lifted verbatim from davreestr.py. Order
  // matters here: a "topilmadi" + success-hint combo means the record was
  // found but a sub-section is empty, not that the record is missing.
  static const _captchaWrongPatterns = ['maxfiy kod noto'];
  static const _rateLimitPatterns = [
    "bazaga so'rovlar soni oshib",
    'rate limit',
  ];
  static const _notFoundPatterns = ['topilmadi', "ma'lumot yo'q", 'no record'];
  static const _successHintPatterns = [
    'manzil:',
    'umumiy maydon',
    'kadastr qiymati',
    'obyekt turi:',
  ];

  /// A rejected search must be RETRIED with a fresh captcha.
  ///
  /// ⚠️ NEGA ALOHIDA VA SOF. davreestr rad etishni `302 → /uz` bilan
  /// qaytaradi va sababini KEYINGI sahifa yuklanishiga flash qiladi. Agar
  /// o'sha sahifada ham sabab bo'lmasa, bizda hech qanday belgi qolmaydi —
  /// va ilgari aynan shunda urinish bekorga sarflanardi: captcha xato
  /// bo'lsa ham sikl qayta urinmasdi.
  ///
  /// Qoida: 302 kelgan, lekin TANIB BO'LADIGAN sabab topilmagan bo'lsa —
  /// captcha deb hisoblab qayta uriniladi. Tanilgan sabab (rate limit,
  /// topilmadi, ochiq «maxfiy kod noto») o'z shoxiga ketadi va bu yerga
  /// tushmaydi.
  @visibleForTesting
  static bool shouldRetryRejected({
    required bool isRedirect,
    required String bodyLower,
  }) =>
      isRedirect &&
      !_anyContains(bodyLower, _rateLimitPatterns) &&
      !_anyContains(bodyLower, _captchaWrongPatterns) &&
      !_anyContains(bodyLower, _notFoundPatterns);

  /// Resolve a cadastre number to property data.
  ///
  /// Fast path: the backend cache (`GET /davreestr/lookup`) — a prior
  /// successful lookup by ANY user means we skip the slow captcha/OCR/scrape
  /// entirely. On a miss (or [forceRefresh]) we scrape on-device and upload
  /// the result so the next lookup is instant.
  Future<DavreestrLookupResult> lookup(
    String cadastreNumber, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _fetchCached(cadastreNumber);
      if (cached != null) return cached;
    }

    final httpClient = HttpClient()
      ..connectionTimeout = _timeout
      ..idleTimeout = _timeout;

    // Manual cookie jar — dart:io's HttpClient doesn't persist cookies
    // across requests by default, and Laravel session cookies (XSRF-TOKEN,
    // laravel_session) are critical for the form POST to succeed.
    final cookies = <String, String>{};

    // Everything that goes wrong is collected here and sent to the backend in
    // the `finally` below — but ONLY if this lookup ends without usable data.
    final report = _FailureReport(cadastreNumber);
    var delivered = false;
    // Which step we are on, so a network error or a timeout — which surface at
    // the bottom of this method, far from where they happened — are still
    // logged against the request that actually hung.
    var stage = _Stage.home;
    var attemptNo = 0;

    try {
      // 1) Home page — collect cookies + CSRF token.
      final homeUri = Uri.parse('$davreestrBaseUrl/uz');
      final homeStarted = DateTime.now();
      final _HttpResult home;
      try {
        home = await _get(httpClient, homeUri, cookies);
      } on DavreestrLookupException catch (e) {
        report.add(
          stage: _Stage.home,
          kind: _Kind.httpError,
          message: e.message,
          method: 'GET',
          url: homeUri.toString(),
          status: e.statusCode,
          durationMs: _elapsed(homeStarted),
        );
        rethrow;
      }
      var token = _extractCsrf(home.body);
      if (token == null) {
        // Either the site changed its markup or this is not the page we think
        // it is. The body is the only evidence, so it goes into the log.
        report.add(
          stage: _Stage.home,
          kind: _Kind.csrfMissing,
          message: 'davreestr.uz: CSRF token topilmadi',
          method: 'GET',
          url: homeUri.toString(),
          status: home.statusCode,
          responseBody: home.body,
          durationMs: _elapsed(homeStarted),
        );
        throw const DavreestrLookupException(
          'davreestr.uz: CSRF token topilmadi',
        );
      }

      String? lastError;

      for (var attempt = 1; attempt <= maxCaptchaRetries; attempt++) {
        attemptNo = attempt;
        // 2) Captcha PNG — session-bound, single-use.
        stage = _Stage.captchaImage;
        final captchaUri = Uri.parse('$davreestrBaseUrl/captcha/default');
        final Uint8List captchaBytes;
        try {
          captchaBytes = await _getBytes(httpClient, captchaUri, cookies);
        } on DavreestrLookupException catch (e) {
          report.add(
            stage: _Stage.captchaImage,
            kind: _Kind.httpError,
            message: e.message,
            attempt: attempt,
            method: 'GET',
            url: captchaUri.toString(),
            status: e.statusCode,
          );
          rethrow;
        }

        // 3) Solve via backend OCR.
        stage = _Stage.captchaOcr;
        final ocrStarted = DateTime.now();
        final String? code;
        try {
          code = await _solveCaptcha(captchaBytes);
        } on DavreestrLookupException catch (e) {
          report.add(
            stage: _Stage.captchaOcr,
            kind: _Kind.httpError,
            message: e.message,
            attempt: attempt,
            method: 'POST',
            url: '$_backendRoot/davreestr/solve-captcha',
            status: e.statusCode,
            durationMs: _elapsed(ocrStarted),
          );
          rethrow;
        }
        if (code == null) {
          // OCR fail — server picks a fresh captcha image, try again. Recorded
          // but only ever SENT if the whole lookup goes on to fail: on its own
          // an OCR miss costs the user nothing.
          report.add(
            stage: _Stage.captchaOcr,
            kind: _Kind.ocrFailed,
            message: "OCR captcha raqamlarini o'qiy olmadi",
            attempt: attempt,
            method: 'POST',
            url: '$_backendRoot/davreestr/solve-captcha',
            requestBody: 'captcha PNG, ${captchaBytes.length} bayt',
            durationMs: _elapsed(ocrStarted),
          );
          continue;
        }

        // 4) Submit search form.
        stage = _Stage.search;
        final form = <String, String>{
          '_token': token!,
          'type': 'cad_num',
          'cad_number': cadastreNumber,
          'org_tin': '',
          'captcha': code,
        };
        final searchUri =
            Uri.parse('$davreestrBaseUrl/data/get-info/search');
        final searchHeaders = {
          'X-CSRF-TOKEN': token,
          HttpHeaders.refererHeader: '$davreestrBaseUrl/uz',
          HttpHeaders.acceptHeader: 'text/html, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': davreestrBaseUrl,
        };
        final searchStarted = DateTime.now();
        final search = await _postForm(
          httpClient,
          searchUri,
          form,
          cookies,
          extraHeaders: searchHeaders,
        );
        // ⚠️ 302 NI KUZATIB BORAMIZ. davreestr HAR QANDAY rad etishni
        // `302 → /uz` bilan qaytaradi va SABABINI keyingi sahifa
        // yuklanishiga flash qiladi. 302 ning o'z tanasi esa atigi
        // «Redirecting to …» — unda na «maxfiy kod noto», na «topilmadi»,
        // na rate-limit matni bor.
        //
        // Busiz pastdagi tasnif HECH QAYSI shoxga tushmasdi va eng
        // muhimi — CAPTCHA XATO ekani bilinmay, qayta urinish sikli
        // umuman ishga tushmasdi: urinish bekorga sarflanib,
        // foydalanuvchi «Ma'lumot olib bo'lmadi» ni ko'rardi. Aynan shu
        // «302 ko'p beryapti» shikoyatining sababi.
        //
        // Ergashish muvaffaqiyatli holatga ham FOYDA: sayt bir kun
        // Post/Redirect/Get ga o'tsa, natija sahifasi shu yerda o'qiladi.
        var searchBody = search.body;
        if (search.isRedirect) {
          final loc = search.headers[HttpHeaders.locationHeader];
          final target = (loc == null || loc.isEmpty)
              ? homeUri
              : homeUri.resolve(loc);
          try {
            searchBody = (await _get(httpClient, target, cookies)).body;
          } on DavreestrLookupException {
            // Flash sahifasi ham kelmasa — asl (bo'sh) tana bilan davom
            // etamiz va pastdagi 302 shoxi ushlaydi.
          }
        }

        /// This attempt's request/response, for whichever branch below decides
        /// it failed. Headers are logged WITHOUT the session cookie value.
        void logSearch(
          String kind,
          String message, {
          String atStage = _Stage.search,
        }) =>
            report.add(
              stage: atStage,
              kind: kind,
              message: message,
              attempt: attempt,
              method: 'POST',
              url: searchUri.toString(),
              requestHeaders: {
                ...searchHeaders,
                'X-CSRF-TOKEN': '<redacted>',
                if (cookies.isNotEmpty) 'Cookie': '<${cookies.length} cookie>',
              },
              requestBody: _encodeForm(form),
              status: search.statusCode,
              responseHeaders: search.headers,
              responseBody: searchBody,
              durationMs: _elapsed(searchStarted),
            );

        // 5) Classify response.
        final lower = _htmlUnescape(searchBody).toLowerCase();

        // 302 dan keyin sabab topilmasa — deyarli har doim captcha.
        // Davreestr rad etish sababini har doim ham flash qilmaydi, lekin
        // rad etishning o'zi 302 bilan keladi, ya'ni urinishni TUGAGAN deb
        // hisoblash noto'g'ri: yangi captcha bilan qayta urinish odatda
        // o'tadi.
        final redirectedWithoutReason = shouldRetryRejected(
          isRedirect: search.isRedirect,
          bodyLower: lower,
        );

        if (_anyContains(lower, _rateLimitPatterns)) {
          logSearch(
            _Kind.rateLimited,
            "bazaga so'rovlar soni oshib ketdi (yoki sayt shu xabarni har "
            "qanday rad etishda ko'rsatadi — javob tanasiga qarab ayirish "
            "kerak)",
          );
          throw const DavreestrLookupException(
            "davreestr.uz: bazaga so'rovlar soni oshib ketdi, "
            "biroz keyinroq urinib ko'ring",
          );
        }

        if (_anyContains(lower, _captchaWrongPatterns) ||
            redirectedWithoutReason) {
          // Wrong captcha — server rotates token, but session stays.
          lastError = 'Captcha xato';
          logSearch(
            _Kind.captchaWrong,
            redirectedWithoutReason
                ? 'Forma rad etildi (302, sabab aytilmadi) — captcha deb '
                    'hisoblab qayta urinamiz'
                : 'Captcha kodi rad etildi',
          );
          final refreshed = _extractCsrf(searchBody);
          if (refreshed != null) token = refreshed;
          continue;
        }

        if (_anyContains(lower, _notFoundPatterns) &&
            !_anyContains(lower, _successHintPatterns)) {
          logSearch(
            _Kind.notFound,
            'Kadastr raqami $cadastreNumber davreestr.uz da topilmadi',
          );
          throw DavreestrLookupException(
            'Kadastr raqami $cadastreNumber davreestr.uz da topilmadi',
          );
        }

        // Success path.
        final parsed = _parseResultHtml(searchBody, cadastreNumber);
        if (parsed.hasUsableData) {
          delivered = true;
        } else {
          // The user sees "Ma'lumot olib bo'lmadi" for this, and until now it
          // left no trace at all. Two very different causes look identical
          // here, which is exactly why the response body is logged:
          //   * a 3xx — davreestr REJECTED the form (it answers every rejected
          //     search with `302 → /uz` and flashes the reason onto the next
          //     page load), so this body is a redirect stub, not a result page;
          //   * a 200 whose markup no longer matches the parser.
          // NOTE: reporting only. The flow is untouched — the empty result is
          // still returned exactly as before.
          logSearch(
            search.isRedirect ? _Kind.httpRedirect : _Kind.parseEmpty,
            search.isRedirect
                ? 'davreestr forma rad etdi: HTTP ${search.statusCode} → '
                    '${search.headers[HttpHeaders.locationHeader] ?? '?'}'
                : "Javob 200, lekin natija maydonlari bo'sh — parser "
                    'eskirgan yoki javob natija sahifasi emas',
            // A rejected form never reached the parser; an empty 200 did.
            atStage: search.isRedirect ? _Stage.search : _Stage.parse,
          );
        }
        // Cache for next time (fire-and-forget — never block/fail on this).
        // On a forced refresh we deliberately don't write the cache either: the
        // AI Baholash flow must stay cache-free end-to-end (a stale/global entry
        // must never feed a legal valuation document).
        if (!forceRefresh) unawaited(_storeCached(parsed));
        return parsed;
      }

      report.add(
        stage: _Stage.search,
        kind: _Kind.captchaExhausted,
        message: '$maxCaptchaRetries urinish ham muvaffaqiyatsiz '
            "(${lastError ?? 'no result'})",
        attempt: maxCaptchaRetries,
      );
      throw DavreestrLookupException(
        "davreestr.uz: captcha yechib bo'lmadi (${lastError ?? 'no result'})",
      );
    } on DavreestrLookupException {
      rethrow;
    } on SocketException catch (e) {
      report.add(
        stage: stage,
        kind: _Kind.network,
        message: 'SocketException: ${e.message}',
        attempt: attemptNo > 0 ? attemptNo : null,
      );
      throw DavreestrLookupException('Tarmoq xatosi: ${e.message}');
    } on TimeoutException {
      report.add(
        stage: stage,
        kind: _Kind.timeout,
        message: 'davreestr.uz vaqtida javob bermadi '
            '(${_timeout.inSeconds}s)',
        attempt: attemptNo > 0 ? attemptNo : null,
      );
      throw const DavreestrLookupException(
        'davreestr.uz vaqtida javob bermadi',
      );
    } catch (e) {
      report.add(
        stage: stage,
        kind: _Kind.unknown,
        message: 'Kutilmagan xato: $e',
        attempt: attemptNo > 0 ? attemptNo : null,
      );
      throw DavreestrLookupException('Kutilmagan xato: $e');
    } finally {
      httpClient.close(force: true);
      // The user did not get their data → tell the backend why. Fire-and-forget
      // and after `return`/`throw` has been decided, so it can neither delay
      // the lookup nor change its outcome.
      if (!delivered) unawaited(_reportFailure(report));
    }
  }

  static int _elapsed(DateTime since) =>
      DateTime.now().difference(since).inMilliseconds;

  static String _encodeForm(Map<String, String> form) => form.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  /// Send the collected failures. Never throws, never blocks the caller.
  ///
  /// `AuthHttpClient` attaches the session token, and the backend derives the
  /// user and the IP from it — the payload carries no identity of its own.
  ///
  /// Its OWN client, not [_backendClient]: this runs unawaited from `lookup`'s
  /// `finally`, and the caller disposes the scraper the moment `lookup`
  /// returns or throws (`CadastreApiService.lookup`). `IOClient.close()`
  /// closes the underlying HttpClient with `force: true`, which terminates
  /// requests still in flight — so a shared client would drop precisely the
  /// reports we care about, the ones from a failed lookup.
  Future<void> _reportFailure(_FailureReport report) async {
    if (report.entries.isEmpty) return;
    final client = _injectedClient ?? AuthHttpClient();
    try {
      await client
          .post(
            Uri.parse('$_backendRoot/davreestr/logs'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'entries': report.entries}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Diagnostics must never become a second failure for the user.
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  void dispose() {
    _backendClient.close();
  }

  // ─── Backend lookup cache ───────────────────────────────────────────
  // Both calls go through AuthHttpClient (auth token attached automatically)
  // and fail soft: a cache miss/error just means we scrape on-device.

  String get _backendRoot => backendBaseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<DavreestrLookupResult?> _fetchCached(String cadastreNumber) async {
    try {
      final uri = Uri.parse(
        '$_backendRoot/davreestr/lookup'
        '?cadastre_number=${Uri.encodeQueryComponent(cadastreNumber)}',
      );
      final res = await _backendClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null; // 404 → not cached / stale
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return DavreestrLookupResult(
        cadastreNumber: (j['cadastre_number'] as String?) ?? cadastreNumber,
        address: j['address'] as String?,
        objectTypeHint: j['object_type_hint'] as String?,
        totalArea: (j['total_area'] as num?)?.toDouble(),
        livingArea: (j['living_area'] as num?)?.toDouble(),
        landArea: (j['land_area'] as num?)?.toDouble(),
        cadastreValue: (j['cadastre_value'] as num?)?.toDouble(),
        // `hasRestrictions` ATAYLAB berilmaydi (= null, "noma'lum"): kesh bu
        // maydonni saqlamaydi va manzil/maydondan farqli o'laroq ta'qiq
        // o'zgarib turadi. Ta'qiqni tekshirish oqimi keshga umuman
        // tushmaydi — `forceRefresh: true` bilan so'raydi.
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeCached(DavreestrLookupResult r) async {
    try {
      final uri = Uri.parse('$_backendRoot/davreestr/lookup');
      await _backendClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'cadastre_number': r.cadastreNumber,
              'address': r.address,
              'object_type_hint': r.objectTypeHint,
              'total_area': r.totalArea,
              'living_area': r.livingArea,
              'land_area': r.landArea,
              'cadastre_value': r.cadastreValue,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // best-effort cache write — ignore failures
    }
  }

  // ─── HTTP helpers ──────────────────────────────────────────────────

  Future<_HttpResult> _get(
    HttpClient client,
    Uri uri,
    Map<String, String> cookies,
  ) async {
    final req = await client.getUrl(uri).timeout(_timeout);
    _applyDefaultHeaders(req, cookies);
    final resp = await req.close().timeout(_timeout);
    _absorbCookies(resp, cookies);
    final bodyBytes = await _collectBytes(resp);
    if (resp.statusCode >= 400) {
      throw DavreestrLookupException(
        'davreestr.uz GET ${uri.path} → HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    return _HttpResult(
      statusCode: resp.statusCode,
      headers: _headerMap(resp),
      body: utf8.decode(bodyBytes, allowMalformed: true),
    );
  }

  Future<Uint8List> _getBytes(
    HttpClient client,
    Uri uri,
    Map<String, String> cookies,
  ) async {
    final req = await client.getUrl(uri).timeout(_timeout);
    _applyDefaultHeaders(req, cookies);
    final resp = await req.close().timeout(_timeout);
    _absorbCookies(resp, cookies);
    if (resp.statusCode != 200) {
      throw DavreestrLookupException(
        'davreestr.uz captcha image HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    return _collectBytes(resp);
  }

  Future<_HttpResult> _postForm(
    HttpClient client,
    Uri uri,
    Map<String, String> form,
    Map<String, String> cookies, {
    Map<String, String> extraHeaders = const {},
  }) async {
    final bodyBytes = utf8.encode(_encodeForm(form));

    final req = await client.postUrl(uri).timeout(_timeout);
    _applyDefaultHeaders(req, cookies);
    req.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded; charset=UTF-8',
    );
    req.headers.set(HttpHeaders.contentLengthHeader, bodyBytes.length);
    extraHeaders.forEach(req.headers.set);

    req.add(bodyBytes);
    final resp = await req.close().timeout(_timeout);
    _absorbCookies(resp, cookies);
    final bytes = await _collectBytes(resp);
    // Deliberately NOT throwing on a non-2xx: davreestr answers a rejected
    // search form with `302`, and the caller has to classify that (and log
    // it) rather than treat it as a transport error.
    return _HttpResult(
      statusCode: resp.statusCode,
      headers: _headerMap(resp),
      body: utf8.decode(bytes, allowMalformed: true),
    );
  }

  /// Response headers as a flat map, minus the session cookie values.
  ///
  /// `location` is the interesting one — on a rejected form it points at
  /// `/uz`, which is what makes a `302` legible in the log.
  static Map<String, String> _headerMap(HttpClientResponse resp) {
    final out = <String, String>{};
    resp.headers.forEach((name, values) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.setCookieHeader) {
        out[key] = '<${values.length} cookie>';
        return;
      }
      out[key] = values.join(', ');
    });
    return out;
  }

  void _applyDefaultHeaders(
    HttpClientRequest req,
    Map<String, String> cookies,
  ) {
    req.headers
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..set(HttpHeaders.acceptLanguageHeader, 'uz,ru;q=0.9,en;q=0.8')
      ..set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
    if (cookies.isNotEmpty) {
      req.headers.set(
        HttpHeaders.cookieHeader,
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    }
    // Disable persistent connection — each davreestr request is independent
    // and TLS handshake cost is negligible compared to 4-5s captcha cycles.
    req.persistentConnection = false;
    req.followRedirects = true;
  }

  void _absorbCookies(
    HttpClientResponse resp,
    Map<String, String> cookies,
  ) {
    for (final c in resp.cookies) {
      // Empty-value Set-Cookie means "delete" — drop from jar so we don't
      // resend a stale cookie that the server explicitly cleared.
      if (c.value.isEmpty) {
        cookies.remove(c.name);
        continue;
      }
      cookies[c.name] = c.value;
    }
  }

  Future<Uint8List> _collectBytes(HttpClientResponse resp) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  // ─── Backend captcha OCR ───────────────────────────────────────────

  Future<String?> _solveCaptcha(Uint8List image) async {
    final uri = Uri.parse(
      '${backendBaseUrl.replaceAll(RegExp(r'/+$'), '')}/davreestr/solve-captcha',
    );
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $authToken'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          image,
          filename: 'captcha.png',
        ),
      );
    try {
      final streamed =
          await _backendClient.send(req).timeout(_timeout);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 502) {
        // Backend says OCR didn't recognize digits — caller retries with a
        // fresh captcha.
        return null;
      }
      if (streamed.statusCode != 200) {
        throw DavreestrLookupException(
          'Backend OCR HTTP ${streamed.statusCode}: ${_excerpt(body)}',
          statusCode: streamed.statusCode,
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final code = (json['code'] as String?)?.trim();
      if (code == null || code.isEmpty) return null;
      return code;
    } on TimeoutException {
      throw const DavreestrLookupException(
        'Captcha serveri vaqtida javob bermadi',
      );
    } on SocketException catch (e) {
      throw DavreestrLookupException(
        'Captcha serveriga ulanish xatosi: ${e.message}',
      );
    }
  }

  static String _excerpt(String s) =>
      s.length <= 200 ? s : '${s.substring(0, 200)}…';

  // ─── HTML helpers (regex; matches the Python original 1:1) ─────────

  static final _csrfMeta = RegExp(
    r'<meta\s+name=["\x27]csrf-token["\x27]\s+content=["\x27]([^"\x27]+)["\x27]',
    caseSensitive: false,
  );
  static final _csrfInput = RegExp(
    r'<input[^>]+name=["\x27]_token["\x27][^>]*value=["\x27]([^"\x27]+)["\x27]',
    caseSensitive: false,
  );

  static String? _extractCsrf(String html) {
    final m1 = _csrfMeta.firstMatch(html);
    if (m1 != null) return m1.group(1);
    final m2 = _csrfInput.firstMatch(html);
    if (m2 != null) return m2.group(1);
    return null;
  }

  // Ta'qiq/cheklov bloki. Natija sahifasida u faqat CHEKLOV BOR obyektda
  // chiziladi — toza obyektda `cad_search_bans` katakchasi umuman yo'q. Ya'ni
  // "taqiq yo'q" degan xulosa qatorning YO'QLIGIdan chiqariladi, va shuning
  // uchun u faqat qidiruvning o'zi muvaffaqiyatli bo'lgandagina ma'noga ega.
  static final _bansStatusRe = RegExp(
    r'cad_search_bans.{0,400}?</td>\s*<td[^>]*>(.*?)</td>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _banTableRe = RegExp(
    r'<table[^>]*class="[^"]*ban-table[^"]*"[^>]*>(.*?)</table>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _banRowRe = RegExp(
    r'<tr[^>]*>(.*?)</tr>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _banCellRe = RegExp(
    r'<td[^>]*>(.*?)</td>',
    caseSensitive: false,
    dotAll: true,
  );

  /// "Mavjud emas" / "yo'q" — reyestr bir kun qatorni HAR DOIM chizadigan
  /// bo'lsa, inkorni matndan o'qiy olishimiz uchun. Bugun bu yo'l yurilmaydi.
  static const _noBanPatterns = [
    'mavjud emas',
    "yo'q",
    'yoq',
    'нет',
    'отсутств',
  ];

  static bool _anyContains(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  // Davreestr response is HTML-escaped on the wire — `&#039;` for `'`,
  // `&quot;`, `&amp;` etc. We unescape just enough to make case-sensitive
  // pattern matching reliable.
  static String _htmlUnescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');

  // davreestr.uz natija sahifasi — server-render qilingan Laravel HTML jadval.
  // Tuzilishi (2026-05 holatiga ko'ra):
  //   <tr><td><b>LABEL (m<sup>2</sup>):</b></td>
  //       <td class="text-right"><span>VALUE</span></td></tr>
  // Manzil esa alohida: <p class="location-color">VALUE</p>.
  // Eski parser label'ni to'g'ridan-to'g'ri <td> ichida kutardi va qiymatni
  // `[^<]+` bilan olardi — `<b>`/`<span>`/`<sup>` o'ramlari tufayli hech narsa
  // topa olmasdi (barcha maydonlar bo'sh chiqardi).
  static DavreestrLookupResult _parseResultHtml(
    String html,
    String cadastreNumber,
  ) {
    // Ko'p qatorli <td> bloklari ishonchli mos kelishi uchun bo'shliqlarni
    // bitta probelga keltiramiz.
    final flat = html.replaceAll(RegExp(r'\s+'), ' ');

    String stripTags(String s) => _htmlUnescape(
          s.replaceAll(RegExp(r'<[^>]+>'), ' '),
        ).replaceAll(RegExp(r'\s+'), ' ').trim();

    // Jadval qatori: LABEL (ehtimol <b> ichida, ichki <sup> bilan) → keyingi
    // <td> qiymat katakchasi. Label'dan keyin katakcha yopilishigacha (</td>)
    // sakraymiz, so'ng qiymat katakchasidagi barcha matnni olamiz.
    String? grabRow(List<String> labels) {
      for (final label in labels) {
        final re = RegExp(
          '${RegExp.escape(label)}.{0,60}?</td>\\s*<td[^>]*>(.*?)</td>',
          caseSensitive: false,
          dotAll: true,
        );
        final m = re.firstMatch(flat);
        if (m != null) {
          final val = stripTags(m.group(1) ?? '');
          if (val.isNotEmpty) return val;
        }
      }
      return null;
    }

    // Manzil — <p class="location-color">...</p> ichida.
    String? grabAddress() {
      final re = RegExp(
        r'class="location-color"[^>]*>(.*?)</p>',
        caseSensitive: false,
        dotAll: true,
      );
      final m = re.firstMatch(flat);
      if (m == null) return null;
      final val = stripTags(m.group(1) ?? '');
      return val.isEmpty ? null : val;
    }

    double? toDecimal(String? s) {
      if (s == null || s.isEmpty) return null;
      // Birliklarni (so'm, m2, *) tashlab, faqat raqam/ajratgichlarni qoldiramiz.
      final cleaned =
          s.replaceAll(RegExp(r'[^0-9,\.]'), '').replaceAll(',', '.');
      if (cleaned.isEmpty) return null;
      return double.tryParse(cleaned);
    }

    // Ta'qiq va cheklovlar. Status katakchasi topilsa — blok bor; matnida
    // inkor bo'lsa (bugun uchramaydi, lekin sayt o'zgarsa) "yo'q" deb
    // o'qiymiz. Blok umuman bo'lmasa `false`: toza obyektda reyestr bu
    // qatorni chizmaydi.
    final bansStatus = _bansStatusRe.firstMatch(flat);
    final bool hasBans;
    if (bansStatus == null) {
      hasBans = false;
    } else {
      final statusText = stripTags(bansStatus.group(1) ?? '').toLowerCase();
      hasBans = !_anyContains(statusText, _noBanPatterns);
    }

    final restrictions = <DavreestrRestriction>[];
    final banTable = _banTableRe.firstMatch(flat);
    if (banTable != null) {
      for (final row in _banRowRe.allMatches(banTable.group(1) ?? '')) {
        // Sarlavha qatorida <td> yo'q (faqat <th>) — o'zidan-o'zi tushib
        // qoladi, alohida <thead> kesish shart emas.
        final cells = _banCellRe
            .allMatches(row.group(1) ?? '')
            .map((c) => stripTags(c.group(1) ?? ''))
            .toList(growable: false);
        if (cells.isEmpty) continue;
        String at(int i) => i < cells.length ? cells[i] : '';
        final entry = DavreestrRestriction(
          number: at(0),
          kind: at(1),
          authority: at(2),
          date: at(3),
          documentNumber: at(4),
          exchangeCode: at(5),
        );
        if (!entry.isEmpty) restrictions.add(entry);
      }
    }

    final parsed = DavreestrLookupResult(
      cadastreNumber: cadastreNumber,
      address: grabAddress() ?? grabRow(const ['Manzil', 'Address', 'Адрес']),
      // ⚠️ Reyestr yorlig'i APOSTROF bilan — `Ob'ekt turi:`. Ro'yxatda faqat
      // `Obyekt turi` turgani uchun bu maydon hech qachon to'lmagan.
      objectTypeHint: grabRow(const [
        "Ob'ekt turi",
        'Obyekt turi',
        'Object type',
        'Тип объекта',
      ]),
      // "Umumiy foydali maydoni" — bino umumiy foydali maydoni (m2).
      totalArea: toDecimal(grabRow(const [
        'Umumiy foydali maydoni',
        'Umumiy maydon',
        'Total area',
        'Общая площадь',
      ])),
      livingArea: toDecimal(grabRow(const [
        'Yashash maydoni',
        'Living area',
        'Жилая площадь',
      ])),
      // Yer maydoni. "Hujjat bo'yicha" AVVAL keladi: u hujjatdagi rasmiy
      // raqam, "Amaldagi" esa o'lchovdagisi — e'lon uchun rasmiysi to'g'ri
      // va u ko'pincha aynan bir xil.
      landArea: toDecimal(grabRow(const [
        "Hujjat bo'yicha umumiy yer maydoni",
        'Amaldagi yer maydoni',
        'Land area',
        'Площадь земельного участка',
      ])),
      cadastreValue: toDecimal(grabRow(const [
        'Kadastr qiymati',
        'Cadastre value',
        'Кадастровая стоимость',
      ])),
      // Bu javob AYNAN hozir reyestrdan o'qildi — ya'ni ta'qiq holati ma'lum.
      // Keshdan kelgan javobda esa `null` qoladi (`_fetchCached`).
      hasRestrictions: hasBans,
      restrictions: List.unmodifiable(restrictions),
    );

    // Sahifa natija sahifasi BO'LMASA (rad etilgan forma, rate-limit, reyestrda
    // yo'q raqam) hamma maydon bo'sh chiqadi — va cheklov bloki ham yo'q, ya'ni
    // `hasBans` `false` bo'ladi. Bu "ta'qiq yo'q" DEGANI EMAS: hech narsa
    // o'qilmadi. Shunday javobni "toza" deb ko'rsatish ta'qiq tekshiruvidagi
    // eng qimmat xato bo'lardi, shuning uchun holatni shu yerda `null`
    // (noma'lum) ga qaytaramiz — chaqiruvchining ehtiyotkorligiga tayanmasdan.
    if (!parsed.hasUsableData) {
      return DavreestrLookupResult(cadastreNumber: cadastreNumber);
    }
    return parsed;
  }

  /// Natija sahifasi parseri — testlar uchun ochilgan. Ishlab turgan kodda
  /// [lookup] o'zi chaqiradi.
  @visibleForTesting
  static DavreestrLookupResult parseResultHtml(
    String html,
    String cadastreNumber,
  ) =>
      _parseResultHtml(html, cadastreNumber);
}
