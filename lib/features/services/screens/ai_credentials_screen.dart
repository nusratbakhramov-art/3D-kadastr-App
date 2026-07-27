/// AI Baholash — appraiser credentials step (shown before the Payme sheet).
///
/// Reassures the user that the valuation is backed by a licensed, insured,
/// certified appraiser by showing the company's legal documents (admin-managed,
/// fetched from `GET /api/v1/appraiser/credentials`). Tapping a document opens
/// a full-screen zoomable viewer. The "To'lovga o'tish" CTA then opens the
/// payment sheet. Resilient: if the docs fail to load, the user can still pay.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../market/widgets/fullscreen_gallery.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../applications/pdf_viewer_screen.dart';
import '../../payments/ai_payment_sheet.dart';
import '../api_appraiser_service.dart';
import '../widgets/appraiser_credential_card.dart';
import '../widgets/service_app_bar.dart';

class AiCredentialsScreen extends StatefulWidget {
  const AiCredentialsScreen({super.key, required this.referenceId});

  /// AI valuation job id — forwarded to the payment sheet.
  final int? referenceId;

  @override
  State<AiCredentialsScreen> createState() => _AiCredentialsScreenState();
}

class _AiCredentialsScreenState extends State<AiCredentialsScreen> {
  final AppraiserService _service = AppraiserService();

  late final Future<List<AppraiserCredential>> _future = _service
      .fetchCredentials()
      .then(appraiserCredentialsOnly);

  /// Guards against a second tap while a PDF is downloading.
  bool _busyPdf = false;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _openDoc(
    List<AppraiserCredential> creds,
    AppraiserCredential tapped,
  ) async {
    if (tapped.isPdf) {
      await _openPdf(tapped);
      return;
    }
    // Images only — the gallery can't render a PDF, so swiping must never land
    // on one.
    final images = creds
        .where((c) => !c.isPdf && c.imageUrl.isNotEmpty)
        .map((c) => c.imageUrl)
        .toList();
    final start = images.indexOf(tapped.imageUrl);
    if (start < 0) return;
    openFullscreenGallery(context, images: images, initialIndex: start);
  }

  /// The PDF viewer needs a local path, so fetch to a temp file first.
  Future<void> _openPdf(AppraiserCredential doc) async {
    if (doc.imageUrl.isEmpty || _busyPdf) return;
    setState(() => _busyPdf = true);
    try {
      final res = await http
          .get(Uri.parse(doc.imageUrl))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final dir = await getTemporaryDirectory();
      final safe = doc.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final file = File('${dir.path}/${safe.isEmpty ? 'hujjat' : safe}.pdf');
      await file.writeAsBytes(res.bodyBytes);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PdfViewerScreen(filePath: file.path, title: doc.title),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_S.openError(Localizations.localeOf(context))),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
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
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<AppraiserCredential>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.splashGreen,
                          ),
                        );
                      }
                      final creds = snap.data ?? const <AppraiserCredential>[];
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          _TrustBanner(text: _S.trust(l), isDark: isDark),
                          const SizedBox(height: 14),
                          if (creds.isEmpty)
                            _EmptyNote(text: _S.empty(l), isDark: isDark)
                          else
                            // Two-up poster grid — same as the profile About page.
                            LayoutBuilder(
                              builder: (context, constraints) {
                                const gap = 10.0;
                                final w = (constraints.maxWidth - gap) / 2;
                                return Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    for (final c in creds)
                                      SizedBox(
                                        width: w,
                                        child: AppraiserCredentialCard(
                                          credential: c,
                                          viewHint: _S.viewHint(l),
                                          isDark: isDark,
                                          poster: true,
                                          onTap: () => _openDoc(creds, c),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _S.continueLabel(l),
                    enabled: true,
                    onTap: () => showAiPaymentSheet(
                      context,
                      referenceId: widget.referenceId,
                    ),
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

// ── Trust banner ──────────────────────────────────────────────────────
class _TrustBanner extends StatelessWidget {
  const _TrustBanner({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.splashGreen.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            size: 22,
            color: AppColors.splashGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: AppColors.splashGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── One credential document ───────────────────────────────────────────
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: muted),
        ),
      ),
    );
  }
}

// ── Localized strings ─────────────────────────────────────────────────
class _S {
  const _S._();

  static String title(Locale l) =>
      tr(l, 'services.scan.credentials.title');

  static String subtitle(Locale l) =>
      tr(l, 'services.scan.credentials.subtitle');

  static String trust(Locale l) =>
      tr(l, 'services.scan.credentials.trust');

  static String viewHint(Locale l) =>
      tr(l, 'services.scan.credentials.view_hint');

  static String continueLabel(Locale l) =>
      tr(l, 'ai.credentials.use_service');

  static String empty(Locale l) =>
      tr(l, 'services.scan.credentials.empty');

  static String openError(Locale l) =>
      tr(l, 'services.scan.credentials.open_error');
}
