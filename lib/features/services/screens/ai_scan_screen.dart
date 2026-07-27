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
/// Backed by the shared translation bundle via `tr(locale, key)`.
class _AiScanStrings {
  static String _t(Locale locale, String key) => tr(locale, key);

  static String appBarTitle(Locale locale) =>
      _t(locale, 'scan.ai.app_bar_title');
  static String appBarSubtitle(Locale locale) =>
      _t(locale, 'scan.ai.app_bar_subtitle');
  static String heading(Locale locale) => _t(locale, 'scan.ai.heading');
  static String subheading(Locale locale) => _t(locale, 'scan.ai.subheading');
  static String cameraIdle(Locale locale) =>
      _t(locale, 'scan.ai.camera_idle');
  static String cameraScanning(Locale locale) =>
      _t(locale, 'scan.ai.camera_scanning');
  static String cameraDone(Locale locale) =>
      _t(locale, 'scan.ai.camera_done');
  static List<String> tips(Locale locale) => [
    _t(locale, 'scan.ai.tip_move_slowly'),
    _t(locale, 'scan.ai.tip_cover_room'),
    _t(locale, 'scan.ai.tip_light'),
  ];
  static String ctaStart(Locale locale) => _t(locale, 'scan.ai.cta_start');
  static String ctaContinue(Locale locale) => _t(locale, 'common.continue');
  static String ctaSkip(Locale locale) => _t(locale, 'scan.ai.cta_skip');
  static String preview3dModel(Locale locale) =>
      _t(locale, 'scan.ai.preview_3d_model');

  static String unsupportedDevice(Locale locale) =>
      _t(locale, 'services.scan.ai.unsupported_device');

  static String scanError(Locale locale) => _t(locale, 'scan.ai.scan_error');

  static String previewError(Locale locale) =>
      _t(locale, 'scan.ai.preview_error');

  static String savedScanSuccess(Locale locale, int id) =>
      _t(locale, 'services.scan.ai.saved_scan_success')
          .replaceAll(r'$id', '$id');

  static String savedModelSuccess(Locale locale, String sizeMb) =>
      _t(locale, 'services.scan.ai.saved_model_success')
          .replaceAll(r'$sizeMb', sizeMb);

  static String loginRequiredForScan(Locale locale) =>
      _t(locale, 'services.scan.ai.login_required_for_scan');

  static String providerUploadSuccess(
    Locale locale,
    String providerLabel,
    String etaLabel,
  ) => _t(locale, 'services.scan.ai.provider_upload_success')
      .replaceAll(r'$providerLabel', providerLabel)
      .replaceAll(r'$etaLabel', etaLabel);

  static String providerSheetTitle(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_sheet_title');

  static String providerSheetSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_sheet_subtitle');

  static String providerCaptureSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_capture_subtitle');

  static String providerPolycamSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_polycam_subtitle');

  static String providerAwsSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_aws_subtitle');

  static String providerKiriSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_kiri_subtitle');

  static String providerCapture(Locale locale) => 'iPhone Object Capture';
  static String providerPolycam(Locale locale) => 'Polycam';
  static String providerAwsGpu(Locale locale) => 'AWS GPU';
  static String providerKiri(Locale locale) => 'Kiri Engine 3DGS';

  static String providerEtaCapture(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_eta_capture');

  static String providerEtaPolycam(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_eta_polycam');

  static String providerEtaAws(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_eta_aws');

  static String providerEtaKiri(Locale locale) =>
      _t(locale, 'services.scan.ai.provider_eta_kiri');

  static String qualitySheetTitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_sheet_title');

  static String qualitySheetSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_sheet_subtitle');

  static String qualityDraftTitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_draft_title');

  static String qualityDraftSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_draft_subtitle');

  static String qualityDraftEta(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_draft_eta');

  static String qualityDraftValue(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_draft_value');

  static String qualityBalancedTitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_balanced_title');

  static String qualityBalancedSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_balanced_subtitle');

  static String qualityBalancedEta(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_balanced_eta');

  static String qualityBalancedValue(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_balanced_value');

  static String qualityMaxTitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_max_title');

  static String qualityMaxSubtitle(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_max_subtitle');

  static String qualityMaxEta(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_max_eta');

  static String qualityMaxValue(Locale locale) =>
      _t(locale, 'services.scan.ai.quality_max_value');

  static String recommended(Locale locale) => _t(locale, 'common.recommended');
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
