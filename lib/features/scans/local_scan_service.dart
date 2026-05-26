import 'package:flutter/services.dart';

/// Local skanlar — Documents/scans/ ichidagi numbered USDZ fayllar.
/// Auth talab qilmaydi, to'liq qurilmada.
class LocalScanItem {
  LocalScanItem({
    required this.id,
    required this.name,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
    required this.areaSqm,
    required this.photoCount,
  });

  final int id;
  final String name;
  final String fileName;
  final DateTime createdAt;
  final int sizeBytes;
  final double areaSqm;
  final int photoCount;

  String get sizeFormatted {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static LocalScanItem fromJson(Map<dynamic, dynamic> j) {
    final createdAtNum = (j['createdAt'] as num?) ?? 0;
    return LocalScanItem(
      id: (j['id'] as num).toInt(),
      name: (j['name'] as String?) ?? 'Skan',
      fileName: (j['fileName'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (createdAtNum * 1000).toInt(),
      ),
      sizeBytes: ((j['sizeBytes'] as num?) ?? 0).toInt(),
      areaSqm: ((j['areaSqm'] as num?) ?? 0).toDouble(),
      photoCount: ((j['photoCount'] as num?) ?? 0).toInt(),
    );
  }
}

class LocalScanService {
  static const _channel = MethodChannel('kadastr/local_scans');

  /// Hamma local skanlarni qaytaradi (newest first).
  Future<List<LocalScanItem>> list() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('list');
      if (result == null) return [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(LocalScanItem.fromJson)
          .toList();
    } on PlatformException {
      return [];
    }
  }

  /// Belgilangan id bo'yicha scan faylining qurilma yo'lini qaytaradi.
  Future<String?> getPath(int id) async {
    try {
      return await _channel.invokeMethod<String?>('getPath', {'id': id});
    } on PlatformException {
      return null;
    }
  }

  /// Scan'ni o'chiradi (fayl + index'dan).
  Future<bool> delete(int id) async {
    try {
      final ok = await _channel.invokeMethod<bool>('delete', {'id': id});
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Scan nomini o'zgartiradi.
  Future<bool> rename(int id, String newName) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('rename', {'id': id, 'name': newName});
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }
}
