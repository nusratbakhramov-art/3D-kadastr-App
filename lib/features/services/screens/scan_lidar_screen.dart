import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../api_ai_upload_service.dart';
import '../data/room_plan_scanner.dart';
import '../models/kadastr_3d_bundle.dart';
import '../widgets/scan_camera_card.dart';
import '../widgets/scan_tips_card.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'scan_diagnostics_screen.dart';
import 'kadastr_3d/k3d_status_screen.dart';

/// Backend route for 3D Kadastr uploads.
const String _kUploadEndpoint = '/3d-kadastr-jobs/upload';

class ScanLidarScreen extends StatefulWidget {
  const ScanLidarScreen({super.key, required this.bundle});

  final Kadastr3dBundle bundle;

  @override
  State<ScanLidarScreen> createState() => _ScanLidarScreenState();
}

class _ScanLidarScreenState extends State<ScanLidarScreen> {
  final AiUploadService _uploads = AiUploadService();
  ScanCardState _state = ScanCardState.idle;
  RoomScanResult? _scanResult;
  bool _uploading = false;

  @override
  void dispose() {
    _uploads.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_state == ScanCardState.scanning) return;
    HapticFeedback.lightImpact();

    // Avval qurilma RoomPlan'ni qo'llaydimi tekshirish.
    final supported = await RoomPlanScanner.isSupported();
    if (!supported) {
      if (!mounted) return;
      AppToast.error(
        context,
        _ScanLidarStrings.unsupportedDevice(localeNotifier.value),
      );
      return;
    }

    setState(() => _state = ScanCardState.scanning);
    try {
      final result =
          await RoomPlanScanner.startScan(locale: localeNotifier.value);
      if (!mounted) return;
      if (result == null) {
        // Foydalanuvchi bekor qildi.
        setState(() => _state = ScanCardState.idle);
        return;
      }
      setState(() {
        _scanResult = result;
        _state = ScanCardState.done;
      });
      // Skan tayyor bo'lishi bilan USDZ faylni serverga yuklaymiz.
      await _uploadScan(result);
    } on RoomPlanScannerException catch (e) {
      if (!mounted) return;
      setState(() => _state = ScanCardState.idle);
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = ScanCardState.idle);
      AppToast.error(
        context,
        '${_ScanLidarStrings.scanError(localeNotifier.value)}: $e',
      );
    }
  }

  Future<void> _uploadScan(RoomScanResult result) async {
    // Phase 7 (v24): saved_raw rejimida USDZ fayl bo'lmaydi (filePath null),
    // faqat savedScanId saqlanadi — yuklash o'tkazib yuboriladi.
    final path = result.filePath;
    if (path == null) return;
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (mounted) AppToast.error(context, L.authRequired(localeNotifier.value));
      return;
    }
    setState(() => _uploading = true);
    try {
      final keys = await _uploads.upload(
        category: UploadCategory.scan3d,
        filePaths: [path],
        token: token,
        endpoint: _kUploadEndpoint,
      );
      if (!mounted) return;
      setState(() {
        widget.bundle.scanKeys
          ..clear()
          ..addAll(keys);
      });
    } catch (e) {
      if (mounted) {
        AppToast.error(context, switch (localeNotifier.value.languageCode) {
          'ru' => 'Не удалось загрузить скан: $e',
          'en' => 'Failed to upload scan: $e',
          _ => 'Skan yuklanmadi: $e',
        });
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _continue() {
    if (_state != ScanCardState.done) return;
    if (widget.bundle.scanKeys.isEmpty) {
      // Yuklash tugamagan yoki muvaffaqiyatsiz — qayta urinib ko'ramiz.
      if (_scanResult != null) _uploadScan(_scanResult!);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => K3dStatusScreen(bundle: widget.bundle),
      ),
    );
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
                        title: _ScanLidarStrings.appBarTitle(locale),
                        subtitle: _ScanLidarStrings.appBarSubtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 6, activeIndex: 5),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            _ScanLidarStrings.heading(locale),
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
                            _ScanLidarStrings.subheading(locale),
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
                            idleLabel: _ScanLidarStrings.cameraIdle(locale),
                            scanningLabel:
                                _ScanLidarStrings.cameraScanning(locale),
                            doneLabel: _ScanLidarStrings.cameraDone(locale),
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ScanDiagnosticsScreen(),
                                ),
                              );
                            },
                          ),
                          if (_state == ScanCardState.done &&
                              _scanResult != null) ...[
                            const SizedBox(height: 12),
                            _ScanResultCard(
                              result: _scanResult!,
                              locale: locale,
                            ),
                          ],
                          const SizedBox(height: 16),
                          ScanTipsCard(tips: _ScanLidarStrings.tips(locale)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: _uploading
                            ? 'Skan yuklanmoqda…'
                            : (_state == ScanCardState.done
                                ? _ScanLidarStrings.ctaContinue(locale)
                                : _ScanLidarStrings.ctaStart(locale)),
                        enabled: _state != ScanCardState.scanning && !_uploading,
                        onTap: _state == ScanCardState.done
                            ? _continue
                            : _startScan,
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

class _ScanResultCard extends StatelessWidget {
  const _ScanResultCard({required this.result, required this.locale});
  final RoomScanResult result;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final keyColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valColor = isDark ? Colors.white : AppColors.textBlack;

    String fmtSize(int bytes) {
      if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    final rows = <(String, String)>[
      (_ScanLidarStrings.rowWalls(locale), '${result.walls}'),
      (_ScanLidarStrings.rowDoors(locale), '${result.doors}'),
      (_ScanLidarStrings.rowWindows(locale), '${result.windows}'),
      if (result.openings > 0)
        (_ScanLidarStrings.rowOpenings(locale), '${result.openings}'),
      if (result.objects > 0)
        (_ScanLidarStrings.rowObjects(locale), '${result.objects}'),
      if (result.floorAreaSqm != null)
        (
          _ScanLidarStrings.rowFloorArea(locale),
          '${result.floorAreaSqm!.toStringAsFixed(1)} m²',
        ),
      (_ScanLidarStrings.rowFileSize(locale), fmtSize(result.fileSize)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.splashGreen.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13,
                        color: keyColor,
                      ),
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: valColor,
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1) Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}

class _ScanLidarStrings {
  static String appBarTitle(Locale locale) => switch (locale.languageCode) {
        'ru' => '3D Кадастр',
        'en' => '3D Cadastre',
        _ => '3D kadastr',
      };

  static String appBarSubtitle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Сканируйте через RoomPlan LiDAR',
        'en' => 'Scan via RoomPlan LiDAR',
        _ => 'RoomPlan LiDAR orqali skan qiling',
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

  static String cameraScanning(Locale locale) =>
      switch (locale.languageCode) {
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

  static String rowWalls(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Стены',
        'en' => 'Walls',
        _ => 'Devorlar',
      };

  static String rowDoors(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Двери',
        'en' => 'Doors',
        _ => 'Eshiklar',
      };

  static String rowWindows(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Окна',
        'en' => 'Windows',
        _ => 'Oynalar',
      };

  static String rowOpenings(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Другие проёмы',
        'en' => 'Other openings',
        _ => 'Boshqa ochiqliklar',
      };

  static String rowObjects(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Мебель/объекты',
        'en' => 'Furniture/objects',
        _ => 'Mebel/obyektlar',
      };

  static String rowFloorArea(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Площадь (примерно)',
        'en' => 'Area (approx.)',
        _ => 'Maydon (taxminiy)',
      };

  static String rowFileSize(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Размер файла',
        'en' => 'File size',
        _ => 'Fayl hajmi',
      };
}
