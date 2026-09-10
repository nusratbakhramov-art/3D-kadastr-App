import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../data/room_plan_scanner.dart';
import '../widgets/scan_skip_button.dart';
import '../widgets/service_app_bar.dart';
import 'ai_scan_process_screen.dart';
import 'ai_start_screen.dart';

/// AI Baholashning 1-qadami — 3D LiDAR skan.
///
/// Oqim: bu ekran → mesh ko'rish → USDZ ga ishlash → kadastr raqami → ...
/// LiDAR yo'q qurilmalarda (simulator / Pro bo'lmagan iPhone, Android) skan
/// mumkin emas — bu qadam avtomatik o'tkazib yuboriladi va foydalanuvchi
/// to'g'ridan wizardning birinchi qadamiga tushadi.
class AiScanIntroScreen extends StatefulWidget {
  const AiScanIntroScreen({super.key});

  @override
  State<AiScanIntroScreen> createState() => _AiScanIntroScreenState();
}

class _AiScanIntroScreenState extends State<AiScanIntroScreen> {
  /// null = tekshirilmoqda, true/false = qurilma LiDAR ni qo'llaydimi.
  bool? _supported;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    final ok = await RoomPlanScanner.isSupported();
    if (!mounted) return;
    if (!ok) {
      _skipUnsupported();
      return;
    }
    setState(() => _supported = ok);
  }

  /// Qurilma skanni qo'llamasa bu ekranda ushlab turishning ma'nosi yo'q —
  /// darhol wizardning birinchi qadamiga (video olish) o'tamiz.
  /// [Navigator.pushReplacement] — orqaga bosilganda boshi berk ekranga
  /// qaytmaslik uchun. LiDARsiz qurilmada draft AYNAN o'sha qadamda, birinchi
  /// video yuklash oldidan yaratiladi: skan yo'qligi oqimni buzmaydi, chunki
  /// baholash uchun kerakli o'lchov videodan chiqadi.
  void _skipUnsupported() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/start'),
        builder: (_) => const AiStartScreen(),
      ),
    );
  }

  /// Continues to the cadastre step without a 3D scan — for users who can't or
  /// don't want to scan (e.g. no LiDAR). The draft is created by the cadastre
  /// step, which covers the missing scan upload.
  void _skipScan() {
    if (_scanning) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/start'),
        builder: (_) => const AiStartScreen(),
      ),
    );
  }

  Future<void> _startScan() async {
    if (_scanning || _supported != true) return;
    HapticFeedback.lightImpact();
    setState(() => _scanning = true);
    try {
      // v24 custom capture: StreamingTSDF + Polycam-uslub UI, xom skanni
      // saved_scans ga saqlaydi (saved_raw → savedScanId). startScan (Apple
      // stok RoomPlan) EMAS — u eski oqim edi.
      final result =
          await RoomPlanScanner.startTexturedScan(locale: localeNotifier.value);
      if (!mounted) return;
      if (result == null) {
        // Foydalanuvchi bekor qildi.
        setState(() => _scanning = false);
        return;
      }
      if (result.savedScanId == null) {
        setState(() => _scanning = false);
        AppToast.error(context, _S.scanNotSaved(localeNotifier.value));
        return;
      }
      setState(() => _scanning = false);
      // Skan saqlandi — to'g'ridan USDZ ga ishlash (tekstura render) qadamiga.
      // Teksturali natija o'sha yerda "3D modelni ko'rish" orqali ochiladi.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'ai/scan-process'),
          builder: (_) => AiScanProcessScreen(scan: result),
        ),
      );
    } on RoomPlanScannerException catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      AppToast.error(context, '${_S.scanError(localeNotifier.value)}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ServiceAppBar(
                    title: _S.title(l),
                    subtitle: _S.subtitle(l),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    children: [
                      Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppColors.splashGreen.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.view_in_ar_rounded,
                            size: 48,
                            color: AppColors.splashGreen,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _S.heading(l),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          height: 1.25,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _S.body(l),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 14,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _StepsCard(isDark: isDark, locale: l),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _scanning
                          ? const _ScanningButton()
                          : ListingCtaButton(
                              label: _supported == null
                                  ? _S.checking(l)
                                  : _S.startScan(l),
                              enabled: _supported == true,
                              onTap: _startScan,
                            ),
                      // Continue without a scan (no LiDAR, or user choice).
                      const SizedBox(height: 10),
                      ScanSkipButton(
                        label: _S.skipScan(l),
                        enabled: !_scanning,
                        onTap: _skipScan,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanningButton extends StatelessWidget {
  const _ScanningButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(999),
      child: const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.buttonTextBlack),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.isDark, required this.locale});

  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final steps = _S.steps(locale);
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.splashGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: (i < _S.stepAssets.length &&
                            _S.stepAssets[i].isNotEmpty)
                        ? Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.asset(
                              _S.stepAssets[i],
                              fit: BoxFit.contain,
                            ),
                          )
                        : const Icon(
                            Icons.payments_rounded,
                            size: 22,
                            color: AppColors.splashGreen,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 14,
                        height: 1.3,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'services.ai.common.brand_title');

  static String subtitle(Locale l) => tr(l, 'services.ai.scan_intro.subtitle');

  static String heading(Locale l) => tr(l, 'services.ai.scan_intro.heading');

  static String body(Locale l) => tr(l, 'services.ai.scan_intro.body');

  // The 6-step "how it works" flow. Assets live in assets/images/howitworks/;
  // step 5's source 403'd on download, so it has no asset and falls back to a
  // built-in icon (see [_StepsCard]).
  static List<String> steps(Locale l) => [
        tr(l, 'howitworks.step1'),
        tr(l, 'howitworks.step2'),
        tr(l, 'howitworks.step3'),
        tr(l, 'howitworks.step4'),
        tr(l, 'howitworks.step5'),
        tr(l, 'howitworks.step6'),
      ];

  // Parallel to [steps]; empty string ⇒ no asset (fall back to a glyph).
  static const List<String> stepAssets = [
    'assets/images/howitworks/step1.png',
    'assets/images/howitworks/step2.png',
    'assets/images/howitworks/step3.png',
    'assets/images/howitworks/step4.png',
    'assets/images/howitworks/step5.png',
    'assets/images/howitworks/step6.png',
  ];

  static String startScan(Locale l) => tr(l, 'services.ai.scan_intro.start_scan');

  static String skipScan(Locale l) =>
      tr(l, 'services.ai.scan_intro.skip_scan');

  static String checking(Locale l) => tr(l, 'services.ai.scan_intro.checking');

  static String scanError(Locale l) => tr(l, 'services.ai.scan_intro.scan_error');

  static String scanNotSaved(Locale l) =>
      tr(l, 'services.ai.scan_intro.scan_not_saved');
}
