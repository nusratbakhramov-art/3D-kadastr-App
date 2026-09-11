/// 360° panorama: suratga olish → yuklash → serverda tikish → natija.
///
/// Foydalanuvchi shu ekranda KUTADI (mahsulot qarori): tikish ~30 s, unga
/// yuklash qo'shiladi. Kutgani uchun tayyor bo'lgach panoramani darhol
/// ko'radi va keyingi xonaga o'tadi; barcha xonalar yig'ilgach turni
/// hozirgidek qo'yadi.
///
/// Nega bu ekran bor. Uchta bosqichni (nativ capture, yuklash, polling)
/// tavsif qadamiga solsak, u ekran tarmoq holati bilan to'lib ketardi.
/// Bu yerda ular bitta joyda va bitta progress chizig'iga aylanadi.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/pano_api.dart';
import '../data/pano_capture_channel.dart';

/// Tayyor panorama — e'longa shu qo'shiladi.
@immutable
class PanoOutcome {
  const PanoOutcome({required this.storageKey, required this.url});

  /// `listings/media/{user_id}/pano_*.jpg` — e'lonning media kaliti.
  final String storageKey;
  final String url;
}

/// Ekranni ochadi. Bekor qilinsa yoki xato bo'lsa `null`.
Future<PanoOutcome?> openPanoCapture(BuildContext context) =>
    Navigator.of(context).push<PanoOutcome>(
      MaterialPageRoute<PanoOutcome>(builder: (_) => const PanoCaptureFlow()),
    );

/// Oqimning qaysi bosqichida turibmiz.
enum _Stage { capturing, uploading, stitching, failed }

class PanoCaptureFlow extends StatefulWidget {
  const PanoCaptureFlow({super.key, this.api});

  /// Faqat testlar uchun.
  final PanoApi? api;

  @override
  State<PanoCaptureFlow> createState() => _PanoCaptureFlowState();
}

class _PanoCaptureFlowState extends State<PanoCaptureFlow> {
  late final PanoApi _api = widget.api ?? PanoApi();

  _Stage _stage = _Stage.capturing;
  double _progress = 0;
  String _note = '';
  String? _error;

  PanoCaptureResult? _capture;
  Timer? _poll;
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
    _poll?.cancel();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final shot = await PanoCaptureChannel.start(context);
      if (!mounted) return;
      if (shot == null) {
        Navigator.of(context).pop();   // bekor qilindi
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
      _fail(StateError('kadrlar yo\'q'));
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
    setState(() {
      _stage = _Stage.stitching;
      _progress = 0;
      _note = '';
    });
    _startPolling(job.id);
  }

  void _startPolling(int jobId) {
    // 1.5 s — serverdagi progress ham shu tezlikda yangilanadi
    // (`_PROGRESS_MIN_INTERVAL_S`), tez-tez so'rashning ma'nosi yo'q.
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      try {
        final job = await _api.status(jobId);
        if (!mounted) return;
        if (job.isDone) {
          t.cancel();
          await _capture?.cleanUp();   // kadrlar endi kerak emas
          if (!mounted) return;
          final key = job.storageKey;
          if (key == null || key.isEmpty) {
            _fail(StateError('server kalit qaytarmadi'));
            return;
          }
          Navigator.of(context).pop(
            PanoOutcome(storageKey: key, url: job.url ?? ''),
          );
          return;
        }
        if (job.isError) {
          t.cancel();
          _fail(PanoApiException(job.error ?? 'tikib boʻlmadi'));
          return;
        }
        setState(() {
          _progress = job.progress;
          _note = job.message ?? '';
        });
      } on Object catch (e) {
        // Bitta so'rov yiqilsa to'xtamaymiz — tarmoq bir lahzaga uzilgan
        // bo'lishi mumkin va tikish serverda davom etyapti.
        debugPrint('pano polling: $e');
      }
    });
  }

  void _fail(Object e) {
    _poll?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _error = e is PanoApiException ? e.message : e.toString();
    });
  }

  Future<void> _retry() async {
    final shot = _capture;
    _poll?.cancel();
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
      // Tikish serverda davom etyapti — orqaga qaytish uni to'xtatmaydi,
      // lekin foydalanuvchi natijasiz qoladi. Ataylab bloklaymiz; chiqish
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
    final title = switch (_stage) {
      _Stage.capturing => tr(l, 'bozor.pano.flow.opening'),
      _Stage.uploading => tr(l, 'bozor.pano.flow.uploading'),
      _ => tr(l, 'bozor.pano.flow.stitching'),
    };
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
        if (_stage == _Stage.stitching) ...[
          const SizedBox(height: 16),
          Text(
            tr(l, 'bozor.pano.flow.wait_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12,
              height: 1.4,
              color: fg.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _errorView(Locale l, Color fg) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline_rounded, size: 44, color: Color(0xFFE0492A)),
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
