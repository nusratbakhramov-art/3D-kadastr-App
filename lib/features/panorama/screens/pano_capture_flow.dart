/// 360° panorama: suratga olish → kadrlarni yuborish → EKRAN YOPILADI.
///
/// ⚠️ TIKISH BU YERDA KUTILMAYDI. Ilgari foydalanuvchi natijani shu ekranda
/// kutardi. O'lchov (prod `celery-panorama` logi, 2026-09-12) tikish
/// **7–9 daqiqa** olishini ko'rsatdi:
///
///     ish 7 → 420.5 s   ish 9  → 459.4 s   ish 15 → 567.1 s
///     ish 8 → 451.2 s   ish 10 → 474.1 s
///
/// Uchta xonaga bu yarim soatlik qotib turish demakdi. Endi ekran kadrlar
/// yuborilishi bilan yopiladi va ISHNING RAQAMINI qaytaradi; tikilishini
/// `PanoJobWatcher` fonda kuzatadi.
///
/// Nega bu ekran baribir kerak: nativ capture va kadrlarni yuklash — ikki
/// bosqich va ikkalasining ham progressi bor. Ularni tavsif qadamiga solsak
/// u ekran tarmoq holati bilan to'lib ketardi.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/pano_api.dart';
import '../data/pano_capture_channel.dart';

/// Serverga topshirilgan tikish ishi.
///
/// ⚠️ Bu TAYYOR PANORAMA EMAS — kadrlar yuborildi va navbatga qo'yildi,
/// xolos. Natija `PanoJobWatcher` orqali keladi.
@immutable
class PanoOutcome {
  const PanoOutcome({required this.jobId});

  /// `bozor_pano_jobs.id` — kuzatuv shu bo'yicha boradi.
  final int jobId;
}

/// Ekranni ochadi. Bekor qilinsa yoki yuklash yiqilsa `null`.
Future<PanoOutcome?> openPanoCapture(BuildContext context) =>
    Navigator.of(context).push<PanoOutcome>(
      MaterialPageRoute<PanoOutcome>(builder: (_) => const PanoCaptureFlow()),
    );

/// Oqimning qaysi bosqichida turibmiz.
///
/// «Tikilmoqda» bosqichi YO'Q — u fonga ko'chdi.
enum _Stage { capturing, uploading, failed }

class PanoCaptureFlow extends StatefulWidget {
  const PanoCaptureFlow({super.key, this.api});

  /// Faqat testlar uchun.
  final PanoApi? api;

  @override
  State<PanoCaptureFlow> createState() => PanoCaptureFlowState();
}

/// ⚠️ OCHIQ (xususiy emas) FAQAT test uchun.
class PanoCaptureFlowState extends State<PanoCaptureFlow> {
  late final PanoApi _api = widget.api ?? PanoApi();

  _Stage _stage = _Stage.capturing;
  double _progress = 0;
  String _note = '';
  String? _error;

  PanoCaptureResult? _capture;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Ekran chizilgandan KEYIN boshlanadi — nativ ekran shu Navigator ustiga
    // modal bo'lib chiqadi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final shot = await PanoCaptureChannel.start(context);
      if (!mounted) return;
      if (shot == null) {
        Navigator.of(context).pop(); // bekor qilindi
        return;
      }
      _capture = shot;
      await _upload(shot);
    } on Object catch (e) {
      _fail(e);
    }
  }

  Future<void> _upload(PanoCaptureResult shot) async {
    setState(() {
      _stage = _Stage.uploading;
      _progress = 0;
    });

    final metaFile = File('${shot.dir}/meta.json');
    if (!metaFile.existsSync()) {
      _fail(StateError('meta.json topilmadi'));
      return;
    }
    final metas = (jsonDecode(await metaFile.readAsString()) as List)
        .cast<Map<String, dynamic>>();
    if (metas.isEmpty) {
      _fail(StateError('kadrlar yoʻq'));
      return;
    }

    final job = await _api.createJob();

    for (var i = 0; i < metas.length; i++) {
      if (!mounted) return;
      final m = metas[i];
      final f = File('${shot.dir}/${m['file']}');
      if (!f.existsSync()) continue;
      await _api.uploadFrame(jobId: job.id, image: f, meta: m);
      if (!mounted) return;
      setState(() {
        _progress = (i + 1) / metas.length;
        _note = '${i + 1}/${metas.length}';
      });
    }

    await _api.finish(job.id);
    if (!mounted) return;

    // Kadrlar SERVERDA — telefondagi nusxa endi kerak emas (bitta tushirish
    // ~6 MB, foydalanuvchi esa ketma-ket bir necha xona oladi).
    //
    // ⚠️ AYNAN SHU YERDA — `finish` MUVAFFAQIYATLI bo'lgandan keyin.
    // Ilgariroq o'chirsak, `finish` tarmoq sababli yiqilganda qayta urinish
    // uchun hech narsa qolmasdi. Serverdagi TIKISH yiqilsa esa lokal kadrlar
    // baribir kerak emas: server ularni 24 soat saqlaydi va qayta urinish
    // o'sha yerdan ketadi.
    await _capture?.cleanUp();
    if (!mounted) return;
    Navigator.of(context).pop(PanoOutcome(jobId: job.id));
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      // Nativ taraf xatoni `PlatformException` qilib qaytaradi (masalan
      // ARCore o'rnatilmagan). Uning `toString()` i «PlatformException(
      // CAPTURE_FAILED, …, null, null)» bo'ladi — foydalanuvchiga shu
      // ko'rinishda chiqarish mumkin emas.
      _error = switch (e) {
        PanoApiException(:final message) => message,
        PlatformException(:final message?) => message,
        _ => e.toString(),
      };
    });
  }

  Future<void> _retry() async {
    final shot = _capture;
    setState(() => _error = null);
    // Kadrlar hali diskda bo'lsa qaytadan suratga olmaymiz — faqat yuklashni
    // takrorlaymiz. Bu eng qimmat qismni (foydalanuvchining 30 nishonni
    // aylanib chiqishini) tejaydi.
    if (shot != null && shot.directory.existsSync()) {
      try {
        await _upload(shot);
      } on Object catch (e) {
        _fail(e);
      }
    } else {
      setState(() => _stage = _Stage.capturing);
      await _run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return PopScope(
      // Kadrlar yuborilyapti — orqaga qaytish ularni yarim yo'lda qoldiradi
      // va server hech qachon `finish` olmaydi. Ataylab bloklaymiz; chiqish
      // yo'li xato holatida beriladi.
      canPop: _stage == _Stage.failed,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _stage == _Stage.failed
                  ? _errorView(l, fg)
                  : _busyView(l, fg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _busyView(Locale l, Color fg) {
    final title = _stage == _Stage.capturing
        ? tr(l, 'bozor.pano.flow.opening')
        : tr(l, 'bozor.pano.flow.uploading');
    // Nativ ekran ochilayotganda progress noma'lum — aylanuvchi ko'rsatkich.
    final value = _stage == _Stage.capturing ? null : _progress.clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 4,
            color: AppColors.splashGreen,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: fg,
          ),
        ),
        if (_note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _note,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: fg.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _errorView(Locale l, Color fg) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        Icons.error_outline_rounded,
        size: 44,
        color: Color(0xFFE0492A),
      ),
      const SizedBox(height: 16),
      Text(
        tr(l, 'bozor.pano.flow.failed'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: fg,
        ),
      ),
      if ((_error ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13,
            color: fg.withValues(alpha: 0.6),
          ),
        ),
      ],
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(l, 'common.cancel')),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _retry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.splashGreen,
            ),
            child: Text(tr(l, 'bozor.pano.flow.retry')),
          ),
        ],
      ),
    ],
  );
}
