/// Profile → "Ilova haqida" (About app): app identity plus the appraiser
/// ("Baholovchi") certificates. The documents come from the same public source
/// as the AI Baholash pre-payment step (`GET /api/v1/appraiser/credentials`),
/// so both guests and logged-in users can view them here. Tapping a document
/// opens the shared full-screen zoomable gallery.
library;

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/remote_image.dart';
import '../market/widgets/fullscreen_gallery.dart';
import '../services/api_appraiser_service.dart';

/// Mirrors pubspec `version:` — bump alongside a release.
const String _kAppVersion = '1.0.2';

class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({super.key});

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  final AppraiserService _service = AppraiserService();
  late final Future<List<AppraiserCredential>> _future = _service
      .fetchCredentials();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _openDoc(List<AppraiserCredential> creds, AppraiserCredential tapped) {
    final images = creds
        .where((c) => c.imageUrl.isNotEmpty)
        .map((c) => c.imageUrl)
        .toList();
    final start = images.indexOf(tapped.imageUrl);
    if (start < 0) return;
    openFullscreenGallery(context, images: images, initialIndex: start);
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
                      final creds =
                          snap.data ?? const <AppraiserCredential>[];
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _AppIdentity(isDark: isDark, locale: l),
                          const SizedBox(height: 24),
                          _SectionLabel(text: _S.docsSection(l), isDark: isDark),
                          const SizedBox(height: 12),
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
                            for (final c in creds) ...[
                              _CredentialCard(
                                credential: c,
                                viewHint: _S.viewHint(l),
                                isDark: isDark,
                                onTap: () => _openDoc(creds, c),
                              ),
                              const SizedBox(height: 10),
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
        const SizedBox(height: 4),
        Text(
          '${_S.versionLabel(locale)} $_kAppVersion',
          style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: muted),
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

// ── One credential document (mirrors the AI Baholash credentials card) ─
class _CredentialCard extends StatelessWidget {
  const _CredentialCard({
    required this.credential,
    required this.viewHint,
    required this.isDark,
    required this.onTap,
  });

  final AppraiserCredential credential;
  final String viewHint;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: hapticTap(onTap),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 58,
                  height: 78,
                  child: RemoteImage(
                    url: credential.imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 240,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      credential.title,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      viewHint,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.zoom_out_map_rounded, size: 20, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty / failed-to-load note (non-blocking) ────────────────────────
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

  static String appName(Locale l) => tr(
    l,
    'about.app_name',
    uz: 'Kadastr',
    ru: 'Kadastr',
    en: 'Kadastr',
  );

  static String versionLabel(Locale l) => tr(
    l,
    'about.version',
    uz: 'Versiya',
    ru: 'Версия',
    en: 'Version',
  );

  static String tagline(Locale l) => tr(
    l,
    'about.tagline',
    uz: 'Ko\'chmas mulkni baholash, 3D kadastr va xizmatlar hisobi — '
        'litsenziyalangan ekspertlar bilan.',
    ru: 'Оценка недвижимости, 3D-кадастр и расчёт услуг — с лицензированными '
        'экспертами.',
    en: 'Property valuation, 3D cadastre and service estimates — backed by '
        'licensed experts.',
  );

  static String docsSection(Locale l) => tr(
    l,
    'about.docs_section',
    uz: 'Baholovchi hujjatlari',
    ru: 'Документы оценщика',
    en: 'Appraiser documents',
  );

  static String viewHint(Locale l) => tr(
    l,
    'about.view_hint',
    uz: 'Ko\'rish uchun bosing',
    ru: 'Нажмите, чтобы открыть',
    en: 'Tap to view',
  );

  static String empty(Locale l) => tr(
    l,
    'about.empty',
    uz: 'Hujjatlar hozircha mavjud emas',
    ru: 'Документы пока недоступны',
    en: 'Documents are not available yet',
  );
}
