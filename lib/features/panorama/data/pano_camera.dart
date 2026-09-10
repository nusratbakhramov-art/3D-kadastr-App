/// `camera` plagini ustidagi yupqa qatlam — 360° capture uchun.
///
/// Ikki ish qiladi va boshqa hech nima:
///  1. `CameraController` ning hayot siklini bitta joyga yig'adi
///     ([open] / [takePicture] / [dispose]);
///  2. o'sha hayot siklini [CameraGuard] ijarasi bilan bog'laydi — controller
///     tirik ekan `panorama` ijarasi ushlab turiladi, o'lgan zahoti bo'shaydi.
///
/// NEGA aynan shu joyda. `CameraController` ni ekran o'zi yaratsa, ekran
/// yiqilganda yoki `initState` da istisno bo'lganda `dispose` chaqirilmay
/// qolishi mumkin va ijara qotib qoladi. Shu sababli ijarani olish va
/// bo'shatish MANA SHU sinfdan tashqariga chiqarilmagan, va har bir yo'lda
/// `finally`/`catch` bilan qoplangan.
///
/// Preview widget'i ([CameraPreview]) uchun controller [controller] orqali
/// oshkor qilinadi — bu ataylab: `PanoCamera` UI qurmaydi.
library;

import 'package:camera/camera.dart';

import 'camera_guard.dart';

class PanoCameraException implements Exception {
  const PanoCameraException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'PanoCameraException($code): $message';
}

class PanoCamera {
  PanoCamera();

  CameraController? _controller;
  bool _hasLease = false;

  /// `CameraPreview(camera.controller!)` uchun. Ochilmagan bo'lsa `null`.
  CameraController? get controller => _controller;

  bool get isOpen => _controller?.value.isInitialized ?? false;

  /// Kamerani ochadi va [controller] ni tayyorlaydi.
  ///
  /// Kamera boshqa egasi qo'lida bo'lsa — [CameraBusyException] (yiqilish
  /// emas, ushlab olinadigan xato). Qurilmada mos linza bo'lmasa yoki
  /// `initialize()` yiqilsa — [PanoCameraException], VA ijara bo'shatiladi:
  /// yarim ochilgan kamera ijarani ushlab turmasligi kerak.
  ///
  /// [preset] `max` — panorama tikuvchisiga eng katta kadr kerak.
  /// [enableAudio] `false` — ovoz kerak emas, va `true` bo'lsa Android'da
  /// `RECORD_AUDIO` ruxsati so'raladi (u Play Console'da data-safety savoli
  /// ochadi).
  Future<void> open({
    ResolutionPreset preset = ResolutionPreset.max,
    CameraLensDirection lens = CameraLensDirection.back,
  }) async {
    if (_controller != null) return; // allaqachon ochiq — qayta ochmaymiz

    final blocker = CameraGuard.holder;
    if (!CameraGuard.acquire(CameraGuard.panorama)) {
      throw CameraBusyException(CameraGuard.panorama, blocker ?? 'unknown');
    }
    _hasLease = true;

    CameraController? created;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const PanoCameraException(
          'NO_CAMERA',
          'Qurilmada kamera topilmadi',
        );
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == lens,
        orElse: () => cameras.first,
      );
      created = CameraController(
        description,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await created.initialize();
      _controller = created;
    } on CameraException catch (e) {
      await _disposeController(created);
      _releaseLease();
      throw PanoCameraException(e.code, e.description ?? 'Kamera ochilmadi');
    } catch (_) {
      // ⚠️ Har qanday boshqa istisno ham ijarani bo'shatishi SHART — aks holda
      // bitta yiqilgan `open` butun sessiya uchun kamerani yopib qo'yadi.
      await _disposeController(created);
      _releaseLease();
      rethrow;
    }
  }

  /// Bitta kadr. Kamera ochilmagan bo'lsa [PanoCameraException].
  Future<XFile> takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw const PanoCameraException('NOT_OPEN', 'Kamera ochilmagan');
    }
    try {
      return await c.takePicture();
    } on CameraException catch (e) {
      throw PanoCameraException(e.code, e.description ?? 'Kadr olinmadi');
    }
  }

  /// Kamerani yopadi va ijarani bo'shatadi. Ikki marta chaqirilsa xavfsiz.
  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    try {
      await _disposeController(c);
    } finally {
      // `dispose()` ning o'zi yiqilsa ham ijara bo'shashi shart.
      _releaseLease();
    }
  }

  Future<void> _disposeController(CameraController? c) async {
    if (c == null) return;
    try {
      await c.dispose();
    } catch (_) {
      // Yopishdagi xato ahamiyatsiz — controller baribir tashlanadi.
    }
  }

  void _releaseLease() {
    if (!_hasLease) return;
    _hasLease = false;
    CameraGuard.release(CameraGuard.panorama);
  }
}
