/// DEV-ONLY probe — kamera egaligi ziddiyatini QURILMADA tekshirish uchun.
///
/// Bu ekran mahsulot oqimining qismi EMAS va hech qayerdan bog'lanmagan; uni
/// `tool/pano/README.md` dagi «Probe ekrani» bo'limida yozilganidek vaqtincha
/// `main.dart` ning `home:` iga qo'yib ochiladi. `AppEnv.isAdmin` (ya'ni debug
/// build + `.env` da `admin=true`) bo'lmasa hech qanday tugma chizilmaydi.
///
/// Uchta tugma uchta savolga javob beradi:
///  1. `camera` plagini yolg'iz o'zi ishlaydimi (preview chiqadimi);
///  2. mavjud `kadastr/video_capture` yo'li avvalgidek ishlaydimi;
///  3. ikkalasi BIR VAQTDA so'ralganda nima bo'ladi — [CameraGuard] ni
///     yiqilishga aylantirmasdan to'xtatadimi.
///
/// ⚠️ Matnlar ATAYLAB tarjima qilinmagan: bu ekran hech qachon relizga
/// chiqmaydi, `assets/i18n/bundle.json` ga esa har bir kalit backend seed'iga
/// ham qo'shilishi kerak. Bir martalik dev vositasi uchun bu narx o'rinsiz.
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/app_env.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/color_tokens.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../services/data/video_capture.dart';
import '../data/camera_guard.dart';
import '../data/pano_camera.dart';

class PanoCameraProbeScreen extends StatefulWidget {
  const PanoCameraProbeScreen({super.key});

  @override
  State<PanoCameraProbeScreen> createState() => _PanoCameraProbeScreenState();
}

class _PanoCameraProbeScreenState extends State<PanoCameraProbeScreen> {
  final PanoCamera _camera = PanoCamera();
  final List<String> _lines = <String>[];
  bool _busy = false;

  @override
  void dispose() {
    // Ekran yopilganda ijara ham bo'shashi shart — aks holda probe'dan
    // chiqqandan keyin kamera butun sessiya davomida band qolib ketadi.
    _camera.dispose();
    super.dispose();
  }

  void _log(String line) {
    if (!mounted) return;
    final t = DateTime.now();
    final stamp =
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${(t.millisecond ~/ 100)}';
    setState(() {
      _lines.insert(0, '$stamp  $line');
      if (_lines.length > 40) _lines.removeLast();
    });
  }

  /// 1-tugma — panorama preview'ni ochadi/yopadi.
  Future<void> _togglePreview() async {
    if (_camera.isOpen) {
      await _camera.dispose();
      _log('panorama: yopildi');
      if (mounted) setState(() {});
      return;
    }
    await _guarded(() async {
      await _camera.open();
      _log('panorama: OCHILDI '
          '(${_camera.controller?.value.previewSize ?? "?"})');
    });
  }

  /// 2-tugma — mavjud video capture yo'li.
  Future<void> _videoCapture() async {
    await _guarded(() async {
      try {
        final result = await VideoCapture.capture();
        _log(result == null
            ? 'video: bekor qilindi (null)'
            : 'video: OK ${result.summary}');
      } on VideoCaptureException catch (e) {
        _log('video: XATO ${e.code} — ${e.message}');
      }
    });
  }

  /// 3-tugma — ziddiyat sinovi. Preview ochiq turganda video capture
  /// chaqiriladi: KUTILGAN natija — `CameraBusyException`, YIQILISH EMAS.
  Future<void> _conflict() async {
    await _guarded(() async {
      if (!_camera.isOpen) {
        await _camera.open();
        _log('panorama: OCHILDI (ziddiyat sinovi uchun)');
      }
      try {
        final result = await VideoCapture.capture();
        _log('⚠️ video guard\'dan O\'TDI — ziddiyat to\'xtatilmadi '
            '(${result?.summary ?? "null"})');
      } on VideoCaptureException catch (e) {
        // `VideoCapture` guard xatosini o'z turiga o'girib beradi, ya'ni
        // mavjud chaqiruvchilar uni avvalgidek ushlaydi.
        _log(e.code == VideoCapture.busyCode
            ? '✅ KUTILGANDEK: ${CameraGuard.holder} ushlab turibdi, '
                'video rad etildi'
            : '⚠️ boshqa xato: $e');
      }
    });
  }

  /// Har bir tugma bitta joyda o'raladi: qayta bosishni bloklaydi va har
  /// qanday istisnoni ekranga chiqaradi (probe'ning butun ma'nosi shu —
  /// xatoni YASHIRMASLIK).
  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on CameraBusyException catch (e) {
      _log('BUSY: $e');
    } catch (e) {
      _log('XATO: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.isAdmin) {
      return Scaffold(
        backgroundColor: ColorTokens.scaffoldBg(context),
        body: Center(
          child: Text(
            'DEV only',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: ColorTokens.secondaryText(context),
            ),
          ),
        ),
      );
    }

    final holder = CameraGuard.holder;
    final preview = _camera.controller;

    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Camera probe (DEV)',
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: ColorTokens.primaryText(context),
                ),
              ),
              const SizedBox(height: 6),
              _StatusPill(holder: holder, heldFor: CameraGuard.heldFor),
              const SizedBox(height: 12),
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: preview != null && preview.value.isInitialized
                        ? CameraPreview(preview)
                        : Text(
                            'preview yopiq',
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListingCtaButton(
                label: _camera.isOpen
                    ? '1 · Panorama preview — YOP'
                    : '1 · Panorama preview — OCH',
                enabled: !_busy,
                onTap: _togglePreview,
              ),
              const SizedBox(height: 8),
              ListingCtaButton(
                label: '2 · Video capture',
                enabled: !_busy,
                onTap: _videoCapture,
              ),
              const SizedBox(height: 8),
              ListingCtaButton(
                label: '3 · Ikkalasi birga (ziddiyat)',
                enabled: !_busy,
                onTap: _conflict,
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ColorTokens.cardBg(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ColorTokens.outline(context)),
                  ),
                  child: _lines.isEmpty
                      ? Text(
                          'natija shu yerda chiqadi',
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 12,
                            color: ColorTokens.tertiaryText(context),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _lines.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: SelectableText(
                              _lines[i],
                              style: TextStyle(
                                fontFamily: 'MTSText',
                                fontSize: 12,
                                height: 1.3,
                                color: ColorTokens.primaryText(context),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.holder, required this.heldFor});

  final String? holder;
  final Duration? heldFor;

  @override
  Widget build(BuildContext context) {
    final free = holder == null;
    final text = free
        ? 'CameraGuard: bo\'sh'
        : 'CameraGuard: $holder (${heldFor?.inSeconds ?? 0}s)';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: free
              ? AppColors.splashGreen.withValues(alpha: 0.18)
              : AppColors.declineRed.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 12,
            color: ColorTokens.primaryText(context),
          ),
        ),
      ),
    );
  }
}
