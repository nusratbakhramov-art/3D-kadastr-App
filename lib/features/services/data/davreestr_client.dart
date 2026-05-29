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
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../auth/auth_http_client.dart';

/// Successful davreestr.uz lookup. Shape matches the existing
/// `CadastreLookupResult` so the rest of the app needs no changes.
class DavreestrLookupResult {
  const DavreestrLookupResult({
    required this.cadastreNumber,
    this.address,
    this.objectTypeHint,
    this.totalArea,
    this.livingArea,
    this.cadastreValue,
  });

  final String cadastreNumber;
  final String? address;
  final String? objectTypeHint;
  final double? totalArea;
  final double? livingArea;
  final double? cadastreValue;
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

  Future<DavreestrLookupResult> lookup(String cadastreNumber) async {
    final httpClient = HttpClient()
      ..connectionTimeout = _timeout
      ..idleTimeout = _timeout;

    // Manual cookie jar — dart:io's HttpClient doesn't persist cookies
    // across requests by default, and Laravel session cookies (XSRF-TOKEN,
    // laravel_session) are critical for the form POST to succeed.
    final cookies = <String, String>{};

    try {
      // 1) Home page — collect cookies + CSRF token.
      final homeUri = Uri.parse('$davreestrBaseUrl/uz');
      final homeBody = await _get(httpClient, homeUri, cookies);
      var token = _extractCsrf(homeBody);
      if (token == null) {
        throw const DavreestrLookupException(
          'davreestr.uz: CSRF token topilmadi',
        );
      }

      String? lastError;

      for (var attempt = 1; attempt <= maxCaptchaRetries; attempt++) {
        // 2) Captcha PNG — session-bound, single-use.
        final captchaUri = Uri.parse('$davreestrBaseUrl/captcha/default');
        final captchaBytes = await _getBytes(httpClient, captchaUri, cookies);

        // 3) Solve via backend OCR.
        final code = await _solveCaptcha(captchaBytes);
        if (code == null) {
          // OCR fail — server picks a fresh captcha image, try again.
          continue;
        }

        // 4) Submit search form.
        final form = <String, String>{
          '_token': token!,
          'type': 'cad_num',
          'cad_number': cadastreNumber,
          'org_tin': '',
          'captcha': code,
        };
        final searchUri =
            Uri.parse('$davreestrBaseUrl/data/get-info/search');
        final searchBody = await _postForm(
          httpClient,
          searchUri,
          form,
          cookies,
          extraHeaders: {
            'X-CSRF-TOKEN': token,
            HttpHeaders.refererHeader: '$davreestrBaseUrl/uz',
            HttpHeaders.acceptHeader: 'text/html, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest',
            'Origin': davreestrBaseUrl,
          },
        );

        // 5) Classify response.
        final lower = _htmlUnescape(searchBody).toLowerCase();

        if (_anyContains(lower, _rateLimitPatterns)) {
          throw const DavreestrLookupException(
            "davreestr.uz: bazaga so'rovlar soni oshib ketdi, "
            "biroz keyinroq urinib ko'ring",
          );
        }

        if (_anyContains(lower, _captchaWrongPatterns)) {
          // Wrong captcha — server rotates token, but session stays.
          lastError = 'Captcha xato';
          final refreshed = _extractCsrf(searchBody);
          if (refreshed != null) token = refreshed;
          continue;
        }

        if (_anyContains(lower, _notFoundPatterns) &&
            !_anyContains(lower, _successHintPatterns)) {
          throw DavreestrLookupException(
            'Kadastr raqami $cadastreNumber davreestr.uz da topilmadi',
          );
        }

        // Success path.
        return _parseResultHtml(searchBody, cadastreNumber);
      }

      throw DavreestrLookupException(
        "davreestr.uz: captcha yechib bo'lmadi (${lastError ?? 'no result'})",
      );
    } on DavreestrLookupException {
      rethrow;
    } on SocketException catch (e) {
      throw DavreestrLookupException('Tarmoq xatosi: ${e.message}');
    } on TimeoutException {
      throw const DavreestrLookupException(
        'davreestr.uz vaqtida javob bermadi',
      );
    } catch (e) {
      throw DavreestrLookupException('Kutilmagan xato: $e');
    } finally {
      httpClient.close(force: true);
    }
  }

  void dispose() {
    _backendClient.close();
  }

  // ─── HTTP helpers ──────────────────────────────────────────────────

  Future<String> _get(
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
    return utf8.decode(bodyBytes, allowMalformed: true);
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

  Future<String> _postForm(
    HttpClient client,
    Uri uri,
    Map<String, String> form,
    Map<String, String> cookies, {
    Map<String, String> extraHeaders = const {},
  }) async {
    final encoded = form.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final bodyBytes = utf8.encode(encoded);

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
    return utf8.decode(bytes, allowMalformed: true);
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

    return DavreestrLookupResult(
      cadastreNumber: cadastreNumber,
      address: grabAddress() ?? grabRow(const ['Manzil', 'Address', 'Адрес']),
      objectTypeHint: grabRow(const ['Obyekt turi', 'Object type', 'Тип объекта']),
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
      cadastreValue: toDecimal(grabRow(const [
        'Kadastr qiymati',
        'Cadastre value',
        'Кадастровая стоимость',
      ])),
    );
  }
}
