/// V2M (3DGS) server client — xona videosini yuborish va modelning holatini
/// kuzatish.
///
/// Server: `kadastr-v2m-beckend/service/app.py`. Ikkita endpoint ishlatiladi:
/// - `POST /api/upload` — multipart `file` + `name`, `{"id": "0826-a1b2c3"}`
///   qaytaradi. Job shu id bilan yashaydi.
/// - `GET  /api/models/{id}` — status/stage/progress/error/note + tayyor
///   fayllar xaritasi (`scene` = .spz, `glb`, `usdz`, `thumb`).
///
/// TEMPORARY: telefon hozircha to'g'ridan GPU qutisiga ulanadi. Asosiy
/// backend upload'ni brokerlashni boshlagach ([ApiConfig.v2mBaseUrl] bilan
/// birga) bu klient faqat backend bergan `upload_url` ni ishlatadigan bo'ladi.
///
/// DIQQAT: bu yerda ataylab oddiy [http.Client] ishlatiladi, `AuthHttpClient`
/// EMAS — u butun tanani `bodyBytes` ga yig'adi va 400 MB video xotirani
/// portlatadi. Fayl esa `MultipartFile.fromPath` orqali diskdan oqib boradi.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../../core/api_config.dart';

class V2mException implements Exception {
  const V2mException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'V2mException($code): $message';
}

/// Tayyor artefakt — yo'l serverga NISBIY (`models/<id>/scene.spz`).
class V2mFile {
  const V2mFile({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;

  factory V2mFile.fromMap(Map<dynamic, dynamic> m) => V2mFile(
        path: m['path'] as String? ?? '',
        sizeBytes: (m['size'] as num?)?.toInt() ?? 0,
      );

  String get sizeLabel => sizeBytes >= 1024 * 1024
      ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
}

/// Bitta xona modeli — v2m'dagi `models` qatorining aksi.
class V2mModel {
  const V2mModel({
    required this.id,
    required this.name,
    this.arizaId,
    this.room,
    this.roomOrd,
    required this.status,
    required this.stage,
    required this.progress,
    this.error,
    this.note,
    this.files = const {},
  });

  final String id;
  final String name;

  /// Asosiy backenddagi ariza id (matn ko'rinishida saqlanadi).
  final String? arizaId;

  /// Qaysi xona — `RoomKind.wire` qiymati.
  final String? room;

  /// Bir xil turdagi xonalarni ajratish uchun (1-yotoqxona, 2-yotoqxona).
  final int? roomOrd;

  /// `queued` | `processing` | `ready` | `done` | `failed`.
  final String status;

  /// `queued` | `ingest` | `frames` | `sfm` | `gpu_navbat` | `training` |
  /// `export` | `done`.
  final String stage;

  /// 0..100 — trening logidan o'qiladi, shu sababli sakrab turishi mumkin.
  final int progress;

  final String? error;

  /// Sifat ogohlantirishi (SSIM/LPIPS darvozasi) — foydalanuvchiga
  /// ko'rsatish uchun yozilgan, o'zbekcha.
  final String? note;

  /// `scene` (.spz) | `glb` | `usdz` | `thumb`.
  final Map<String, V2mFile> files;

  factory V2mModel.fromMap(Map<dynamic, dynamic> m) {
    final raw = (m['files'] as Map?) ?? const {};
    return V2mModel(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      arizaId: m['ariza_id'] as String?,
      room: m['room'] as String?,
      roomOrd: (m['room_ord'] as num?)?.toInt(),
      status: m['status'] as String? ?? '',
      stage: m['stage'] as String? ?? '',
      progress: (m['progress'] as num?)?.toInt() ?? 0,
      error: (m['error'] as String?)?.trim().isEmpty ?? true
          ? null
          : m['error'] as String?,
      note: (m['note'] as String?)?.trim().isEmpty ?? true
          ? null
          : m['note'] as String?,
      files: {
        for (final e in raw.entries)
          if (e.value is Map)
            e.key.toString(): V2mFile.fromMap(e.value as Map),
      },
    );
  }

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  /// Tugamagan — hali kutilyapti yoki ishlanyapti.
  bool get isRunning => !isDone && !isFailed;

  /// Xom splat (`.spz`). DIQQAT: quvur SPZ **v3** chiqaradi, ilovadagi
  /// mkkellogg viewer'i esa faqat v1–v2 ni o'qiydi ("version not supported"),
  /// shu sababli hozircha ko'rsatishga ishlatilmaydi. Viewer yangilanganda
  /// yoki Spark asosidagi web viewer ulanganda kerak bo'ladi.
  V2mFile? get scene => files['scene'];

  /// Telefonda HOZIR ochib bo'ladigan format: GLB (`model_viewer_plus`) yoki
  /// USDZ (iOS QuickLook) — ikkalasini ham `openScanModel()` mazmuni bo'yicha
  /// to'g'ri viewer'ga yo'naltiradi.
  ///
  /// Yo'q bo'lsa model hali tayyor emas — `status == 'done'` bo'lsa ham
  /// (SfM sifatsiz chiqsa eksport bo'lmasligi mumkin).
  V2mFile? get viewable => files['glb'] ?? files['usdz'];
}

class V2mClient {
  V2mClient({String? baseUrl, http.Client? client, Duration? readTimeout})
      : _baseUrl = baseUrl ?? ApiConfig.v2mBaseUrl,
        _client = client ?? http.Client(),
        _readTimeout = readTimeout ?? _defaultReadTimeout;

  final String _baseUrl;
  final http.Client _client;

  /// Javob TANASINI o'qish chegarasi (sarlavhalarniki emas). Sinovlar uni
  /// qisqartiradi — aks holda osilgan server testi haqiqiy bir daqiqa kutardi.
  final Duration _readTimeout;

  /// Nisbiy yo'lni (`models/<id>/scene.spz`) to'liq URL ga aylantiradi.
  String fileUrl(String relativePath) {
    final p = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return '$_baseUrl/$p';
  }

  /// Videoni yuboradi va model id sini qaytaradi.
  ///
  /// [name] — odam o'qiydigan yorliq (admin ro'yxatida ko'rinadi).
  /// [arizaId] va [room] esa alohida ustunlarga yoziladi — keyin
  /// [listByAriza] shular bo'yicha qidiradi.
  ///
  /// [onProgress] yuborilgan baytlarni jonli beradi — 100-500 MB fayl uchun
  /// progressiz UI muzlab qolgandek ko'rinadi.
  Future<String> upload({
    required File file,
    required String name,
    String? arizaId,
    String? room,
    int? roomOrd,
    void Function(int sent, int total)? onProgress,
  }) async {
    // Fayl yo'qligi ODATIY hol, xato emas: yo'l `SharedPreferences` da
    // saqlanadi, iOS esa tmp/Caches ni istalgan payt tozalaydi va ilova qayta
    // o'rnatilganda konteyner identifikatori o'zgaradi — saqlangan mutlaq yo'l
    // o'lik bo'lib qoladi.
    //
    // `File.length()` va `MultipartFile.fromPath` bunda `PathNotFoundException`
    // (`FileSystemException`) tashlaydi. Uni SHU YERDA [V2mException] ga
    // aylantirish shart: chaqiruvchi faqat [V2mException] ni ushlaydi, aks
    // holda xato undan o'tib ketardi va ekran "Video yuklanmoqda 0.0 / 0.0 MB"
    // holatida abadiy qotib qolardi.
    final int total;
    try {
      total = await file.length();
    } on FileSystemException {
      throw const V2mException('NO_FILE', 'Video fayli telefonda topilmadi');
    }
    // Nol baytli fayl serverda ham foydasiz, lekin bu yerda to'xtatmasak
    // `_timeoutFor(0)` eng qisqa taymautni beradi va sabab "Yuklash vaqti
    // tugadi" bo'lib ko'rinardi — asl sababni yashirib.
    if (total <= 0) {
      throw const V2mException('EMPTY_FILE', 'Video fayli bo\'sh');
    }

    final http.MultipartFile part;
    try {
      part = await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: _mediaTypeFor(file.path),
      );
    } on FileSystemException {
      throw const V2mException('NO_FILE', 'Video fayli telefonda topilmadi');
    }

    final request = _ProgressMultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/upload'),
      onBytes: onProgress == null ? null : (sent) => onProgress(sent, total),
    )
      ..fields['name'] = name
      ..fields['ariza_id'] = arizaId ?? ''
      ..fields['room'] = room ?? ''
      ..fields['room_ord'] = '${roomOrd ?? 0}'
      ..files.add(part);

    // Hajm BIRINCHI baytdan OLDIN bildiriladi. [onProgress] faqat oqim
    // boshlanganda chaqirilardi, shuning uchun ulanish sekin ochilsa ekranda
    // "0.0 / 0.0 MB" turardi — foydalanuvchi 1.5 GB video yuborayotganini
    // ko'rmasdi va yuklash qotib qolgandek tuyulardi.
    onProgress?.call(0, total);

    final http.StreamedResponse streamed;
    final String body;
    try {
      streamed = await _client.send(request).timeout(_timeoutFor(total));
      // `send` FAQAT sarlavha kelishini kutadi — tana keyin oqib keladi.
      // Uni ham chegaralash SHART: 200 qaytarib, so'ng jim qolgan server
      // (osilgan worker, yarim ochiq NAT ulanishi) bu future'ni ABADIY
      // tugallanmagan qoldirardi. Xato tashlanmagani uchun hech qanday
      // `catch` yordam bermasdi va ekran "yuklanmoqda" da qamalib qolardi —
      // u yerda tugma ham yo'q, orqaga chiqish ham bloklangan.
      body = await streamed.stream.bytesToString().timeout(_readTimeout);
    } on TimeoutException {
      throw const V2mException('TIMEOUT', 'Yuklash vaqti tugadi');
    } on SocketException catch (e) {
      throw V2mException('NETWORK', e.message);
    } on http.ClientException catch (e) {
      // `http` paketi dart:io `HttpException` ini shunga aylantiradi
      // ("Connection closed before full header was received"), va u
      // SocketException EMAS — alohida ushlanmasa o'tib ketardi.
      throw V2mException('NETWORK', e.message);
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw V2mException('HTTP_${streamed.statusCode}', _errorText(body));
    }
    final decoded = jsonDecode(body);
    final id = decoded is Map ? decoded['id'] as String? : null;
    if (id == null || id.isEmpty) {
      throw const V2mException('NO_ID', 'Server model id qaytarmadi');
    }
    return id;
  }

  /// Modelning joriy holati. 404 → [V2mException] `NOT_FOUND`.
  Future<V2mModel> getModel(String id) async {
    final uri = Uri.parse('$_baseUrl/api/models/$id');
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const V2mException('TIMEOUT', 'Server javob bermadi');
    } on SocketException catch (e) {
      throw V2mException('NETWORK', e.message);
    }
    if (res.statusCode == 404) {
      throw const V2mException('NOT_FOUND', 'Model topilmadi');
    }
    if (res.statusCode != 200) {
      throw V2mException('HTTP_${res.statusCode}', _errorText(res.body));
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw const V2mException('BAD_BODY', 'Kutilmagan javob');
    }
    return V2mModel.fromMap(decoded);
  }

  /// Modelni serverdan butunlay o'chiradi: yuklangan video, oraliq ish
  /// papkalari va tayyor splat/mesh fayllari.
  ///
  /// Model hozir ishlanayotgan bo'lsa server jarayonni AVVAL to'xtatadi
  /// (jarayon guruhi bilan) va navbatdagi ishga o'tadi — shuning uchun bu
  /// chaqiruv 30 soniyagacha ketishi mumkin.
  ///
  /// 404 ni XATO deb hisoblamaymiz: model allaqachon yo'q bo'lsa maqsadga
  /// erishilgan. `true` — server ishlayotgan ishni to'xtatdi.
  Future<bool> deleteModel(String id) async {
    final uri = Uri.parse('$_baseUrl/api/models/$id');
    final http.Response res;
    try {
      res = await _client.delete(uri).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const V2mException('TIMEOUT', 'Server javob bermadi');
    } on SocketException catch (e) {
      throw V2mException('NETWORK', e.message);
    }
    if (res.statusCode == 404) return false;
    if (res.statusCode != 200) {
      throw V2mException('HTTP_${res.statusCode}', _errorText(res.body));
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return decoded['cancelled'] == true;
    } catch (_) {
      // Javob JSON bo'lmasa ham o'chirish bajarilgan.
    }
    return false;
  }

  /// Ilova ichidagi WebView uchun viewer manzili — `embed.html`, ya'ni
  /// tugmasiz, oq fonli, faqat bitta xonani ko'rsatadigan sahifa
  /// (`view.html` — brauzer uchun to'liq versiya, joystik va model ro'yxatiga
  /// havolasi bilan; u ilovada ishlatilmaydi).
  ///
  /// Model hali tayyor bo'lmasa `null`.
  ///
  /// Ilovadagi viewer ishlatilmaydi: u SPZ v1-v2 ni o'qiydi, quvur esa v3
  /// yozadi. GLB ham emas — u splatdan olingan mesh, sifati pastroq.
  String? viewerUrlFor(V2mModel model, {String? title}) {
    final scene = model.scene;
    if (scene == null) return null;
    final name = Uri.encodeQueryComponent(title ?? model.name);
    // `m` da `/` kodlanmaydi: sahifa katalogni shu yo'ldan oladi
    // (`orient.json` yonida turadi), %2F esa uni chalg'itishi mumkin.
    return '$_baseUrl/embed.html?m=${scene.path}&n=$name';
  }

  /// Arizaga tegishli BARCHA xona modellari — model id larni eslab
  /// qolish shart emas, ariza raqami yetadi.
  Future<List<V2mModel>> listByAriza(String arizaId) async {
    final uri = Uri.parse('$_baseUrl/api/models?ariza_id=$arizaId');
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const V2mException('TIMEOUT', 'Server javob bermadi');
    } on SocketException catch (e) {
      throw V2mException('NETWORK', e.message);
    }
    if (res.statusCode != 200) {
      throw V2mException('HTTP_${res.statusCode}', _errorText(res.body));
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(V2mModel.fromMap)
        .toList();
  }

  /// Tayyor artefaktni lokal faylga yuklab oladi (splat viewer lokal yo'lni
  /// talab qiladi). Fayl oqim bilan yoziladi — 20-40 MB xotiraga yig'ilmaydi.
  Future<File> download(
    V2mFile remote, {
    required Directory into,
    void Function(int received, int total)? onProgress,
  }) async {
    final uri = Uri.parse(fileUrl(remote.path));
    final request = http.Request('GET', uri);
    final http.StreamedResponse res;
    try {
      res = await _client.send(request).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const V2mException('TIMEOUT', 'Yuklab olish vaqti tugadi');
    } on SocketException catch (e) {
      throw V2mException('NETWORK', e.message);
    }
    if (res.statusCode != 200) {
      throw V2mException('HTTP_${res.statusCode}', 'Fayl yuklab olinmadi');
    }

    final name = remote.path.split('/').last;
    final file = File('${into.path}/${remote.hashCode.toUnsigned(32)}_$name');
    final sink = file.openWrite();
    final total = res.contentLength ?? remote.sizeBytes;
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  }

  void dispose() => _client.close();

  /// Yuklash tugagach javob tanasini o'qish chegarasi. Bu yerda uzatiladigan
  /// narsa bir necha o'nlab bayt (`{"id": "..."}`), shuning uchun qat'iy: uzoq
  /// kutishning ma'nosi yo'q, ammo chegarasiz qoldirish ekranni qamab qo'yadi.
  static const Duration _defaultReadTimeout = Duration(seconds: 60);

  /// Katta fayl sekin ketadi — timeout hajm bilan o'sadi (60 s + 4 s/MB),
  /// 1 daqiqadan 10 daqiqagacha.
  static Duration _timeoutFor(int bytes) {
    final mb = bytes / (1024 * 1024);
    final seconds = (60 + mb * 4).round().clamp(60, 600);
    return Duration(seconds: seconds);
  }

  static String _errorText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // JSON emas — xom matnni beramiz.
    }
    return body.isEmpty ? 'Server xatosi' : body;
  }
}

/// Tana socketga oqib chiqqan sari yuborilgan baytlarni xabar qiladi.
/// `package:http` upload progress bermaydi — `api_ai_upload_service.dart`
/// dagi bilan bir xil usul.
class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, {this.onBytes});

  final void Function(int bytesSent)? onBytes;

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final cb = onBytes;
    if (cb == null) return byteStream;
    var sent = 0;
    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        sent += data.length;
        cb(sent);
        sink.add(data);
      },
    );
    return http.ByteStream(byteStream.transform(transformer));
  }
}

MediaType? _mediaTypeFor(String path) {
  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'mp4':
      return MediaType('video', 'mp4');
    case 'mov':
      return MediaType('video', 'quicktime');
    case 'm4v':
      return MediaType('video', 'x-m4v');
    default:
      return null;
  }
}
