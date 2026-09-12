/// AI Baholash — natijadan OLDINGI qadam: obyektning SMETA (qurilish / o'rnini
/// bosish) hujjatlari va qiymati.
///
/// Avval "Smeta hujjatlaringiz bormi?" (Ha / Yo'q) so'raladi:
///   • Yo'q  → hech narsa yig'ilmaydi, to'g'ridan-to'g'ri natijaga o'tadi.
///   • Ha    → smeta qiymati (so'm) kiritiladi + (ixtiyoriy) smeta hujjatlari
///             yuklanadi. Qiymat bundle'ga (`targetSellPrice`) yoziladi va natija
///             ekrani arizani yaratgach `PATCH /ai-valuations/{id}/target-price`
///             orqali biriktiradi — backend uni XARAJAT (tannarx) yondashuvini
///             hisoblashda ishlatadi. Hujjatlar `smeta_keys` sifatida create
///             payloadida ketadi va hisobotga (smeta papkasi) qo'shiladi.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../settings/settings_state.dart';
import '../api_ai_upload_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/choice_tile.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/wizard_nav_bar.dart';
import 'ai_status_screen.dart';

enum _UpStatus { uploading, done, failed }

/// One picked smeta document being (or already) uploaded.
class _SmetaDoc {
  _SmetaDoc(this.path, this.name);
  final String path;
  final String name;
  _UpStatus status = _UpStatus.uploading;
  String? key; // backend S3 key once uploaded
  String? error;
}

class AiTargetPriceScreen extends StatefulWidget {
  const AiTargetPriceScreen({super.key, required this.bundle});

  /// To'liq wizard bundle — narx/hujjatlar shunga yoziladi va natija ekraniga
  /// uzatiladi.
  final AiBaholashBundle bundle;

  @override
  State<AiTargetPriceScreen> createState() => _AiTargetPriceScreenState();
}

class _AiTargetPriceScreenState extends State<AiTargetPriceScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final AiUploadService _uploads = AiUploadService();

  /// null = foydalanuvchi hali tanlamagan; true = "Ha, smetam bor"; false = yo'q.
  /// Resume: bundle allaqachon smeta qiymati/hujjatlari saqlagan bo'lsa "Ha".
  bool? _hasSmeta;

  final List<_SmetaDoc> _docs = <_SmetaDoc>[];

  static const int _maxDocs = 15;

  @override
  void initState() {
    super.initState();
    final existingPrice = widget.bundle.targetSellPrice;
    if (existingPrice != null && existingPrice > 0) {
      _hasSmeta = true;
      _ctrl.text = _groupThousands(existingPrice.toInt().toString());
    } else if (widget.bundle.smetaKeys.isNotEmpty) {
      _hasSmeta = true;
    }
    // Restore already-uploaded smeta docs (resume) as done tiles.
    for (var i = 0; i < widget.bundle.smetaKeys.length; i++) {
      final key = widget.bundle.smetaKeys[i];
      final path = i < widget.bundle.smetaPaths.length
          ? widget.bundle.smetaPaths[i]
          : key;
      final doc = _SmetaDoc(path, _basename(path))
        ..status = _UpStatus.done
        ..key = key;
      _docs.add(doc);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _uploads.dispose();
    super.dispose();
  }

  double? get _enteredPrice {
    final digits = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  Future<String?> _token() async {
    final session = await const AuthStorage().loadSession();
    return session.token;
  }

  Future<void> _pickDocs() async {
    final remaining = _maxDocs - _docs.length;
    if (remaining <= 0) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png', 'webp', 'heic',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final existing = _docs.map((d) => d.path).toSet();
    final fresh = <_SmetaDoc>[];
    setState(() {
      for (final f in result.files) {
        final p = f.path;
        if (p == null || existing.contains(p)) continue;
        if (_docs.length >= _maxDocs) break;
        final doc = _SmetaDoc(p, f.name);
        _docs.add(doc);
        fresh.add(doc);
      }
    });
    for (final doc in fresh) {
      _uploadOne(doc);
    }
  }

  Future<void> _uploadOne(_SmetaDoc doc) async {
    final token = await _token();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() {
        doc.status = _UpStatus.failed;
        doc.error = _S.authRequired(localeNotifier.value);
      });
      return;
    }
    setState(() {
      doc.status = _UpStatus.uploading;
      doc.error = null;
    });
    try {
      final keys = await _uploads.upload(
        category: UploadCategory.smeta,
        filePaths: [doc.path],
        token: token,
      );
      if (!mounted) return;
      setState(() {
        if (keys.isNotEmpty) {
          doc.key = keys.first;
          doc.status = _UpStatus.done;
        } else {
          doc.status = _UpStatus.failed;
          doc.error = _S.uploadFailed(localeNotifier.value);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        doc.status = _UpStatus.failed;
        doc.error = '$e';
      });
    }
  }

  void _removeDoc(_SmetaDoc doc) {
    setState(() => _docs.remove(doc));
  }

  void _captureToBundle() {
    if (_hasSmeta == true) {
      widget.bundle.targetSellPrice = _enteredPrice;
      final done = _docs.where((d) => d.status == _UpStatus.done).toList();
      widget.bundle.smetaKeys
        ..clear()
        ..addAll(done.map((d) => d.key!).where((k) => k.isNotEmpty));
      widget.bundle.smetaPaths
        ..clear()
        ..addAll(done.map((d) => d.path));
    } else {
      // "Yo'q" — smeta ma'lumotlarini tozalab davom etamiz.
      widget.bundle.targetSellPrice = null;
      widget.bundle.smetaKeys.clear();
      widget.bundle.smetaPaths.clear();
    }
  }

  void _continue() {
    HapticFeedback.lightImpact();
    _captureToBundle();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/status'),
        builder: (_) => AiStatusScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final uploading = _docs.any((d) => d.status == _UpStatus.uploading);

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
                    title: _S.appBar(l),
                    subtitle: _S.appBarSub(l),
                    // Bu tugma butun oqimni yopadi — bitta qadam
                    // orqaga EMAS. Qadamma-qadam qaytish pastda.
                    onBack: () => closeAiWizard(context),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 7, activeIndex: 6),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      Text(
                        _S.hasSmetaQ(l),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1.2,
                          color: headingColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _S.hasSmetaSub(l),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ChoiceTile(
                        label: _S.hasSmetaYes(l),
                        selected: _hasSmeta == true,
                        onTap: () => setState(() => _hasSmeta = true),
                      ),
                      const SizedBox(height: 10),
                      ChoiceTile(
                        label: _S.hasSmetaNo(l),
                        selected: _hasSmeta == false,
                        onTap: () => setState(() => _hasSmeta = false),
                      ),
                      if (_hasSmeta == true) ...[
                        const SizedBox(height: 22),
                        Text(
                          _S.heading(l),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: headingColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _AmountField(
                          controller: _ctrl,
                          isDark: isDark,
                          suffix: _S.soum(l),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _S.docsLabel(l),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: headingColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _S.docsOptional(l),
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 12.5,
                            height: 1.35,
                            color: subColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final d in _docs) ...[
                          _DocTile(
                            doc: d,
                            isDark: isDark,
                            locale: l,
                            onRemove: () => _removeDoc(d),
                            onRetry: () => _uploadOne(d),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_docs.length < _maxDocs)
                          _AddDocButton(
                            label: _S.addDocs(l),
                            isDark: isDark,
                            onTap: _pickDocs,
                          ),
                        const SizedBox(height: 16),
                        _AssessmentNote(text: _S.assessment(l), isDark: isDark),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: WizardNavBar(
                    onBack: () => Navigator.of(context).maybePop(),
                    onContinue: _continue,
                    continueLabel: _S.continueLabel(l),
                    // Tanlov qilinishi shart; hujjatlar yuklanayotgan bo'lsa kutamiz.
                    continueEnabled: _hasSmeta != null && !uploading,
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

String _basename(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i >= 0 ? path.substring(i + 1) : path;
}

String _groupThousands(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// One uploaded/uploading smeta document row.
class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.doc,
    required this.isDark,
    required this.locale,
    required this.onRemove,
    required this.onRetry,
  });

  final _SmetaDoc doc;
  final bool isDark;
  final Locale locale;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    Widget trailing;
    switch (doc.status) {
      case _UpStatus.uploading:
        trailing = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.splashGreen,
          ),
        );
        break;
      case _UpStatus.done:
        trailing = IconButton(
          icon: Icon(Icons.close_rounded, size: 20, color: muted),
          onPressed: onRemove,
          splashRadius: 20,
        );
        break;
      case _UpStatus.failed:
        trailing = TextButton(
          onPressed: onRetry,
          child: Text(_S.retry(locale)),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: doc.status == _UpStatus.failed
              ? const Color(0xFFE0492A)
              : border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            doc.status == _UpStatus.done
                ? Icons.description_rounded
                : (doc.status == _UpStatus.failed
                    ? Icons.error_outline_rounded
                    : Icons.upload_file_rounded),
            size: 22,
            color: doc.status == _UpStatus.failed
                ? const Color(0xFFE0492A)
                : AppColors.splashGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: textColor,
                  ),
                ),
                if (doc.status == _UpStatus.failed && doc.error != null)
                  Text(
                    doc.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 11.5,
                      color: Color(0xFFE0492A),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _AddDocButton extends StatelessWidget {
  const _AddDocButton({
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded,
                  size: 20, color: AppColors.splashGreen),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.isDark,
    required this.suffix,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isDark;
  final String suffix;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.32)
        : AppColors.textBlack.withValues(alpha: 0.30);
    final suffixColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              onChanged: onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              inputFormatters: const [_MoneyInputFormatter()],
              cursorColor: AppColors.splashGreen,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w800,
                fontSize: 26,
                color: textColor,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                hintText: '0',
                hintStyle: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  color: hintColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            suffix,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: suffixColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yashil "check" bilan — foydalanuvchi baholash xulosasini olishini bildiradi.
class _AssessmentNote extends StatelessWidget {
  const _AssessmentNote({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? AppColors.splashGreen.withValues(alpha: 0.12)
        : AppColors.splashGreen.withValues(alpha: 0.08);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.splashGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_outlined,
              size: 20, color: AppColors.splashGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Digits-only with thousands grouping (`12 500 000`), cursor kept at the end.
class _MoneyInputFormatter extends TextInputFormatter {
  const _MoneyInputFormatter();

  static const int _maxDigits = 15;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > _maxDigits) digits = digits.substring(0, _maxDigits);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _S {
  const _S._();

  static String appBar(Locale l) => tr(l, 'services.ai.target_price.app_bar');

  static String appBarSub(Locale l) =>
      tr(l, 'services.ai.target_price.app_bar_sub');

  static String hasSmetaQ(Locale l) =>
      tr(l, 'services.ai.target_price.has_smeta_q');

  static String hasSmetaSub(Locale l) =>
      tr(l, 'services.ai.target_price.has_smeta_sub');

  static String hasSmetaYes(Locale l) =>
      tr(l, 'services.ai.target_price.has_smeta_yes');

  static String hasSmetaNo(Locale l) =>
      tr(l, 'services.ai.target_price.has_smeta_no');

  static String heading(Locale l) => tr(l, 'services.ai.target_price.heading');

  static String docsLabel(Locale l) =>
      tr(l, 'services.ai.target_price.docs_label');

  static String docsOptional(Locale l) =>
      tr(l, 'services.ai.target_price.docs_optional');

  static String addDocs(Locale l) =>
      tr(l, 'services.ai.target_price.add_docs');

  static String uploadFailed(Locale l) =>
      tr(l, 'services.ai.target_price.upload_failed');

  static String authRequired(Locale l) =>
      tr(l, 'services.ai.common.sign_in_first');

  static String retry(Locale l) => tr(l, 'services.ai.cadastre.retry');

  static String assessment(Locale l) =>
      tr(l, 'services.ai.target_price.assessment');

  static String soum(Locale l) => tr(l, 'services.ai.common.soum');

  static String continueLabel(Locale l) => tr(l, 'services.ai.common.continue');
}
