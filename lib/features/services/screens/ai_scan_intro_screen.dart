import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../data/room_plan_scanner.dart';
import '../widgets/service_app_bar.dart';
import 'ai_cadastre_screen.dart';
import 'ai_scan_process_screen.dart';

/// AI Baholashning 1-qadami — 3D LiDAR skan.
///
/// Oqim: bu ekran → mesh ko'rish → USDZ ga ishlash → kadastr raqami → ...
/// LiDAR yo'q qurilmalarda (simulator / Pro bo'lmagan iPhone) skan
/// qo'llab-quvvatlanmaydi, lekin "O'tkazib yuborish" bilan skansiz davom
/// etish mumkin (payment integratsiya / test uchun).
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
    setState(() => _supported = ok);
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

  /// Skanni o'tkazib yuborib, to'g'ridan kadastr qadamiga o'tadi (scan: null).
  /// Payment integratsiya / LiDAR yo'q qurilmada test uchun.
  void _skip() {
    if (_scanning) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AiCadastreScreen(),
      ),
    );
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
    final unsupported = _supported == false;

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
                      if (unsupported) ...[
                        const SizedBox(height: 16),
                        _UnsupportedCard(isDark: isDark, locale: l),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _scanning
                      ? const _ScanningButton()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListingCtaButton(
                              label: _supported == null
                                  ? _S.checking(l)
                                  : _S.startScan(l),
                              enabled: _supported == true,
                              onTap: _startScan,
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _skip,
                              child: Text(
                                _S.skip(l),
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontSize: 14,
                                  color: subColor,
                                ),
                              ),
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
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.splashGreen.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.splashGreen,
                      ),
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

class _UnsupportedCard extends StatelessWidget {
  const _UnsupportedCard({required this.isDark, required this.locale});

  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0A12A)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFE0A12A), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _S.unsupportedTitle(locale),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _S.unsupportedBody(locale),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    height: 1.35,
                    color: hintColor,
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

  static String title(Locale l) => switch (l.languageCode) {
        'ru' => 'AI Оценка',
        'en' => 'AI Valuation',
        _ => 'AI Baholash',
      };

  static String subtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Шаг 1 — 3D скан помещения',
        'en' => 'Step 1 — 3D room scan',
        _ => '1-qadam — xonaning 3D skani',
      };

  static String heading(Locale l) => switch (l.languageCode) {
        'ru' => 'Сначала отсканируйте помещение',
        'en' => 'First, scan the room',
        _ => 'Avval xonani skanlang',
      };

  static String body(Locale l) => switch (l.languageCode) {
        'ru' =>
          'Для точной оценки нужен 3D скан. Медленно обойдите помещение, '
              'направляя камеру на стены, пол и потолок.',
        'en' =>
          'An accurate valuation needs a 3D scan. Walk slowly around the '
              'room, pointing the camera at walls, floor and ceiling.',
        _ =>
          'Aniq baholash uchun 3D skan kerak. Xonani sekin aylanib chiqing, '
              'kamerani devor, pol va shiftga yo\'naltiring.',
      };

  static List<String> steps(Locale l) => switch (l.languageCode) {
        'ru' => const [
            'Сканирование помещения',
            'Просмотр 3D модели (mesh)',
            'Обработка в USDZ',
            'Ввод кадастрового номера',
          ],
        'en' => const [
            'Scan the room',
            'Preview the 3D mesh',
            'Process into USDZ',
            'Enter the cadastral number',
          ],
        _ => const [
            'Xonani skanlash',
            '3D model (mesh) ni ko\'rish',
            'USDZ ga ishlash',
            'Kadastr raqamini kiritish',
          ],
      };

  static String startScan(Locale l) => switch (l.languageCode) {
        'ru' => 'Начать сканирование',
        'en' => 'Start scanning',
        _ => 'Skanlashni boshlash',
      };

  static String skip(Locale l) => switch (l.languageCode) {
        'ru' => 'Пропустить',
        'en' => 'Skip',
        _ => 'O\'tkazib yuborish',
      };

  static String checking(Locale l) => switch (l.languageCode) {
        'ru' => 'Проверка устройства…',
        'en' => 'Checking device…',
        _ => 'Qurilma tekshirilmoqda…',
      };

  static String unsupportedTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Устройство не поддерживает скан',
        'en' => 'Device does not support scanning',
        _ => 'Qurilma skanni qo\'llamaydi',
      };

  static String unsupportedBody(Locale l) => switch (l.languageCode) {
        'ru' =>
          '3D скан требует LiDAR — iPhone Pro или iPad Pro. На этом устройстве '
              'продолжить нельзя.',
        'en' =>
          '3D scanning needs LiDAR — iPhone Pro or iPad Pro. You can\'t '
              'continue on this device.',
        _ =>
          '3D skan LiDAR talab qiladi — iPhone Pro yoki iPad Pro. Bu qurilmada '
              'davom etib bo\'lmaydi.',
      };

  static String scanError(Locale l) => switch (l.languageCode) {
        'ru' => 'Ошибка сканирования',
        'en' => 'Scan error',
        _ => 'Skan xatosi',
      };

  static String scanNotSaved(Locale l) => switch (l.languageCode) {
        'ru' => 'Скан не сохранён, попробуйте снова',
        'en' => 'Scan not saved, please try again',
        _ => 'Skan saqlanmadi, qayta urinib ko\'ring',
      };
}
