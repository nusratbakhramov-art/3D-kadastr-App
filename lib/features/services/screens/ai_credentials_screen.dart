/// AI Baholash — appraiser credentials step (shown before the Payme sheet).
///
/// Reassures the user that the valuation is backed by a licensed, insured,
/// certified appraiser by showing the company's legal documents (admin-managed,
/// fetched from `GET /api/v1/appraiser/credentials`). Tapping a document opens
/// a full-screen zoomable viewer. The "To'lovga o'tish" CTA then opens the
/// payment sheet. Resilient: if the docs fail to load, the user can still pay.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/remote_image.dart';
import '../../market/widgets/fullscreen_gallery.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../payments/ai_payment_sheet.dart';
import '../api_appraiser_service.dart';
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
        onTap: onTap,
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
class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Документы оценщика',
    'en' => 'Appraiser documents',
    _ => 'Baholovchi hujjatlari',
  };

  static String subtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Лицензированный эксперт',
    'en' => 'Licensed expert',
    _ => 'Litsenziyalangan ekspert',
  };

  static String trust(Locale l) => switch (l.languageCode) {
    'ru' => 'Оценку проводит лицензированный и застрахованный эксперт',
    'en' => 'Valuation is performed by a licensed, insured expert',
    _ => 'Baholash litsenziyalangan va sug\'urtalangan ekspert tomonidan',
  };

  static String viewHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Нажмите, чтобы открыть',
    'en' => 'Tap to view',
    _ => 'Ko\'rish uchun bosing',
  };

  static String continueLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Перейти к оплате',
    'en' => 'Continue to payment',
    _ => 'To\'lovga o\'tish',
  };

  static String empty(Locale l) => switch (l.languageCode) {
    'ru' => 'Документы пока недоступны',
    'en' => 'Documents are not available yet',
    _ => 'Hujjatlar hozircha mavjud emas',
  };
}
