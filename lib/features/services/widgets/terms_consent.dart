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
import '../../../core/i18n/app_translations.dart';
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
  const _TermsSheet({this.acceptMode = false});

  /// When true the sheet is a consent gate: it shows an "QABUL QILAMAN" button
  /// (enabled only once the user has scrolled through the terms) and pops
  /// `true` on accept. When false it's read-only with a "Yopish" button.
  final bool acceptMode;

  @override
  State<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<_TermsSheet> {
  String? _title; // backend-provided heading
  String? _html; // backend HTML body
  bool _loading = true;
  bool _offline = false; // true → show the bundled fallback text
  bool _started = false;

  final ScrollController _scrollCtrl = ScrollController();
  // Accept mode: enabled once the user has scrolled to the end of the terms
  // (or the text already fits without scrolling).
  bool _read = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_read || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 12) {
      setState(() => _read = true);
    }
  }

  // After content lays out, if it isn't tall enough to scroll, count it as read.
  void _markReadIfFits() {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || _read) return;
      if (_scrollCtrl.hasClients &&
          _scrollCtrl.position.maxScrollExtent <= 0) {
        setState(() => _read = true);
      }
    });
  }

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
        if (widget.acceptMode) _markReadIfFits();
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
      if (widget.acceptMode) _markReadIfFits();
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
                    controller: _scrollCtrl,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.acceptMode && !_read && !_loading) ...[
                  Text(
                    _S.scrollHint(l),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 12.5,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.splashGreen,
                      disabledBackgroundColor:
                          AppColors.splashGreen.withValues(alpha: 0.35),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: widget.acceptMode
                        ? (_read
                            ? () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop(true);
                              }
                            : null)
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      widget.acceptMode ? _S.accept(l) : _S.close(l),
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white,
                      ),
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

/// Shows the terms as a consent gate: the user scrolls through them and taps
/// "QABUL QILAMAN". Returns true only if accepted (false if dismissed).
Future<bool> showTermsAcceptanceSheet(BuildContext context) async {
  HapticFeedback.selectionClick();
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TermsSheet(acceptMode: true),
  );
  return accepted == true;
}

class _S {
  const _S._();

  static String label(Locale l) => tr(l, 'services.widget.terms.label');

  static String readFull(Locale l) => tr(l, 'services.widget.terms.read_full');

  static String sheetTitle(Locale l) =>
      tr(l, 'services.widget.terms.sheet_title');

  static String close(Locale l) => tr(l, 'services.widget.terms.close');

  static String accept(Locale l) => tr(l, 'services.widget.terms.accept');

  static String scrollHint(Locale l) =>
      tr(l, 'services.widget.terms.scroll_hint');

  static List<String> paragraphs(Locale l) => [
        tr(l, 'services.widget.terms.para1'),
        tr(l, 'services.widget.terms.para2'),
        tr(l, 'services.widget.terms.para3'),
      ];
}
