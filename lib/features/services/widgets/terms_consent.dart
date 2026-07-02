/// Reusable "I agree to the terms" gate — a manual checkbox (CAPTCHA-style) the
/// user must tick before proceeding, plus a link that opens the full terms.
///
/// The checkbox label is the agreed placeholder ("Yolg'on ma'lumot yuklamayman").
/// The full-text sheet fetches the live terms from the backend
/// (`GET /legal/terms?lang=`, admin-editable via RTE) and renders the returned
/// HTML; if the network is unavailable it falls back to the bundled text below.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';
import '../../../theme/app_colors.dart';

class TermsConsent extends StatelessWidget {
  const TermsConsent({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Whether the box is currently ticked.
  final bool value;

  /// Called with the new value when the user toggles the box.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = value
        ? AppColors.splashGreen.withValues(alpha: 0.55)
        : (isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8));
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final linkColor = AppColors.splashGreen;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CAPTCHA-style manual checkbox.
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(!value);
            },
            child: Container(
              margin: const EdgeInsets.only(top: 1),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? AppColors.splashGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: value
                      ? AppColors.splashGreen
                      : (isDark
                          ? const Color(0xFF4A5054)
                          : const Color(0xFFB9BEC4)),
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(!value);
                  },
                  child: Text(
                    _S.label(l),
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _openTerms(context),
                  child: Text(
                    _S.readFull(l),
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: linkColor,
                      decoration: TextDecoration.underline,
                      decorationColor: linkColor,
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

  void _openTerms(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TermsSheet(),
    );
  }
}

class _TermsSheet extends StatefulWidget {
  const _TermsSheet();

  @override
  State<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<_TermsSheet> {
  String? _title; // backend-provided heading
  String? _html; // backend HTML body
  bool _loading = true;
  bool _offline = false; // true → show the bundled fallback text
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Localizations lookup is only valid here (not in initState).
    if (_started) return;
    _started = true;
    unawaited(_load(Localizations.localeOf(context).languageCode));
  }

  Future<void> _load(String lang) async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/legal/terms?lang=$lang'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _title = body['title'] as String?;
          _html = body['content'] as String?;
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // fall through to the bundled fallback
    }
    if (mounted) {
      setState(() {
        _offline = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF14181A) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    final media = MediaQuery.of(context);
    final bodyStyle = TextStyle(
      fontFamily: 'MTSText',
      fontSize: 14,
      height: 1.55,
      color: textColor,
    );

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (_title != null && _title!.trim().isNotEmpty)
                        ? _title!
                        : _S.sheetTitle(l),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    children: [
                      if (_offline) ...[
                        for (final p in _S.paragraphs(l))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(p, style: bodyStyle),
                          ),
                      ] else
                        HtmlWidget(_html ?? '', textStyle: bodyStyle),
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + media.padding.bottom),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.splashGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  _S.close(l),
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  // Placeholder checkbox label (final legal text pending).
  static String label(Locale l) => _pick(
        l,
        'Yolg\'on ma\'lumot yuklamayman',
        'Не буду загружать ложную информацию',
        'I will not upload false information',
      );

  static String readFull(Locale l) => _pick(
        l,
        'Shartlarni to\'liq o\'qish',
        'Читать условия полностью',
        'Read the full terms',
      );

  static String sheetTitle(Locale l) => _pick(
        l,
        'Foydalanish shartlari',
        'Условия использования',
        'Terms of use',
      );

  static String close(Locale l) => _pick(l, 'Yopish', 'Закрыть', 'Close');

  static List<String> paragraphs(Locale l) => switch (l.languageCode) {
        'ru' => const [
            'Пользуясь сервисом оценки, вы подтверждаете, что предоставленные '
                'данные, фотографии и документы являются достоверными и '
                'принадлежат оцениваемому объекту.',
            'Загрузка ложной, чужой или вводящей в заблуждение информации '
                'запрещена и может привести к отклонению заявки.',
            'Оценка носит предварительный характер; окончательное заключение '
                'выдаётся лицензированным экспертом.',
          ],
        'en' => const [
            'By using the valuation service you confirm that the data, photos '
                'and documents you provide are truthful and belong to the '
                'object being valued.',
            'Uploading false, third-party or misleading information is '
                'prohibited and may lead to your request being rejected.',
            'The valuation is preliminary; the final conclusion is issued by a '
                'licensed expert.',
          ],
        _ => const [
            'Baholash xizmatidan foydalanar ekansiz, siz taqdim etgan '
                'ma\'lumotlar, rasmlar va hujjatlar haqiqiy ekanini hamda '
                'baholanayotgan obyektga tegishli ekanini tasdiqlaysiz.',
            'Yolg\'on, o\'zganing yoki chalg\'ituvchi ma\'lumot yuklash '
                'taqiqlanadi va ariza rad etilishiga olib kelishi mumkin.',
            'Baholash dastlabki xarakterga ega; yakuniy xulosa litsenziyalangan '
                'ekspert tomonidan beriladi.',
          ],
      };
}
