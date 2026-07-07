import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_config.dart';
import '../../../core/i18n.dart';
import '../../../core/i18n/app_translations.dart';
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

    // Provider picker olib tashlandi — kadastr 3D scan'ning yagona yo'li:
    // on-device ARKit + LiDAR (`startTexturedScan` → custom mesh export →
    // USDZ). Internet, server, token kerak emas.
    setState(() => _state = ScanCardState.scanning);
    try {
      final result = await RoomPlanScanner.startTexturedScan();
      if (!mounted) return;
      if (result == null) {
        setState(() => _state = ScanCardState.idle);
        return;
      }
      setState(() => _state = ScanCardState.done);

      // Phase 7: saved_raw mode (default) — texturing'siz saqlangan.
      // Foydalanuvchi profilga kirib qayta ishlash tugmasini bosadi.
      if (result.isSavedRaw) {
        AppToast.success(
          context,
          _AiScanStrings.savedScanSuccess(
            localeNotifier.value,
            result.savedScanId!,
          ),
        );
      } else {
        // Legacy: filePath bilan kelgan (offline_processed yoki eski flow).
        final path = result.filePath;
        if (path != null && path.isNotEmpty) {
          await RoomPlanScanner.preview(path);
          if (!mounted) return;
          AppToast.success(
            context,
            _AiScanStrings.savedModelSuccess(
              localeNotifier.value,
              (result.fileSize / 1048576).toStringAsFixed(1),
            ),
          );
        }
      }
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
    return;
  }

  // ignore: unused_element
  Future<void> _startScanLegacy() async {
    // Eski multi-provider flow — vaqtincha o'chirilgan, kelajakda kerakli
    // bo'lsa qaytariladi. Hozircha faqat custom on-device pipeline.
    final selectedProvider = await _pickProvider();
    if (selectedProvider == null) return;
    String quality = 'balanced';
    if (selectedProvider == 'aws_gpu') {
      final pickedQuality = await _pickQuality();
      if (pickedQuality == null) return;
      quality = pickedQuality;
    }
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      AppToast.error(
        context,
        _AiScanStrings.loginRequiredForScan(localeNotifier.value),
      );
      return;
    }
    setState(() => _state = ScanCardState.scanning);
    try {
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
        _AiScanStrings.providerUploadSuccess(
          localeNotifier.value,
          providerLabel,
          etaLabel,
        ),
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
    final locale = localeNotifier.value;
    switch (provider) {
      case 'aws_gpu':
        return _AiScanStrings.providerAwsGpu(locale);
      case 'kiri_engine':
        return _AiScanStrings.providerKiri(locale);
      case 'polycam':
      default:
        return _AiScanStrings.providerPolycam(locale);
    }
  }

  String _providerEta(String provider) {
    final locale = localeNotifier.value;
    switch (provider) {
      case 'aws_gpu':
        return _AiScanStrings.providerEtaAws(locale);
      case 'kiri_engine':
        return _AiScanStrings.providerEtaKiri(locale);
      case 'polycam':
      default:
        return _AiScanStrings.providerEtaPolycam(locale);
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
        builder: (_) =>
            AiResultScreen(draft: draft, scanCompleted: scanCompleted),
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
                      child: const StepProgressBar(count: 4, activeIndex: 0),
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
                            scanningLabel: _AiScanStrings.cameraScanning(
                              locale,
                            ),
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
              Icon(
                Icons.view_in_ar_rounded,
                color: AppColors.splashGreen,
                size: 22,
              ),
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
              Icon(
                Icons.chevron_right_rounded,
                color: textColor.withValues(alpha: 0.4),
                size: 22,
              ),
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
  static String _t(
    Locale locale,
    String key,
    String uz,
    String ru,
    String en,
  ) => tr(locale, key, uz: uz, ru: ru, en: en);

  static String appBarTitle(Locale locale) => _t(
    locale,
    'scan.ai.app_bar_title',
    'AI Baholash',
    'AI Оценка',
    'AI Valuation',
  );
  static String appBarSubtitle(Locale locale) => _t(
    locale,
    'scan.ai.app_bar_subtitle',
    'Ko\'chmas mulk qiymatini aniqlash',
    'Определение стоимости недвижимости',
    'Determine property value',
  );
  static String heading(Locale locale) => _t(
    locale,
    'scan.ai.heading',
    'Obyektni skan qiling',
    'Сканируйте объект',
    'Scan the object',
  );
  static String subheading(Locale locale) => _t(
    locale,
    'scan.ai.subheading',
    'RoomPlan LiDAR orqali skan qiling',
    'Сканируйте через RoomPlan LiDAR',
    'Scan via RoomPlan LiDAR',
  );
  static String cameraIdle(Locale locale) => _t(
    locale,
    'scan.ai.camera_idle',
    'LiDAR kamerani ishga tushiring',
    'Запустите LiDAR-камеру',
    'Start LiDAR camera',
  );
  static String cameraScanning(Locale locale) => _t(
    locale,
    'scan.ai.camera_scanning',
    'Skanerlanmoqda...',
    'Сканирование...',
    'Scanning...',
  );
  static String cameraDone(Locale locale) => _t(
    locale,
    'scan.ai.camera_done',
    'Skan tayyor',
    'Скан готов',
    'Scan ready',
  );
  static List<String> tips(Locale locale) => [
    _t(
      locale,
      'scan.ai.tip_move_slowly',
      'Qurilmani sekin harakatlantiring',
      'Двигайте устройство медленно',
      'Move the device slowly',
    ),
    _t(
      locale,
      'scan.ai.tip_cover_room',
      'Xonani to\'liq qamrab oling',
      'Охватите всю комнату',
      'Cover the entire room',
    ),
    _t(
      locale,
      'scan.ai.tip_light',
      'Yorug\'lik yetarli bo\'lishi kerak',
      'Освещение должно быть достаточным',
      'Sufficient lighting is required',
    ),
  ];
  static String ctaStart(Locale locale) => _t(
    locale,
    'scan.ai.cta_start',
    'Scan boshlash',
    'Начать сканирование',
    'Start scan',
  );
  static String ctaContinue(Locale locale) =>
      _t(locale, 'common.continue', 'Davom etish', 'Продолжить', 'Continue');
  static String ctaSkip(Locale locale) => _t(
    locale,
    'scan.ai.cta_skip',
    'O\'tkazib yuborish',
    'Пропустить и продолжить',
    'Skip and continue',
  );
  static String preview3dModel(Locale locale) => _t(
    locale,
    'scan.ai.preview_3d_model',
    '3D modelni ko\'rish',
    'Просмотр 3D-модели',
    'View 3D model',
  );

  static String unsupportedDevice(Locale locale) =>
      switch (locale.languageCode) {
        'ru' =>
          'На этом устройстве нет RoomPlan. Требуется iPhone Pro или iPad Pro '
              '(iOS 16+ и LiDAR-сенсор).',
        'en' =>
          'This device does not support RoomPlan. iPhone Pro or iPad Pro is '
              'required (iOS 16+ with a LiDAR sensor).',
        _ =>
          'Bu qurilmada RoomPlan yo\'q. iPhone Pro yoki iPad Pro kerak '
              '(iOS 16+ va LiDAR sensori).',
      };

  static String scanError(Locale locale) => _t(
    locale,
    'scan.ai.scan_error',
    'Skan xatosi',
    'Ошибка сканирования',
    'Scan error',
  );

  static String previewError(Locale locale) => _t(
    locale,
    'scan.ai.preview_error',
    'Ko\'rsatish xatosi',
    'Ошибка просмотра',
    'Preview error',
  );

  static String savedScanSuccess(Locale locale, int id) =>
      switch (locale.languageCode) {
        'ru' => 'Скан сохранён (#$id) — Профиль → Мои сканы',
        'en' => 'Scan saved (#$id) — Profile → My scans',
        _ => 'Skan saqlandi (#$id) — Profil → Mening skanlarim',
      };

  static String savedModelSuccess(Locale locale, String sizeMb) =>
      switch (locale.languageCode) {
        'ru' => '3D-модель готова — сохранена на iPhone ($sizeMb MB)',
        'en' => '3D model is ready — saved on iPhone ($sizeMb MB)',
        _ => '3D model tayyor — iPhone\'da saqlandi ($sizeMb MB)',
      };

  static String loginRequiredForScan(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Сначала войдите в аккаунт для сканирования',
        'en' => 'Please sign in first to scan',
        _ => 'Skan uchun avval tizimga kiring',
      };

  static String providerUploadSuccess(
    Locale locale,
    String providerLabel,
    String etaLabel,
  ) => switch (locale.languageCode) {
    'ru' =>
      'Фото отправлены в $providerLabel. 3D-модель будет готова через '
          '$etaLabel — отслеживайте статус в разделе "Заявки".',
    'en' =>
      'Photos were sent to $providerLabel. The 3D model will be ready in '
          '$etaLabel — track it in Applications.',
    _ =>
      'Foto\'lar $providerLabel\'ga yuborildi. 3D model $etaLabel\'da tayyor — '
          'Arizalar bo\'limidan kuzating.',
  };

  static String providerSheetTitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Выберите способ создания 3D-модели',
        'en' => 'Choose how to create the 3D model',
        _ => '3D model yaratish usulini tanlang',
      };

  static String providerSheetSubtitle(
    Locale locale,
  ) => switch (locale.languageCode) {
    'ru' =>
      'Каким способом обработать фото и данные сканирования для 3D-модели?',
    'en' => 'How should the photos and scan data be processed into a 3D model?',
    _ => 'Foto va skan ma\'lumotlari qaysi usulda 3D modelga aylantirilsin?',
  };

  static String providerCaptureSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Модель создаётся прямо на iPhone. Интернет не требуется.',
        'en' =>
          'The model is created directly on the iPhone. No internet required.',
        _ => 'Model iPhone\'ning o\'zida tayyorlanadi. Internet kerak emas.',
      };

  static String providerPolycamSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Обработка через онлайн-сервис, результат высокого качества.',
        'en' =>
          'Processed through an online service with high-quality results.',
        _ => 'Onlayn xizmat orqali tayyorlanadi, natija sifati yuqori.',
      };

  static String providerAwsSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Обработка на нашем сервере: быстрее и экономичнее.',
        'en' => 'Processed on our server: faster and more cost-efficient.',
        _ => 'Bizning serverda tezroq va tejamkorroq qayta ishlanadi.',
      };

  static String providerKiriSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Подходит даже для фотографий среднего качества.',
        'en' => 'Works well even with lower-quality photos.',
        _ => 'Sifat pastroq bo\'lgan suratlarda ham yaxshi natija beradi.',
      };

  static String providerCapture(Locale locale) => 'iPhone Object Capture';
  static String providerPolycam(Locale locale) => 'Polycam';
  static String providerAwsGpu(Locale locale) => 'AWS GPU';
  static String providerKiri(Locale locale) => 'Kiri Engine 3DGS';

  static String providerEtaCapture(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => '3-5 минут',
        'en' => '3-5 minutes',
        _ => '3-5 daqiqa',
      };

  static String providerEtaPolycam(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => '30-60 минут',
        'en' => '30-60 minutes',
        _ => '30-60 daqiqa',
      };

  static String providerEtaAws(Locale locale) => switch (locale.languageCode) {
    'ru' => '15-30 минут',
    'en' => '15-30 minutes',
    _ => '15-30 daqiqa',
  };

  static String providerEtaKiri(Locale locale) => switch (locale.languageCode) {
    'ru' => '5-20 минут',
    'en' => '5-20 minutes',
    _ => '5-20 daqiqa',
  };

  static String qualitySheetTitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Выберите качество обработки',
        'en' => 'Choose processing quality',
        _ => 'Model sifati darajasini tanlang',
      };

  static String qualitySheetSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Баланс между скоростью и качеством результата',
        'en' => 'Balance between speed and output quality',
        _ => 'Tezlik va natija sifati o\'rtasidagi muvozanat',
      };

  static String qualityDraftTitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Быстро',
        'en' => 'Fast',
        _ => 'Tez',
      };

  static String qualityDraftSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Быстрый результат, базовое качество',
        'en' => 'Fast result with basic quality',
        _ => 'Tez natija, o\'rtacha sifat',
      };

  static String qualityDraftEta(Locale locale) => switch (locale.languageCode) {
    'ru' => '~10 минут',
    'en' => '~10 minutes',
    _ => '~10 daqiqa',
  };

  static String qualityDraftValue(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => '60% качества',
        'en' => '60% quality',
        _ => '60% sifat',
      };

  static String qualityBalancedTitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Стандарт',
        'en' => 'Standard',
        _ => 'Standart',
      };

  static String qualityBalancedSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Рекомендуемый баланс скорости и качества',
        'en' => 'Recommended balance of speed and quality',
        _ => 'Tezlik va sifatning tavsiya etilgan muvozanati',
      };

  static String qualityBalancedEta(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => '~25-40 минут',
        'en' => '~25-40 minutes',
        _ => '~25-40 daqiqa',
      };

  static String qualityBalancedValue(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => '80% качества',
        'en' => '80% quality',
        _ => '80% sifat',
      };

  static String qualityMaxTitle(Locale locale) => switch (locale.languageCode) {
    'ru' => 'Максимум',
    'en' => 'Maximum',
    _ => 'Maksimal',
  };

  static String qualityMaxSubtitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Высокая детализация с использованием глубины LiDAR',
        'en' => 'High-detail result using LiDAR depth',
        _ => 'Yuqori aniqlikdagi natija, LiDAR chuqurlik ma\'lumotlari bilan',
      };

  static String qualityMaxEta(Locale locale) => switch (locale.languageCode) {
    'ru' => '~90-150 минут',
    'en' => '~90-150 minutes',
    _ => '~90-150 daqiqa',
  };

  static String qualityMaxValue(Locale locale) => switch (locale.languageCode) {
    'ru' => '95-100% качества',
    'en' => '95-100% quality',
    _ => '95-100% sifat',
  };

  static String recommended(Locale locale) => _t(
    locale,
    'common.recommended',
    'Tavsiya',
    'Рекомендация',
    'Recommended',
  );
}

/// 3D pipeline tanlash uchun bottom sheet — Polycam / AWS GPU / Kiri.
/// Foydalanuvchi tanlagan provider id'sini Navigator.pop bilan qaytaradi.
class _ProviderPickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
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
              _AiScanStrings.providerSheetTitle(locale),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _AiScanStrings.providerSheetSubtitle(locale),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            _providerCard(
              context,
              id: 'object_capture',
              title: _AiScanStrings.providerCapture(locale),
              subtitle: _AiScanStrings.providerCaptureSubtitle(locale),
              eta: _AiScanStrings.providerEtaCapture(locale),
              icon: Icons.phone_iphone,
              color: const Color(0xFF34C759),
              recommended: true,
            ),
            const SizedBox(height: 12),
            _providerCard(
              context,
              id: 'polycam',
              title: _AiScanStrings.providerPolycam(locale),
              subtitle: _AiScanStrings.providerPolycamSubtitle(locale),
              eta: _AiScanStrings.providerEtaPolycam(locale),
              icon: Icons.cloud,
              color: const Color(0xFFE85A4F),
            ),
            const SizedBox(height: 12),
            _providerCard(
              context,
              id: 'aws_gpu',
              title: _AiScanStrings.providerAwsGpu(locale),
              subtitle: _AiScanStrings.providerAwsSubtitle(locale),
              eta: _AiScanStrings.providerEtaAws(locale),
              icon: Icons.memory,
              color: const Color(0xFFFF9900),
            ),
            const SizedBox(height: 12),
            _providerCard(
              context,
              id: 'kiri_engine',
              title: _AiScanStrings.providerKiri(locale),
              subtitle: _AiScanStrings.providerKiriSubtitle(locale),
              eta: _AiScanStrings.providerEtaKiri(locale),
              icon: Icons.auto_awesome,
              color: const Color(0xFF3DB99F),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L.cancel(locale)),
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
    final locale = Localizations.localeOf(context);
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
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _AiScanStrings.recommended(locale).toUpperCase(),
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
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 12,
                        color: Colors.white54,
                      ),
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
    final locale = Localizations.localeOf(context);
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
              _AiScanStrings.qualitySheetTitle(locale),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _AiScanStrings.qualitySheetSubtitle(locale),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            _qualityCard(
              context,
              id: 'draft',
              title: _AiScanStrings.qualityDraftTitle(locale),
              subtitle: _AiScanStrings.qualityDraftSubtitle(locale),
              eta: _AiScanStrings.qualityDraftEta(locale),
              quality: _AiScanStrings.qualityDraftValue(locale),
              icon: Icons.bolt,
              color: const Color(0xFF60A5FA),
            ),
            const SizedBox(height: 12),
            _qualityCard(
              context,
              id: 'balanced',
              title: _AiScanStrings.qualityBalancedTitle(locale),
              subtitle: _AiScanStrings.qualityBalancedSubtitle(locale),
              eta: _AiScanStrings.qualityBalancedEta(locale),
              quality: _AiScanStrings.qualityBalancedValue(locale),
              icon: Icons.tune,
              color: const Color(0xFFFF9900),
              recommended: true,
            ),
            const SizedBox(height: 12),
            _qualityCard(
              context,
              id: 'max',
              title: _AiScanStrings.qualityMaxTitle(locale),
              subtitle: _AiScanStrings.qualityMaxSubtitle(locale),
              eta: _AiScanStrings.qualityMaxEta(locale),
              quality: _AiScanStrings.qualityMaxValue(locale),
              icon: Icons.diamond,
              color: const Color(0xFFE85A4F),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L.cancel(locale)),
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
    final locale = Localizations.localeOf(context);
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
                          child: Text(
                            _AiScanStrings.recommended(locale),
                            style: const TextStyle(
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
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
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
