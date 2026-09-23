/// AI Baholash 360° — tayyor panoramani `/ai-valuations/upload`
/// (category=panorama) ga yuklaydi va TELEFONDA nusxasini qoldiradi.
///
/// NEGA NUSXA. `PanoCaptureFlow` muvaffaqiyatli yuklashdan keyin capture
/// katalogini (kadrlar + `pano.jpg`) o'chiradi. Bozor panoramani keyin
/// URL bilan ochadi, AI Baholash fayllari esa himoyalangan (ochiq URL yo'q)
/// — eskiz va tur uchun tasvir telefonda qolishi kerak. Nusxa
/// `Application Support/ai_pano/` da turadi va qoralamaga yo'li bilan
/// yoziladi (`AiBaholashBundle.panoramaPaths`).
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import '../../auth/auth_storage.dart';
import '../../panorama/screens/pano_capture_flow.dart';
import '../api_ai_upload_service.dart';

/// [PanoUploadFn] AI Baholash uchun. Natija: `url` — LOKAL nusxa yo'li.
Future<PanoUploadResult?> uploadAiPanorama(String panoPath) async {
  final session = await const AuthStorage().loadSession();
  final token = session.token;
  if (token == null || token.isEmpty) {
    throw AiUploadException('auth required', statusCode: 401);
  }
  final copy = await _keepCopy(panoPath);
  final service = AiUploadService();
  try {
    final keys = await service.upload(
      category: UploadCategory.panorama,
      filePaths: [copy.path],
      token: token,
    );
    if (keys.isEmpty || keys.first.trim().isEmpty) {
      await _silentDelete(copy);
      return null;
    }
    return (key: keys.first, url: copy.path);
  } on Object {
    await _silentDelete(copy);
    rethrow;
  } finally {
    service.dispose();
  }
}

/// Nusxani o'chiradi (xona olib tashlanganda). Xato — jim.
Future<void> deleteAiPanoramaCopy(String? path) async {
  if (path == null || path.isEmpty) return;
  await _silentDelete(File(path));
}

Future<File> _keepCopy(String panoPath) async {
  final root = await getApplicationSupportDirectory();
  final dir = Directory('${root.path}/ai_pano');
  await dir.create(recursive: true);
  final id =
      '${DateTime.now().microsecondsSinceEpoch}_'
      '${math.Random().nextInt(1 << 32).toRadixString(16)}';
  return File(panoPath).copy('${dir.path}/pano_$id.jpg');
}

Future<void> _silentDelete(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } on Object {
    // Keyingi tozalashda ketadi — foydalanuvchiga ta'sir qilmaydi.
  }
}
