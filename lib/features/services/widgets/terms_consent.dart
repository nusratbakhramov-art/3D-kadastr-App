/// Reusable "I agree to the terms" gate — a manual checkbox (CAPTCHA-style) the
/// user must tick before proceeding, plus a link that opens the full terms.
///
/// The consent sheet ([showTermsAcceptanceSheet]) is the OFFER ACCEPTANCE step:
/// we sign no bilateral contract with the client, so the service is formed by
/// accepting the public offer here. That is why it asks for TWO separate ticks
/// — (1) the offer was read and is accepted, (2) the fee is non-refundable —
/// and why the caller must persist them (`POST
/// /ai-valuations/{id}/offer-acceptance`): the generated report cites this
/// acceptance, with its date and time, as the legal basis for the valuation.
///
/// The checkbox label is the agreed placeholder ("Yolg'on ma'lumot yuklamayman").
/// The full-text sheet fetches the live terms from the backend
/// (`GET /legal/terms?lang=`, admin-editable via RTE) and renders the returned
/// HTML; if the network is unavailable it falls back to the bundled text below.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

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

  /// When true the sheet is a consent gate: the user scrolls through the offer,
  /// then ticks BOTH boxes (terms accepted + payment non-refundable) before
  /// "QABUL QILAMAN" enables; it pops `true` on accept. When false it's
  /// read-only with a "Yopish" button.
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
  // Accept mode: the two boxes unlock once the user has scrolled to the end of
  // the offer (or the text already fits without scrolling).
  bool _read = false;

  // The two consents the generated report cites as its legal basis:
  //   _okTerms  — oferta shartlari o'qib chiqildi va qabul qilindi
  //   _okRefund — to'langan xizmat haqi qaytarilmasligiga rozilik
  // BOTH are required — the backend rejects a half-consent, and the report's
  // "Baholash uchun asos" paragraph asserts both were given.
  bool _okTerms = false;
  bool _okRefund = false;

  bool get _canAccept => _read && _okTerms && _okRefund;

  // ── Oferta PDF ────────────────────────────────────────────────────────
  // Backend PDF bergan bo'lsa (`pdf_url`) foydalanuvchi AYNAN shu hujjatni
  // ko'radi — HTML matn emas. Rozilik bandlari hujjat OXIRGI sahifasigacha
  // ko'rilmaguncha ochilmaydi: imzolanadigan shartnomani ko'rmasdan qabul
  // qilish mumkin bo'lmasligi kerak.
  PdfControllerPinch? _pdfCtrl;
  int _pdfPages = 0;
  int _pdfPage = 1;
  // PDF bor, lekin yuklab bo'lmadi → matnli variantga tushamiz (oqim
  // to'xtamasligi uchun), lekin rozilik gate'i baribir ishlaydi.
  bool _pdfFailed = false;

  bool get _hasPdf => _pdfCtrl != null;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _pdfCtrl?.dispose();
    super.dispose();
  }

  /// Oferta PDF'ini yuklab, keshlab, ko'rsatishga tayyorlaydi.
  ///
  /// Kesh kaliti — backend bergan `pdf_version` (fayl mtime): admin hujjatni
  /// almashtirsa versiya o'zgaradi va eski nusxa ishlatilmaydi. Shu bilan har
  /// safar 200 KB qayta yuklanmaydi ham.
  Future<void> _loadPdf(String url, int version, String lang) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/legal_terms_${lang}_$version.pdf');
      if (!file.existsSync() || file.lengthSync() == 0) {
        final res = await http
            .get(Uri.parse(ApiConfig.resolveUrl(url)))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
          throw Exception('HTTP ${res.statusCode}');
        }
        await file.writeAsBytes(res.bodyBytes, flush: true);
      }
      if (!mounted) return;
      setState(() {
        _pdfCtrl = PdfControllerPinch(document: PdfDocument.openFile(file.path));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // PDF'siz qolsak ham foydalanuvchi tiqilib qolmasin: matnli variant
      // ko'rsatiladi va o'sha yerdagi skroll gate ishlaydi.
      setState(() {
        _pdfFailed = true;
        _loading = false;
      });
      if (widget.acceptMode) _markReadIfFits();
    }
  }

  void _onScroll() {
    if (_read || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 12) {
      setState(() => _read = true);
    }
  }

  // After the content lays out, if it isn't tall enough to scroll there is
  // nothing to scroll THROUGH — count it as read, otherwise the consent boxes
  // would stay locked forever with no way for the user to unlock them.
  //
  // Runs as a post-frame callback (not a fixed delay): the check needs the
  // ListView to be attached to `_scrollCtrl`, and the frame that builds it is
  // the one this very setState schedules. A timer guess raced that frame.
  void _markReadIfFits() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
        });
        // Oferta PDF'i bo'lsa — SHU ko'rsatiladi, HTML matn emas.
        final pdfUrl = body['pdf_url'] as String?;
        final pdfVersion = (body['pdf_version'] as num?)?.toInt() ?? 0;
        if (pdfUrl != null && pdfUrl.isNotEmpty) {
          await _loadPdf(pdfUrl, pdfVersion, lang);
          return;
        }
        setState(() => _loading = false);
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
                : _hasPdf
                    ? PdfViewPinch(
                        controller: _pdfCtrl!,
                        onDocumentLoaded: (doc) {
                          if (!mounted) return;
                          setState(() => _pdfPages = doc.pagesCount);
                          // Bir sahifali hujjat — ochilishining o'zi ko'rilgan
                          // hisoblanadi (skroll qiladigan joyi yo'q).
                          if (doc.pagesCount <= 1) {
                            setState(() => _read = true);
                          }
                        },
                        onPageChanged: (page) {
                          if (!mounted) return;
                          setState(() {
                            _pdfPage = page;
                            // Oxirgi sahifaga yetdi → hujjat ko'rib chiqildi.
                            if (_pdfPages > 0 && page >= _pdfPages) {
                              _read = true;
                            }
                          });
                        },
                        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                          options: const DefaultBuilderOptions(),
                          documentLoaderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          pageLoaderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                        ),
                      )
                    : ListView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    children: [
                      // Oferta PDF'i bor edi, lekin ochib bo'lmadi — buni
                      // yashirmaymiz: foydalanuvchi qaysi hujjatga rozilik
                      // berayotganini bilishi kerak.
                      if (_pdfFailed)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _S.pdfFailed(l),
                            style: const TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 12.5,
                              color: Color(0xFF8A5A00),
                            ),
                          ),
                        ),
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
                if (widget.acceptMode && !_loading) ...[
                  // PDF sahifa hisoblagichi — foydalanuvchi qancha qolganini
                  // ko'rib tursin (gate oxirgi sahifada ochiladi).
                  if (_hasPdf && _pdfPages > 0) ...[
                    Text(
                      '$_pdfPage / $_pdfPages',
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: _read ? AppColors.splashGreen : muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _ConsentCheck(
                    value: _okTerms,
                    enabled: _read,
                    label: _S.checkOffer(l),
                    onChanged: (v) => setState(() => _okTerms = v),
                  ),
                  const SizedBox(height: 8),
                  _ConsentCheck(
                    value: _okRefund,
                    enabled: _read,
                    label: _S.checkRefund(l),
                    onChanged: (v) => setState(() => _okRefund = v),
                  ),
                  if (!_canAccept) ...[
                    const SizedBox(height: 10),
                    Text(
                      _read
                          ? _S.checkHint(l)
                          : (_hasPdf ? _S.readPdfHint(l) : _S.scrollHint(l)),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12.5,
                        color: muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
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
                        ? (_canAccept
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

/// One tick line inside the consent gate. Stays greyed out (and inert) until
/// the user has scrolled through the offer — you cannot agree to what you have
/// not been shown.
class _ConsentCheck extends StatelessWidget {
  const _ConsentCheck({
    required this.value,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final off = isDark ? const Color(0xFF4A5054) : const Color(0xFFB9BEC4);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged(!value);
              }
            : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 1),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? AppColors.splashGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? AppColors.splashGreen : off,
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
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

  static String checkOffer(Locale l) =>
      tr(l, 'services.widget.terms.check_offer');

  static String checkRefund(Locale l) =>
      tr(l, 'services.widget.terms.check_refund');

  static String checkHint(Locale l) =>
      tr(l, 'services.widget.terms.check_hint');

  static String readPdfHint(Locale l) =>
      tr(l, 'services.widget.terms.read_pdf_hint');

  static String pdfFailed(Locale l) =>
      tr(l, 'services.widget.terms.pdf_failed');

  static List<String> paragraphs(Locale l) => [
        tr(l, 'services.widget.terms.para1'),
        tr(l, 'services.widget.terms.para2'),
        tr(l, 'services.widget.terms.para3'),
      ];
}
