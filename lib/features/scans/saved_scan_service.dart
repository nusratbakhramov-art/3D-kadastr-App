import 'package:flutter/services.dart';

/// Saqlangan raw scan natijasi (texturing'dan oldin) — Documents/saved_scans/.
/// Phase 7: foydalanuvchi Done bossa, ARKit anchors + photos + poses + depths
/// shu storage'ga ko'chiriladi. Texturing keyin "Process" tugmasi orqali ishga
/// tushiriladi. Har process attempt yangi versiya sifatida saqlanadi.
class SavedScanOutput {
  const SavedScanOutput({
    required this.version,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
    required this.params,
  });

  final int version;
  final String fileName;
  final DateTime createdAt;
  final int sizeBytes;
  final Map<String, String> params;

  String get sizeFormatted {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static SavedScanOutput fromJson(Map<dynamic, dynamic> j) {
    final createdAtNum = (j['createdAt'] as num?) ?? 0;
    final paramsRaw = (j['params'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final params = <String, String>{};
    paramsRaw.forEach((k, v) {
      params['$k'] = '$v';
    });
    return SavedScanOutput(
      version: (j['version'] as num).toInt(),
      fileName: (j['fileName'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (createdAtNum * 1000).toInt(),
      ),
      sizeBytes: ((j['sizeBytes'] as num?) ?? 0).toInt(),
      params: params,
    );
  }
}

class SavedScanItem {
  const SavedScanItem({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.photoCount,
    required this.areaSqm,
    required this.outputs,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final int photoCount;
  final double areaSqm;
  final List<SavedScanOutput> outputs;

  bool get isProcessed => outputs.isNotEmpty;

  static SavedScanItem fromJson(Map<dynamic, dynamic> j) {
    final createdAtNum = (j['createdAt'] as num?) ?? 0;
    final outsRaw = (j['outputs'] as List<dynamic>?) ?? const <dynamic>[];
    final outs = outsRaw
        .whereType<Map<dynamic, dynamic>>()
        .map(SavedScanOutput.fromJson)
        .toList();
    outs.sort((a, b) => b.version.compareTo(a.version));
    return SavedScanItem(
      id: (j['id'] as num).toInt(),
      name: (j['name'] as String?) ?? 'Skan',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (createdAtNum * 1000).toInt(),
      ),
      photoCount: ((j['photoCount'] as num?) ?? 0).toInt(),
      areaSqm: ((j['areaSqm'] as num?) ?? 0).toDouble(),
      outputs: outs,
    );
  }
}

class SavedScanProcessResult {
  const SavedScanProcessResult({
    required this.scanId,
    required this.version,
    required this.filePath,
    required this.fileSize,
  });

  final int scanId;
  final int version;
  final String filePath;
  final int fileSize;

  static SavedScanProcessResult? tryFromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return null;
    final scanId = (m['scanId'] as num?)?.toInt();
    final version = (m['version'] as num?)?.toInt();
    final path = m['filePath'] as String?;
    if (scanId == null || version == null || path == null) return null;
    return SavedScanProcessResult(
      scanId: scanId,
      version: version,
      filePath: path,
      fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Skan to'plamidagi bitta artefakt fayl (native listScanFiles'dan).
/// [type] backend `scan_files` shakliga mos: `glb`/`usdz`/`geo`/`png`/
/// `geometry_bin`/`mesh_ply`/`mesh_usdz`/`manifest`/`frames_json`/`frame`.
class ScanFile {
  const ScanFile({
    required this.path,
    required this.type,
    required this.sizeBytes,
    this.rel = '',
  });

  final String path; // to'liq qurilma yo'li (upload uchun)
  final String rel; // skan papkasiga nisbatan yo'l (ko'rsatish uchun)
  final String type;
  final int sizeBytes;

  bool get isFrame => type == 'frame';

  static ScanFile? fromMap(Map<dynamic, dynamic> j) {
    final path = j['path'] as String?;
    final type = j['type'] as String?;
    if (path == null || type == null) return null;
    return ScanFile(
      path: path,
      type: type,
      rel: (j['rel'] as String?) ?? '',
      sizeBytes: ((j['sizeBytes'] as num?) ?? 0).toInt(),
    );
  }

  /// Upload-bundle uchun record shaklida (api_ai_upload_service.uploadBundle).
  ({String path, String type, int sizeBytes}) get entry =>
      (path: path, type: type, sizeBytes: sizeBytes);
}

class SavedScanService {
  static const _channel = MethodChannel('kadastr/saved_scans');
  static const _previewChannel = MethodChannel('kadastr/room_plan_scanner');

  /// Saqlangan scan'larni ro'yxat sifatida (yangidan eskiga sorted).
  Future<List<SavedScanItem>> list() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('list');
      if (raw == null) return [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(SavedScanItem.fromJson)
          .toList();
    } on PlatformException {
      return [];
    }
  }

  /// Belgilangan ID bo'yicha scan detail (outputs bilan).
  Future<SavedScanItem?> get(int id) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'get', {'id': id},
      );
      if (raw == null) return null;
      return SavedScanItem.fromJson(raw);
    } on PlatformException {
      return null;
    }
  }

  /// Saqlangan scan'ni qayta ishlash (texturing pipeline'ni ishga tushirish).
  /// Bu native modal overlay ochadi, jarayon tugaguncha kutadi.
  Future<SavedScanProcessResult?> process(
    int id, {
    Map<String, String> params = const {},
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'process',
        {'id': id, 'params': params},
      );
      return SavedScanProcessResult.tryFromMap(raw);
    } on PlatformException catch (e) {
      throw Exception('Qayta ishlash xatosi: ${e.message ?? e.code}');
    }
  }

  /// Skanning BARCHA artefakt fayllari (rasmlar, glb, usdz, mesh, geo/png,
  /// manifest, frames.json) — backendga to'liq yuklash uchun. Har biri
  /// {path, type, sizeBytes}. Native Documents/Scans/scanNNN/ ni sanaydi.
  Future<List<ScanFile>> listScanFiles(int id) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listScanFiles', {'id': id},
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(ScanFile.fromMap)
          .whereType<ScanFile>()
          .toList();
    } on PlatformException {
      return const [];
    }
  }

  /// Xom LiDAR mesh (anchors.bin) ni textura'siz clay USDZ sifatida eksport
  /// qiladi va temp yo'lini qaytaradi. Pipeline'siz, tez. Versiya saqlanmaydi.
  Future<String?> viewLidarMesh(int id) async {
    try {
      return await _channel.invokeMethod<String?>('viewLidarMesh', {'id': id});
    } on PlatformException catch (e) {
      throw Exception('LiDAR mesh xatosi: ${e.message ?? e.code}');
    }
  }

  /// Output USDZ ning to'liq qurilma yo'lini qaytaradi.
  Future<String?> outputPath(int id, int version) async {
    try {
      return await _channel.invokeMethod<String?>(
        'outputPath', {'id': id, 'version': version},
      );
    } on PlatformException {
      return null;
    }
  }

  Future<bool> delete(int id) async {
    try {
      final ok = await _channel.invokeMethod<bool>('delete', {'id': id});
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> deleteOutput(int id, int version) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'deleteOutput', {'id': id, 'version': version},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> rename(int id, String newName) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'rename', {'id': id, 'name': newName},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// USDZ faylini iOS native preview'ga (Quick Look) yuborish.
  Future<void> preview(String filePath) async {
    try {
      await _previewChannel.invokeMethod('previewModel', {'filePath': filePath});
    } on PlatformException {
      // ignore — caller toast ko'rsatadi
    }
  }
}
