/// Profile → "Ilova haqida" (About app): app identity plus the appraiser
/// ("Baholovchi") certificates. The documents come from the same public source
/// as the AI Baholash pre-payment step (`GET /api/v1/appraiser/credentials`),
/// so both guests and logged-in users can view them here. Tapping a document
/// opens the shared full-screen zoomable gallery.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/app_version.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_header_back.dart';
import '../applications/pdf_viewer_screen.dart';
import '../market/widgets/fullscreen_gallery.dart';
import '../services/api_appraiser_service.dart';
import '../services/widgets/appraiser_credential_card.dart';

class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({super.key});

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  final AppraiserService _service = AppraiserService();
  late final Future<List<AppraiserCredential>> _future = _service
      .fetchCredentials();

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
    // PDFs can't go through the image gallery — download and hand to the PDF
    // viewer, which needs a local path.
    if (tapped.isPdf) {
      await _openPdf(tapped);
      return;
    }
    // Gallery holds images only, so swiping never lands on a PDF that can't
    // render.
    final images = creds
        .where((c) => !c.isPdf && c.imageUrl.isNotEmpty)
        .map((c) => c.imageUrl)
        .toList();
    final start = images.indexOf(tapped.imageUrl);
    if (start < 0) return;
    openFullscreenGallery(context, images: images, initialIndex: start);
  }

  Future<void> _openPdf(AppraiserCredential doc) async {
    if (doc.imageUrl.isEmpty || _busyPdf) return;
    setState(() => _busyPdf = true);
    try {
      final res = await http
          .get(Uri.parse(doc.imageUrl))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final dir = await getTemporaryDirectory();
      // Name it after the document so the viewer's share sheet is meaningful.
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

    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: AppHeaderBack(title: _S.title(l)),
                ),
                Expanded(
                  child: FutureBuilder<List<AppraiserCredential>>(
                    future: _future,
                    builder: (context, snap) {
                      final loading =
                          snap.connectionState == ConnectionState.waiting;
                      final creds = snap.data ?? const <AppraiserCredential>[];
                      final grouped = groupCredentialsByCategory(creds);
                      final labelled = credentialSectionsAreLabelled(grouped);
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _AppIdentity(isDark: isDark, locale: l),
                          const SizedBox(height: 20),
                          if (loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.splashGreen,
                                ),
                              ),
                            )
                          else if (creds.isEmpty)
                            _EmptyNote(text: _S.empty(l), isDark: isDark)
                          else
                            // One section per service line. An empty category
                            // never appears — it isn't in the payload at all.
                            for (final entry in grouped.entries) ...[
                              const SizedBox(height: 12),
                              if (labelled) ...[
                                _SectionLabel(
                                  text: entry.key.name(l.languageCode),
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 4),
                              ],
                              // Two-up grid of appraiser ("Baholovchi") docs.
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  const gap = 10.0;
                                  final w = (constraints.maxWidth - gap) / 2;
                                  return Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final c in entry.value)
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
                        ],
                      );
                    },
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

// ── App identity header ───────────────────────────────────────────────
class _AppIdentity extends StatelessWidget {
  const _AppIdentity({required this.isDark, required this.locale});

  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Column(
      children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            'assets/branding/appicon.png',
            width: 96,
            height: 96,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _S.appName(locale),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 6),
        // A chip, not grey body text: the version is the one fact people come
        // to this screen to read out to support.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.splashGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.splashGreen.withValues(alpha: 0.30),
            ),
          ),
          child: Text(
            '${_S.versionLabel(locale)} $kAppVersionFull',
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              height: 1.1,
              color: AppColors.splashGreen,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _S.tagline(locale),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13.5,
            height: 1.4,
            color: muted,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    return Row(
      children: [
        const Icon(
          Icons.verified_user_rounded,
          size: 20,
          color: AppColors.splashGreen,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: titleColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// One credential document, as a quiet row.
///
/// Was a bordered card repeating "Ko'rish uchun bosing" and a ⤢ glyph on every
/// entry — ten elements saying what one says. Now: hairline rows, the hint
/// collapsed into a single green affordance, and no card chrome competing with
/// the documents themselves.
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
// Backend orqali yangilanadigan (app_translations) kalitlar — inline qiymatlar
// faqat zaxira (override kelmasa). Admin i18n'da `about.*` kalitlarini qo'shib
// matnni ilova yangilanmasdan o'zgartirish mumkin.
class _S {
  const _S._();

  static String title(Locale l) => tr(
    l,
    'about.title',
    uz: 'Ilova haqida',
    ru: 'О приложении',
    en: 'About app',
  );

  static String appName(Locale l) =>
      tr(l, 'about.app_name', uz: '3D Kadastr', ru: '3D Kadastr', en: '3D Kadastr');

  static String versionLabel(Locale l) =>
      tr(l, 'about.version', uz: 'Versiya', ru: 'Версия', en: 'Version');

  static String tagline(Locale l) => tr(
    l,
    'about.tagline',
    uz:
        'Ko\'chmas mulkni baholash, 3D kadastr va xizmatlar hisobi — '
        'litsenziyalangan ekspertlar bilan.',
    ru:
        'Оценка недвижимости, 3D-кадастр и расчёт услуг — с лицензированными '
        'экспертами.',
    en:
        'Property valuation, 3D cadastre and service estimates — backed by '
        'licensed experts.',
  );

  // Short, because it now sits on every row as the tap affordance rather than
  // as a sentence of instructions under each title.
  static String viewHint(Locale l) =>
      tr(l, 'about.view_hint', uz: 'Ko\'rish →', ru: 'Открыть →', en: 'View →');

  static String empty(Locale l) => tr(
    l,
    'about.empty',
    uz: 'Hujjatlar hozircha mavjud emas',
    ru: 'Документы пока недоступны',
    en: 'Documents are not available yet',
  );

  static String openError(Locale l) => tr(
    l,
    'about.open_error',
    uz: 'Hujjatni ochib bo\'lmadi',
    ru: 'Не удалось открыть документ',
    en: 'Could not open the document',
  );
}
