import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../scans/saved_scan_service.dart';
import '../ai_draft_saver.dart';
import '../api_ai_upload_service.dart';
import '../data/room_plan_scanner.dart';
import '../models/ai_scan_result.dart';
import '../widgets/service_app_bar.dart';
import 'ai_cadastre_screen.dart';

enum _ProcStage { idle, processing, done, error }

/// AI Baholashning 3-qadami — xom skanni teksturali USDZ ga ishlash.
///
/// `SavedScanService.process()` native texturing pipeline'ini ishga tushiradi
/// (MetalAtlasBaker). Tugagach `AiScanResult` tuziladi va kadastr raqami
/// qadamiga (`AiCadastreScreen`) uzatiladi.
class AiScanProcessScreen extends StatefulWidget {
  const AiScanProcessScreen({super.key, required this.scan});

  final RoomScanResult scan;

  @override
  State<AiScanProcessScreen> createState() => _AiScanProcessScreenState();
}

class _AiScanProcessScreenState extends State<AiScanProcessScreen> {
  final SavedScanService _service = SavedScanService();
  _ProcStage _stage = _ProcStage.idle;
  AiScanResult? _result;
  String? _error;
  bool _uploading = false;
  // Continue bosilganda to'liq skan to'plamini yuklash progressi.
  int _upDone = 0; // yuborilgan fayllar soni
  int _upTotal = 0; // jami fayllar
  int _upBytesSent = 0;
  int _upBytesTotal = 0;

  int get _scanId => widget.scan.savedScanId!;

  @override
  void initState() {
    super.initState();
    // Foydalanuvchi skan oxirida "Process" tugmasini bosib keldi — tekstura
    // render'ni DARHOL boshlaymiz (qo'shimcha tugma bosish shart emas). Shunday
    // qilib: Process → render → teksturali natija "3D modelni ko'rish" da.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _process();
    });
  }

  Future<void> _process() async {
    if (_stage == _ProcStage.processing) return;
    HapticFeedback.lightImpact();
    setState(() {
      _stage = _ProcStage.processing;
      _error = null;
    });
    try {
      final res = await _service.process(_scanId);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _stage = _ProcStage.error;
          _error = _S.failed(Localizations.localeOf(context));
        });
        return;
      }
      setState(() {
        _result = AiScanResult(
          savedScanId: _scanId,
          version: res.version,
          usdzPath: res.filePath,
          floorAreaSqm: widget.scan.floorAreaSqm,
          walls: widget.scan.walls,
          doors: widget.scan.doors,
          windows: widget.scan.windows,
          objects: widget.scan.objects,
        );
        _stage = _ProcStage.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _ProcStage.error;
        _error = '$e';
      });
    }
  }

  Future<void> _continue() async {
    final r = _result;
    if (r == null || _uploading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _uploading = true;
      _upDone = 0;
      _upTotal = 0;
      _upBytesSent = 0;
      _upBytesTotal = 0;
    });

    // Backendga FAQAT 2 ta modelni yuklaymiz: GLB (asosiy) + USDZ (zaxira/
    // QuickLook). Mesh/geo/png/manifest/frames backendga kerak emas — model
    // faqat 3D ko'rsatish/saqlash uchun ishlatiladi. "glb" kaliti asosiy model
    // sifatida scan_usdz_key ga ham yoziladi (orqaga moslik). Yuklash
    // best-effort: tarmoq yo'q/xato bo'lsa oqim baribir davom etadi (asosiy
    // modelni alohida yuklab ko'ramiz).
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    Map<String, dynamic>? scanFiles;
    String? scanKey;

    if (token != null && token.isNotEmpty) {
      final all = await _service.listScanFiles(_scanId);
      final files = all
          .where((f) => f.type == 'glb' || f.type == 'usdz')
          .toList(growable: false);
      if (files.isNotEmpty) {
        final svc = AiUploadService();
        try {
          scanFiles = await svc.uploadBundle(
            entries: files.map((f) => f.entry).toList(growable: false),
            token: token,
            onProgress: (done, total, sent, totalBytes) {
              if (!mounted) return;
              setState(() {
                _upDone = done;
                _upTotal = total;
                _upBytesSent = sent;
                _upBytesTotal = totalBytes;
              });
            },
          );
          scanKey = (scanFiles['glb'] ?? scanFiles['usdz']) as String?;
        } catch (_) {
          // bundle yuklash yiqildi — quyida asosiy modelni alohida yuboramiz
        } finally {
          svc.dispose();
        }
      }
    }
    // Zaxira: to'plam bo'sh/yiqilgan bo'lsa, hech bo'lmasa asosiy modelni yukla.
    scanKey ??= await _uploadUsdz(r.usdzPath);

    // Skandan keyin DRAFT ariza (skan kaliti + to'liq to'plam + keyingi qadam).
    final draftId = await createAiDraft(
      currentStep: 'cadastre',
      scanUsdzKey: scanKey,
      scanFiles: scanFiles,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    // Skan oqimi tugadi — kadastr qadamiga o'tamiz (process ekraniga qaytmaymiz).
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/cadastre'),
        builder: (_) => AiCadastreScreen(scan: r, draftId: draftId),
      ),
    );
  }

  /// USDZ ni backendga yuklaydi (best-effort). Kalit yoki null qaytaradi.
  Future<String?> _uploadUsdz(String path) async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) return null;
    final svc = AiUploadService();
    try {
      final keys = await svc.upload(
        category: UploadCategory.scanModel,
        filePaths: [path],
        token: token,
      );
      return keys.isNotEmpty ? keys.first : null;
    } catch (_) {
      return null; // yuklash muvaffaqiyatsiz bo'lsa ham oqim davom etadi
    } finally {
      svc.dispose();
    }
  }

  Future<void> _viewModel() async {
    final r = _result;
    if (r == null) return;
    HapticFeedback.lightImpact();
    // Teksturali USDZ ni native QuickLook'da ochadi (aylantirib/zoom ko'rish).
    // Xom LiDAR mesh EMAS — process natijasi (rangli tekstura).
    await _service.preview(r.usdzPath);
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

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
                Expanded(child: _buildBody(context, l, isDark)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _buildCta(l),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCta(Locale l) {
    if (_uploading) return const _BusyButton();
    switch (_stage) {
      case _ProcStage.done:
        return ListingCtaButton(label: _S.continueLabel(l), onTap: _continue);
      case _ProcStage.processing:
        return const _BusyButton();
      case _ProcStage.idle:
        return ListingCtaButton(label: _S.startProcess(l), onTap: _process);
      case _ProcStage.error:
        return ListingCtaButton(label: _S.retry(l), onTap: _process);
    }
  }

  Widget _buildBody(BuildContext context, Locale l, bool isDark) {
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    // Continue bosilgach — to'plam yuklash progressi (X/N fayl, MB, foiz).
    if (_uploading) return _buildUploadProgress(l, isDark, textColor, subColor);

    final (IconData icon, Color iconColor, String heading, String body)
        content = switch (_stage) {
      _ProcStage.done => (
          Icons.view_in_ar_rounded,
          AppColors.splashGreen,
          _S.doneHeading(l),
          _S.doneBody(l),
        ),
      _ProcStage.error => (
          Icons.error_outline_rounded,
          const Color(0xFFE0492A),
          _S.errorHeading(l),
          _error ?? _S.failed(l),
        ),
      _ProcStage.processing => (
          Icons.auto_awesome_rounded,
          AppColors.splashGreen,
          _S.processingHeading(l),
          _S.processingBody(l),
        ),
      _ProcStage.idle => (
          Icons.auto_awesome_rounded,
          AppColors.splashGreen,
          _S.idleHeading(l),
          _S.idleBody(l),
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
      children: [
        Center(
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_stage == _ProcStage.processing)
                  const SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.splashGreen),
                    ),
                  ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: content.$2.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(content.$1, size: 42, color: content.$2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          content.$3,
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
          content.$4,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 14,
            height: 1.4,
            color: subColor,
          ),
        ),
        if (_stage == _ProcStage.done) ...[
          const SizedBox(height: 28),
          _ViewModelButton(label: _S.viewModel(l), onTap: _viewModel),
        ],
      ],
    );
  }

  /// "Ma'lumotlar yuklanmoqda" — to'liq skan to'plamini yuklash progressi.
  /// Foiz baytlar bo'yicha (aniqroq); fayl hisobi (X/N) qo'shimcha ko'rsatkich.
  Widget _buildUploadProgress(
      Locale l, bool isDark, Color textColor, Color subColor) {
    final double? pct = _upBytesTotal > 0
        ? (_upBytesSent / _upBytesTotal).clamp(0.0, 1.0)
        : (_upTotal > 0 ? (_upDone / _upTotal).clamp(0.0, 1.0) : null);
    final pctLabel = pct != null ? '${(pct * 100).round()}%' : '…';
    final mbSent = (_upBytesSent / (1024 * 1024)).toStringAsFixed(1);
    final mbTotal = (_upBytesTotal / (1024 * 1024)).toStringAsFixed(1);
    final track = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
      children: [
        Center(
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 2.6,
                    backgroundColor: track,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.splashGreen),
                  ),
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.splashGreen.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_upload_rounded,
                      size: 40, color: AppColors.splashGreen),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _S.uploadingHeading(l),
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
          _S.uploadingBody(l),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 14,
            height: 1.4,
            color: subColor,
          ),
        ),
        const SizedBox(height: 28),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: track,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.splashGreen),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$_upDone / $_upTotal ${_S.filesWord(l)} · $pctLabel',
              style: TextStyle(
                  fontFamily: 'MTSText', fontSize: 13, color: subColor),
            ),
            Text(
              '$mbSent / $mbTotal MB',
              style: TextStyle(
                  fontFamily: 'MTSText', fontSize: 13, color: subColor),
            ),
          ],
        ),
      ],
    );
  }
}

class _ViewModelButton extends StatelessWidget {
  const _ViewModelButton({required this.label, required this.onTap});

  final String label;
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
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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

class _BusyButton extends StatelessWidget {
  const _BusyButton();

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

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
        'ru' => 'AI Оценка',
        'en' => 'AI Valuation',
        _ => 'AI Baholash',
      };

  static String subtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Шаг 3 — обработка в USDZ',
        'en' => 'Step 3 — process into USDZ',
        _ => '3-qadam — USDZ ga ishlash',
      };

  static String idleHeading(Locale l) => switch (l.languageCode) {
        'ru' => 'Обработать скан',
        'en' => 'Process the scan',
        _ => 'Skanni ishlash',
      };

  static String idleBody(Locale l) => switch (l.languageCode) {
        'ru' =>
          'Сейчас скан превратится в текстурированную 3D модель (USDZ). '
              'Это занимает около минуты.',
        'en' =>
          'The scan will be turned into a textured 3D model (USDZ). '
              'This takes about a minute.',
        _ =>
          'Skan teksturali 3D modelga (USDZ) aylantiriladi. '
              'Bu taxminan bir daqiqa oladi.',
      };

  static String processingHeading(Locale l) => switch (l.languageCode) {
        'ru' => 'Обработка…',
        'en' => 'Processing…',
        _ => 'Ishlanmoqda…',
      };

  static String processingBody(Locale l) => switch (l.languageCode) {
        'ru' => 'Строим текстуру и собираем USDZ. Не закрывайте экран.',
        'en' => 'Building texture and assembling USDZ. Keep the screen open.',
        _ => 'Tekstura qurilyapti va USDZ yig\'ilyapti. Ekranni yopmang.',
      };

  static String doneHeading(Locale l) => switch (l.languageCode) {
        'ru' => 'Текстура готова',
        'en' => 'Texture ready',
        _ => 'Tekstura tayyor',
      };

  static String doneBody(Locale l) => switch (l.languageCode) {
        'ru' =>
          'Текстурированная 3D модель готова. Посмотрите её или продолжайте.',
        'en' =>
          'The textured 3D model is ready. Preview it or continue.',
        _ =>
          'Teksturali 3D model tayyor. Ko\'rib chiqing yoki davom eting.',
      };

  static String viewModel(Locale l) => switch (l.languageCode) {
        'ru' => 'Посмотреть 3D модель',
        'en' => 'View 3D model',
        _ => '3D modelni ko\'rish',
      };

  static String errorHeading(Locale l) => switch (l.languageCode) {
        'ru' => 'Не удалось обработать',
        'en' => 'Processing failed',
        _ => 'Ishlab bo\'lmadi',
      };

  static String startProcess(Locale l) => switch (l.languageCode) {
        'ru' => 'Начать обработку',
        'en' => 'Start processing',
        _ => 'Ishlashni boshlash',
      };

  static String continueLabel(Locale l) => switch (l.languageCode) {
        'ru' => 'Продолжить',
        'en' => 'Continue',
        _ => 'Davom etish',
      };

  static String uploadingHeading(Locale l) => switch (l.languageCode) {
        'ru' => 'Загрузка данных',
        'en' => 'Uploading data',
        _ => 'Ma\'lumotlar yuklanmoqda',
      };

  static String uploadingBody(Locale l) => switch (l.languageCode) {
        'ru' =>
          'Все файлы скана (фото, 3D модель, меш) отправляются на сервер. '
              'Не закрывайте экран.',
        'en' =>
          'All scan files (photos, 3D model, mesh) are being sent to the '
              'server. Keep the screen open.',
        _ =>
          'Skanning barcha fayllari (rasmlar, 3D model, mesh) serverga '
              'yuborilmoqda. Ekranni yopmang.',
      };

  static String filesWord(Locale l) => switch (l.languageCode) {
        'ru' => 'файлов',
        'en' => 'files',
        _ => 'fayl',
      };

  static String retry(Locale l) => switch (l.languageCode) {
        'ru' => 'Повторить',
        'en' => 'Try again',
        _ => 'Qayta urinish',
      };

  static String failed(Locale l) => switch (l.languageCode) {
        'ru' => 'Обработка не удалась',
        'en' => 'Processing failed',
        _ => 'Ishlash muvaffaqiyatsiz',
      };
}
