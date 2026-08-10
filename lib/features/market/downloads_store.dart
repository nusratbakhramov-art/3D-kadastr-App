import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bitta yuklab olingan marketplace fayli haqidagi yozuv.
///
/// [fileName] saqlanadi, TO'LIQ yo'l EMAS: iOS'da ilova konteyneri yo'li har
/// build/o'rnatishda o'zgaradi, shuning uchun absolut yo'lni saqlash keyingi
/// ishga tushirishda "fayl yo'q" degan xatoga olib keladi.
class MarketDownload {
  const MarketDownload({
    required this.fileId,
    required this.modelId,
    required this.fileName,
    required this.format,
    required this.sizeBytes,
    required this.savedAt,
  });

  final int fileId;
  final int modelId;
  final String fileName;
  final String format;
  final int sizeBytes;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'modelId': modelId,
    'fileName': fileName,
    'format': format,
    'sizeBytes': sizeBytes,
    'savedAt': savedAt.millisecondsSinceEpoch,
  };

  static MarketDownload? fromJson(Map<String, dynamic> j) {
    final fileId = (j['fileId'] as num?)?.toInt();
    final name = j['fileName'] as String?;
    if (fileId == null || name == null || name.isEmpty) return null;
    return MarketDownload(
      fileId: fileId,
      modelId: (j['modelId'] as num?)?.toInt() ?? 0,
      fileName: name,
      format: (j['format'] as String?) ?? '',
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (j['savedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Marketplace'dan yuklab olingan fayllar ombori.
///
/// Fayllar ilovaning `Documents/Yuklamalar` papkasiga tushadi (vaqtinchalik
/// `tmp` EMAS — iOS uni istalgan vaqtda tozalab yuboradi). Indeks
/// SharedPreferences'da: shu tufayli ekran qayta ochilganda chip "yuklab olish"
/// emas, "ochish" holatida ko'rinadi va katta fayl qayta yuklanmaydi.
class MarketDownloads {
  MarketDownloads._();

  static const String _prefsKey = 'market.downloads.v1';
  static const String _dirName = 'Yuklamalar';

  /// Fayl tizimida ruxsat etilmagan belgilar. Kirill/lotin harflari, `№`,
  /// apostrof va bo'shliqlar SAQLANADI — nom o'qiladigan bo'lib qolsin.
  static final RegExp _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  static Directory? _cachedDir;

  /// `Documents/Yuklamalar` — yo'q bo'lsa yaratiladi.
  static Future<Directory> directory() async {
    final cached = _cachedDir;
    if (cached != null && await cached.exists()) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cachedDir = dir;
    return dir;
  }

  /// E'lon sarlavhasidan o'qiladigan fayl nomi yasaydi: `Sarlavha.dwg`.
  ///
  /// Eski kod ASCII bo'lmagan hamma narsani kesib tashlardi, shuning uchun
  /// "Ko'p qavatli turar joy bino №64" → "Kop_qavatli_turar_joy_bino_64" bo'lib
  /// qolardi. Endi faqat fayl tizimi uchun xavfli belgilar olib tashlanadi.
  static String buildFileName(String title, String format) {
    var base = title
        .replaceAll(_illegal, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Nuqta bilan boshlanish (yashirin fayl) va ortiqcha uzunlikni cheklaymiz.
    while (base.startsWith('.')) {
      base = base.substring(1).trim();
    }
    if (base.length > 80) base = base.substring(0, 80).trim();
    if (base.isEmpty) base = 'model';
    final ext = format.toLowerCase().replaceAll(_illegal, '');
    return ext.isEmpty ? base : '$base.$ext';
  }

  static Future<Map<int, MarketDownload>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      final out = <int, MarketDownload>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final rec = MarketDownload.fromJson(Map<String, dynamic>.from(item));
        if (rec != null) out[rec.fileId] = rec;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeIndex(Map<int, MarketDownload> index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final r in index.values) r.toJson()]),
    );
  }

  /// Shu modelning yuklab olingan fayllari (diskda haqiqatan mavjudlari).
  ///
  /// Diskda yo'q bo'lib qolgan yozuvlar (foydalanuvchi Files'da o'chirgan,
  /// ilova qayta o'rnatilgan) indeksdan tozalanadi — chip yolg'on "yuklangan"
  /// holatda qolib ketmasin.
  static Future<Map<int, MarketDownload>> forModel(int modelId) async {
    final index = await _readIndex();
    final dir = await directory();
    final alive = <int, MarketDownload>{};
    var changed = false;
    for (final rec in index.values) {
      final exists = await File('${dir.path}/${rec.fileName}').exists();
      if (exists) {
        alive[rec.fileId] = rec;
      } else {
        changed = true;
      }
    }
    if (changed) await _writeIndex(alive);
    return {
      for (final e in alive.entries)
        if (e.value.modelId == modelId) e.key: e.value,
    };
  }

  /// Yozuvga mos absolut yo'l (o'qish vaqtida hisoblanadi).
  static Future<File> fileFor(MarketDownload rec) async =>
      File('${(await directory()).path}/${rec.fileName}');

  /// Baytlarni `Documents/Yuklamalar` ichiga yozadi va indeksni yangilaydi.
  ///
  /// Bir e'londa bir nechta bir xil formatli fayl bo'lishi mumkin (masalan uch
  /// xil DWG), shuning uchun nom band bo'lsa ` (2)`, ` (3)` qo'shiladi.
  static Future<MarketDownload> save({
    required int fileId,
    required int modelId,
    required String title,
    required String format,
    required List<int> bytes,
  }) => saveStream(
    fileId: fileId,
    modelId: modelId,
    title: title,
    format: format,
    stream: Stream<List<int>>.value(bytes),
  );

  /// Oqim (stream) orqali saqlaydi — baytlar diskka kelgan sari yoziladi.
  ///
  /// `.max` fayllar 1.5 GB'gacha bo'ladi; ularni butunlay xotiraga yig'ib olish
  /// (`response.bodyBytes`) qurilmada ilovani o'ldiradi. [onProgress] yuklab
  /// olingan baytlar sonini qaytaradi — UI foizni ko'rsatishi uchun.
  static Future<MarketDownload> saveStream({
    required int fileId,
    required int modelId,
    required String title,
    required String format,
    required Stream<List<int>> stream,
    void Function(int received)? onProgress,
  }) async {
    final dir = await directory();
    final index = await _readIndex();

    // Shu fayl ilgari yuklangan bo'lsa — o'sha nomni qayta ishlatamiz
    // (qayta yuklashda nusxa "(2)" yaratilmasin).
    var name = index[fileId]?.fileName ?? buildFileName(title, format);
    final takenByOthers = {
      for (final r in index.values)
        if (r.fileId != fileId) r.fileName,
    };
    if (takenByOthers.contains(name) ||
        (index[fileId] == null && await File('${dir.path}/$name').exists())) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      var n = 2;
      while (true) {
        final candidate = '$stem ($n)$ext';
        final free =
            !takenByOthers.contains(candidate) &&
            !await File('${dir.path}/$candidate').exists();
        if (free) {
          name = candidate;
          break;
        }
        n++;
      }
    }

    // Avval `.part` faylga yozamiz: yuklash uzilib qolsa, chala fayl tayyor
    // deb indeksga tushmaydi (chip "yuklangan" bo'lib ko'rinib, ochilganda
    // buzuq fayl chiqmasin).
    final target = File('${dir.path}/$name');
    final partial = File('${dir.path}/$name.part');
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Uzilish yoki bekor qilish — chala `.part` diskda qolib ketmasin.
      try {
        await sink.close();
      } catch (_) {}
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);

    final rec = MarketDownload(
      fileId: fileId,
      modelId: modelId,
      fileName: name,
      format: format,
      sizeBytes: received,
      savedAt: DateTime.now(),
    );
    index[fileId] = rec;
    await _writeIndex(index);
    return rec;
  }

  /// Faylni diskdan va indeksdan o'chiradi.
  static Future<void> remove(int fileId) async {
    final index = await _readIndex();
    final rec = index.remove(fileId);
    if (rec != null) {
      final f = File('${(await directory()).path}/${rec.fileName}');
      if (await f.exists()) await f.delete();
      await _writeIndex(index);
    }
  }
}
