import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_config.dart';
import '../../../core/i18n.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../data/room_plan_scanner.dart';
import '../models/architecture_order_draft.dart';
import '../widgets/scan_camera_card.dart';
import '../widgets/scan_tips_card.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_result_screen.dart';
import 'calculator/arxitektura_tz_wizard_screen.dart';

class AiScanScreen extends StatefulWidget {
  const AiScanScreen({super.key});

  @override
  State<AiScanScreen> createState() => _AiScanScreenState();
}

class _AiScanScreenState extends State<AiScanScreen> {
  ScanCardState _state = ScanCardState.idle;
  RoomScanResult? _scanResult;

  Future<void> _startScan() async {
    if (_state == ScanCardState.scanning) return;
    HapticFeedback.lightImpact();

    final supported = await RoomPlanScanner.isSupported();
    if (!supported) {
      if (!mounted) return;
      AppToast.error(
        context,
        _AiScanStrings.unsupportedDevice(localeNotifier.value),
      );
      return;
    }

    // 3D pipeline tanlash — Polycam (default), AWS GPU (skip-COLMAP), Kiri 3DGS
    final selectedProvider = await _pickProvider();
    if (selectedProvider == null) return;  // foydalanuvchi bekor qildi

    // aws_gpu (splatfacto) uchun quality preset tanlash —
    // Tez / Standart / Maksimal.
    String quality = 'balanced';
    if (selectedProvider == 'aws_gpu') {
      final pickedQuality = await _pickQuality();
      if (pickedQuality == null) return;  // bekor qildi
      quality = pickedQuality;
    }

    // Auth token kerak (server processing)
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Skan uchun avval tizimga kiring',
      );
      return;
    }

    setState(() => _state = ScanCardState.scanning);
    try {
      // Provider'ga qarab algoritm avtomatik tanlanadi:
      //   polycam — server-side WASM USDZ (30-60 daq)
      //   aws_gpu — kadastr splatfacto + LiDAR (15-90 daq, quality'ga qarab)
      //   kiri_engine — Kiri cloud, 3DGS algoritmi (5-20 daq, $1/scan)
      final algorithm = selectedProvider == 'kiri_engine' ? '3dgs' : '';
      final hybrid = await RoomPlanScanner.startHybridScan(
        baseUrl: ApiConfig.serverBaseUrl,
        token: token,
        provider: selectedProvider,
        algorithm: algorithm,
        quality: quality,
      );
      if (!mounted) return;
      if (hybrid == null) {
        setState(() => _state = ScanCardState.idle);
        return;
      }
      setState(() {
        _state = ScanCardState.done;
      });
      final providerLabel = _providerLabel(selectedProvider);
      final etaLabel = _providerEta(selectedProvider);
      AppToast.success(
        context,
        'Foto\'lar $providerLabel\'ga yuborildi. 3D model $etaLabel\'da tayyor — '
        'Arizalar bo\'limidan kuzating.',
      );
    } on RoomPlanScannerException catch (e) {
      if (!mounted) return;
      setState(() => _state = ScanCardState.idle);
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = ScanCardState.idle);
      AppToast.error(
        context,
        '${_AiScanStrings.scanError(localeNotifier.value)}: $e',
      );
    }
  }

  /// Bottom sheet — 3D pipeline tanlash. Foydalanuvchi cancel qilsa null
  /// qaytaradi (skan boshlanmaydi).
  Future<String?> _pickProvider() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ProviderPickerSheet(),
    );
  }

  /// Splatfacto quality preset tanlash (faqat aws_gpu uchun).
  /// 'draft' (10 daq) | 'balanced' (30 daq) | 'max' (90 daq)
  Future<String?> _pickQuality() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _QualityPickerSheet(),
    );
  }

  String _providerLabel(String provider) {
    switch (provider) {
      case 'aws_gpu':
        return 'AWS GPU';
      case 'kiri_engine':
        return 'Kiri';
      case 'polycam':
      default:
        return 'Polycam';
    }
  }

  String _providerEta(String provider) {
    switch (provider) {
      case 'aws_gpu':
        return '15-30 daqiqa';
      case 'kiri_engine':
        return '5-20 daqiqa';
      case 'polycam':
      default:
        return '30-60 daqiqa';
    }
  }

  void _continue() {
    if (_state != ScanCardState.done) return;
    _openWizard(
      scanCompleted: _scanResult != null,
      areaM2: _scanResult?.floorAreaSqm,
    );
  }

  void _skip() {
    if (_state == ScanCardState.scanning) return;
    HapticFeedback.lightImpact();
    _openWizard(scanCompleted: false);
  }

  /// Skan/skip natijasini hisobga olib 9-step wizard ochish.
  /// Wizard tugagandan keyin AI baholash natijasi ekraniga o'tadi.
  void _openWizard({required bool scanCompleted, double? areaM2}) {
    final initialDraft = ArchitectureOrderDraft();
    if (areaM2 != null) {
      // RoomPlan'dan kelgan maydonni initial qiymat sifatida qo'yamiz —
      // foydalanuvchi step 3'da uni ko'radi va kerak bo'lsa to'g'rilaydi.
      initialDraft.totalAreaSqm = areaM2;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArxitekturaTzWizardScreen(
          mode: WizardMode.aiValuation,
          initialDraft: initialDraft,
          onSubmit: (draft) => _onWizardComplete(
            draft: draft,
            scanCompleted: scanCompleted,
            scanArea: areaM2,
          ),
        ),
      ),
    );
  }

  void _onWizardComplete({
    required ArchitectureOrderDraft draft,
    required bool scanCompleted,
    double? scanArea,
  }) {
    HapticFeedback.lightImpact();
    // Wizard'dan kelgan to'liq draft + skan natijasi → backend AI baholash.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AiResultScreen(
          draft: draft,
          scanCompleted: scanCompleted,
        ),
      ),
    );
  }

  Future<void> _preview() async {
    final path = _scanResult?.filePath;
    if (path == null) return;
    HapticFeedback.lightImpact();
    try {
      await RoomPlanScanner.preview(path);
    } on RoomPlanScannerException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        '${_AiScanStrings.previewError(localeNotifier.value)}: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => _build(context, locale),
    );
  }

  Widget _build(BuildContext context, Locale locale) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContent = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: _AiScanStrings.appBarTitle(locale),
                        subtitle: _AiScanStrings.appBarSubtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 1),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            _AiScanStrings.heading(locale),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              height: 1.25,
                              color: headingColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _AiScanStrings.subheading(locale),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.3,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ScanCameraCard(
                            state: _state,
                            onTap: _startScan,
                            idleLabel: _AiScanStrings.cameraIdle(locale),
                            scanningLabel:
                                _AiScanStrings.cameraScanning(locale),
                            doneLabel: _AiScanStrings.cameraDone(locale),
                          ),
                          if (_state == ScanCardState.done &&
                              _scanResult != null) ...[
                            const SizedBox(height: 12),
                            _PreviewButton(
                              onTap: _preview,
                              label: _AiScanStrings.preview3dModel(locale),
                            ),
                          ],
                          const SizedBox(height: 16),
                          ScanTipsCard(tips: _AiScanStrings.tips(locale)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: ListingCtaButton(
                        label: _state == ScanCardState.done
                            ? _AiScanStrings.ctaContinue(locale)
                            : _AiScanStrings.ctaStart(locale),
                        enabled: _state != ScanCardState.scanning,
                        onTap: _state == ScanCardState.done
                            ? _continue
                            : _startScan,
                      ),
                    ),
                    if (_state != ScanCardState.done)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextButton(
                          onPressed: _state == ScanCardState.scanning
                              ? null
                              : _skip,
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _AiScanStrings.ctaSkip(locale),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: subColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = AppColors.splashGreen.withValues(alpha: 0.6);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Row(
            children: [
              Icon(Icons.view_in_ar_rounded,
                  color: AppColors.splashGreen, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: textColor.withValues(alpha: 0.4), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Locale-aware strings for the AI valuation scan screen.
/// Keeps the inline `switch (locale.languageCode)` pattern used elsewhere
/// in the app (see `home_cta.dart`).
class _AiScanStrings {
  static String appBarTitle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'AI Оценка',
        'en' => 'AI Valuation',
        _ => 'AI Baholash',
      };

  static String appBarSubtitle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Определение стоимости недвижимости',
        'en' => 'Determine property value',
        _ => 'Ko\'chmas mulk qiymatini aniqlash',
      };

  static String heading(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Сканируйте объект',
        'en' => 'Scan the object',
        _ => 'Obyektni skan qiling',
      };

  static String subheading(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Сканируйте через RoomPlan LiDAR',
        'en' => 'Scan via RoomPlan LiDAR',
        _ => 'RoomPlan LiDAR orqali skan qiling',
      };

  static String cameraIdle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Запустите LiDAR-камеру',
        'en' => 'Start LiDAR camera',
        _ => 'LiDAR kamerani ishga tushiring',
      };

  static String cameraScanning(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Сканирование...',
        'en' => 'Scanning...',
        _ => 'Skanerlanmoqda...',
      };

  static String cameraDone(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Скан готов',
        'en' => 'Scan ready',
        _ => 'Skan tayyor',
      };

  static List<String> tips(Locale locale) => switch (locale.languageCode) {
        'ru' => const [
            'Двигайте устройство медленно',
            'Охватите всю комнату',
            'Освещение должно быть достаточным',
          ],
        'en' => const [
            'Move the device slowly',
            'Cover the entire room',
            'Sufficient lighting is required',
          ],
        _ => const [
            'Qurilmani sekin harakatlantiring',
            'Xonani to\'liq qamrab oling',
            'Yorug\'lik yetarli bo\'lishi kerak',
          ],
      };

  static String ctaStart(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Начать сканирование',
        'en' => 'Start scan',
        _ => 'Scan boshlash',
      };

  static String ctaContinue(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Продолжить',
        'en' => 'Continue',
        _ => 'Davom etish',
      };

  static String ctaSkip(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Пропустить и продолжить',
        'en' => 'Skip and continue',
        _ => 'O\'tkazib yuborish',
      };

  static String preview3dModel(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Просмотр 3D-модели',
        'en' => 'View 3D model',
        _ => '3D modelni ko\'rish',
      };

  static String unsupportedDevice(Locale locale) =>
      switch (locale.languageCode) {
        'ru' =>
          'На этом устройстве нет RoomPlan. Требуется iPhone Pro или iPad Pro '
              '(iOS 16+ и LiDAR-сенсор).',
        'en' =>
          'This device does not support RoomPlan. iPhone Pro or iPad Pro is '
              'required (iOS 16+ with a LiDAR sensor).',
        _ => 'Bu qurilmada RoomPlan yo\'q. iPhone Pro yoki iPad Pro kerak '
            '(iOS 16+ va LiDAR sensori).',
      };

  static String scanError(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Ошибка сканирования',
        'en' => 'Scan error',
        _ => 'Skan xatosi',
      };

  static String previewError(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Ошибка просмотра',
        'en' => 'Preview error',
        _ => 'Ko\'rsatish xatosi',
      };

}

/// 3D pipeline tanlash uchun bottom sheet — Polycam / AWS GPU / Kiri.
/// Foydalanuvchi tanlagan provider id'sini Navigator.pop bilan qaytaradi.
class _ProviderPickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '3D pipeline tanlang',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Foto\'lar qaysi tizimda 3D model qilinsin?',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            _providerCard(
              context,
              id: 'polycam',
              title: 'Polycam',
              subtitle: 'Web UI orqali, sifat baland (mesh-based USDZ)',
              eta: '30-60 daqiqa',
              icon: Icons.cloud,
              color: const Color(0xFFE85A4F),
            ),
            const SizedBox(height: 12),
            _providerCard(
              context,
              id: 'aws_gpu',
              title: 'AWS GPU (kadastr)',
              subtitle: 'O\'z server, ARKit pose\'lar bilan tezroq + arzon',
              eta: '15-30 daqiqa',
              icon: Icons.memory,
              color: const Color(0xFFFF9900),
              recommended: true,
            ),
            const SizedBox(height: 12),
            _providerCard(
              context,
              id: 'kiri_engine',
              title: 'Kiri Engine 3DGS',
              subtitle: 'Gaussian Splatting — past sifatli foto\'larga ham yaxshi',
              eta: '5-20 daqiqa',
              icon: Icons.auto_awesome,
              color: const Color(0xFF3DB99F),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L.cancel(Localizations.localeOf(context))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerCard(
    BuildContext context, {
    required String id,
    required String title,
    required String subtitle,
    required String eta,
    required IconData icon,
    required Color color,
    bool recommended = false,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: recommended ? color : Colors.white12,
            width: recommended ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'TAVSIYA',
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          size: 12, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text(
                        eta,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}


/// Splatfacto quality preset tanlash uchun bottom sheet (aws_gpu uchun).
/// 'draft' (tez, ~10 daq), 'balanced' (~30 daq, default), 'max' (~90 daq).
class _QualityPickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Sifat darajasini tanlang',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Tezlik va sifat orasidagi balans',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            _qualityCard(
              context,
              id: 'draft',
              title: 'Tez',
              subtitle: 'Tezkor preview, oddiy sifat',
              eta: '~10 daqiqa',
              quality: '60% sifat',
              icon: Icons.bolt,
              color: const Color(0xFF60A5FA),
            ),
            const SizedBox(height: 12),
            _qualityCard(
              context,
              id: 'balanced',
              title: 'Standart',
              subtitle: 'Tezlik va sifat balansi (tavsiya)',
              eta: '~25-40 daqiqa',
              quality: '80% sifat',
              icon: Icons.tune,
              color: const Color(0xFFFF9900),
              recommended: true,
            ),
            const SizedBox(height: 12),
            _qualityCard(
              context,
              id: 'max',
              title: 'Maksimal',
              subtitle: 'Foto-realistic, LiDAR depth bilan',
              eta: '~90-150 daqiqa',
              quality: '95-100% sifat',
              icon: Icons.diamond,
              color: const Color(0xFFE85A4F),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L.cancel(Localizations.localeOf(context))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityCard(
    BuildContext context, {
    required String id,
    required String title,
    required String subtitle,
    required String eta,
    required String quality,
    required IconData icon,
    required Color color,
    bool recommended = false,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: recommended ? color : Colors.white12,
            width: recommended ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Tavsiya',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 11, color: Colors.white38),
                      const SizedBox(width: 3),
                      Text(
                        eta,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.star, size: 11, color: Colors.white38),
                      const SizedBox(width: 3),
                      Text(
                        quality,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}
