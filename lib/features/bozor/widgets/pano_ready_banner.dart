/// Sehrgar tepasidagi «360° panorama tayyor» lentasi.
///
/// NEGA O'RAM. Panorama fonda ~7–9 daqiqa tikiladi va shu vaqt ichida
/// foydalanuvchi sehrgarning istalgan qadamida bo'lishi mumkin. Har bir
/// qadam ekrani O'Z `Scaffold` iga ega va umumiy qobiq yo'q — shuning uchun
/// lenta `bozorStepScreen` ning natijasini o'raydi: bitta joy, hamma qadam.
///
/// ⚠️ KUZATUVCHINI HAM SHU O'RAM TIRIK TUTADI. Foydalanuvchi «Tavsif»
/// qadamidan chiqib ketsa ham tikish kuzatilishi kerak, aks holda tayyor
/// bo'lgan panorama qoralamaga yozilmay qolardi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/pano_job_watcher.dart';
import '../models/bozor_draft.dart';

class PanoReadyBanner extends StatefulWidget {
  const PanoReadyBanner({
    super.key,
    required this.draft,
    required this.child,
    this.watcher,
  });

  final BozorDraft draft;
  final Widget child;

  /// Faqat testlar uchun.
  final PanoJobWatcher? watcher;

  @override
  State<PanoReadyBanner> createState() => _PanoReadyBannerState();
}

class _PanoReadyBannerState extends State<PanoReadyBanner> {
  late final PanoJobWatcher _watcher = widget.watcher ?? PanoJobWatcher.instance;

  /// Lenta shuncha turadi.
  ///
  /// O'chirish tugmasi ham bor, lekin foydalanuvchi bosmasa ham xabar
  /// abadiy qolib ketmasin: u faqat «qarab qo'ying» deydi, harakat
  /// talab qilmaydi.
  static const Duration kVisible = Duration(seconds: 12);

  int _ready = 0;

  @override
  void initState() {
    super.initState();
    _watcher
      ..addListener(_onChanged)
      ..watch(widget.draft);
    _onChanged();
  }

  @override
  void dispose() {
    _watcher.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final fresh = _watcher.takeReady();
    if (fresh.isEmpty || !mounted) return;
    setState(() => _ready += fresh.length);
    // ⚠️ Kechikkan `setState` — vidjet o'lgan bo'lishi mumkin.
    Future<void>.delayed(kVisible, () {
      if (mounted) setState(() => _ready = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == 0) return widget.child;
    final l = Localizations.localeOf(context);

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.of(context).padding.top + 8,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: AppColors.brandGreen,
              borderRadius: BorderRadius.circular(14),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(l, 'bozor.pano.ready.banner'),
                        style: const TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 18),
                      onPressed: () => setState(() => _ready = 0),
                      tooltip: tr(l, 'common.cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
