import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../scans/saved_scan_service.dart';
import '../api_ai_valuation_job_service.dart';
import '../data/model_preview.dart';
import '../widgets/service_app_bar.dart';

/// Skanlangan 3D modelni ko'rish ekrani — wizard qadamidan "3D modelni ko'rish"
/// tugmasi bilan USTIGA ochiladi.
///
/// Foydalanuvchi oldin skanlangan modelni QuickLook'da ko'radi; "Ortga" yoki ←
/// bilan o'sha qadamga qaytadi (qadam OSTIDA saqlanib turadi, ma'lumot yo'qolmaydi).
/// USDZ backend'dan (`GET /ai-valuations/{id}/scan`) vaqtinchalik faylga yuklanadi
/// — lokal fayl yangi sessiyada yo'q.
class AiScanResumeScreen extends StatefulWidget {
  const AiScanResumeScreen({super.key, required this.jobId});

  /// Draft ariza id — `GET /ai-valuations/{id}/scan` shu bilan yuklaydi.
  final int jobId;

  @override
  State<AiScanResumeScreen> createState() => _AiScanResumeScreenState();
}

class _AiScanResumeScreenState extends State<AiScanResumeScreen> {
  final AiValuationJobService _service = AiValuationJobService();
  final SavedScanService _scan = SavedScanService();
  bool _loading = false;

  Future<void> _viewModel() async {
    if (_loading) return;
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      final session = await const AuthStorage().loadSession();
      final token = session.token;
      if (token == null || token.isEmpty) {
        if (mounted) AppToast.error(context, _S.signIn(_locale));
        return;
      }
      final path = await _service.downloadScanUsdz(widget.jobId, token: token);
      if (!mounted) return;
      if (path == null) {
        AppToast.error(context, _S.notFound(_locale));
        return;
      }
      // Asosiy model endi GLB (scan_usdz_key → .glb). SceneKit GLB'ni
      // ko'rsata olmaydi (bo'sh ekran) — shuning uchun kontent bo'yicha
      // yo'naltiramiz: GLB → model_viewer_plus, eski USDZ → QuickLook.
      await openScanModel(context, path, scan: _scan);
    } catch (e) {
      if (mounted) AppToast.error(context, '${_S.failed(_locale)}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _continue() {
    HapticFeedback.lightImpact();
    // Qadamdan USTIGA ochilgan — pop bilan o'sha qadamga (saqlangan ma'lumot
    // bilan) qaytamiz.
    Navigator.of(context).maybePop();
  }

  Locale get _locale => Localizations.localeOf(context);

  @override
  Widget build(BuildContext context) {
    final l = _locale;
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
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                    children: [
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.splashGreen.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 42,
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
                      const SizedBox(height: 28),
                      _ViewModelButton(
                        label: _S.viewModel(l),
                        loading: _loading,
                        onTap: _viewModel,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _S.continueLabel(l),
                    onTap: _continue,
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

class _ViewModelButton extends StatelessWidget {
  const _ViewModelButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                )
              else
                Icon(Icons.threed_rotation_rounded, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
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
        'ru' => '3D скан — продолжение заявки',
        'en' => '3D scan — resume application',
        _ => '3D skan — arizani davom ettirish',
      };

  static String heading(Locale l) => switch (l.languageCode) {
        'ru' => '3D модель отсканирована',
        'en' => '3D model scanned',
        _ => '3D model skanlangan',
      };

  static String body(Locale l) => switch (l.languageCode) {
        'ru' =>
          'Текстурированная 3D модель сохранена в заявке. Посмотрите её или '
              'продолжайте заполнение с сохранённого шага.',
        'en' =>
          'The textured 3D model is saved in this application. Preview it or '
              'continue from your saved step.',
        _ =>
          'Teksturali 3D model arizada saqlangan. Uni ko\'rib chiqing yoki '
              'saqlangan qadamdan davom eting.',
      };

  static String viewModel(Locale l) => switch (l.languageCode) {
        'ru' => 'Посмотреть 3D модель',
        'en' => 'View 3D model',
        _ => '3D modelni ko\'rish',
      };

  static String continueLabel(Locale l) => switch (l.languageCode) {
        'ru' => 'Назад',
        'en' => 'Back',
        _ => 'Ortga qaytish',
      };

  static String notFound(Locale l) => switch (l.languageCode) {
        'ru' => '3D модель не найдена',
        'en' => '3D model not found',
        _ => '3D model topilmadi',
      };

  static String failed(Locale l) => switch (l.languageCode) {
        'ru' => 'Не удалось загрузить модель',
        'en' => 'Could not load the model',
        _ => 'Modelni yuklab bo\'lmadi',
      };

  static String signIn(Locale l) => switch (l.languageCode) {
        'ru' => 'Сначала войдите в систему',
        'en' => 'Please sign in first',
        _ => 'Avval tizimga kiring',
      };
}
