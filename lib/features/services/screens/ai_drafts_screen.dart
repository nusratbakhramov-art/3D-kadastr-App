import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../../widgets/app_toast.dart';
import '../api_ai_valuation_job_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import 'ai_cadastre_screen.dart';
import 'ai_client_form_screen.dart';
import 'ai_intake_screen.dart';
import 'ai_location_screen.dart';
import 'ai_purpose_screen.dart';

/// "Mening arizalarim" — tugallanmagan (DRAFT) AI Baholash arizalari.
/// Tap → qolgan qadamdan davom (resume). Backend `GET /ai-valuations/drafts`.
class AiDraftsScreen extends StatefulWidget {
  const AiDraftsScreen({super.key});

  @override
  State<AiDraftsScreen> createState() => _AiDraftsScreenState();
}

class _AiDraftsScreenState extends State<AiDraftsScreen> {
  final AiValuationJobService _service = AiValuationJobService();
  List<AiJobSummary>? _drafts;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _S.signIn(Localizations.localeOf(context));
      });
      return;
    }
    try {
      final list = await _service.listDrafts(token: token);
      if (!mounted) return;
      setState(() {
        _drafts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _resume(AiJobSummary d) async {
    HapticFeedback.lightImpact();
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) return;
    try {
      final snap = await _service.get(d.id, token: token);
      if (!mounted) return;
      final bundle =
          AiBaholashBundle.fromJson(snap.requestPayload, draftId: snap.id);
      // Resume SAQLANGAN qadamdan boshlanadi. Skan qilingan bo'lsa (scan_usdz_key
      // bor), saqlangan qadamda "3D modelni ko'rish" tugmasi chiqadi.
      final scanJobId =
          (snap.scanUsdzKey != null && snap.scanUsdzKey!.isNotEmpty)
              ? snap.id
              : null;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _stepScreen(bundle, snap.currentStep, scanJobId),
        ),
      );
      if (mounted) _load(); // qaytib kelganda ro'yxatni yangilash
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '$e');
    }
  }

  /// Saqlangan qadam nomidan mos wizard ekranini quradi (skan qadamidan
  /// keyingi qadamlar). `scanJobId` — skan bor bo'lsa, cadastre qadamida
  /// "3D modelni ko'rish" tugmasi chiqadi.
  Widget _stepScreen(AiBaholashBundle bundle, String? step, int? scanJobId) {
    switch (step) {
      // Legacy 'area' drafts resume into the cadastre step (falls through to
      // default), which now owns the object area.
      case 'client':
        return AiClientFormScreen(bundle: bundle);
      case 'location':
        return AiLocationScreen(bundle: bundle);
      case 'purpose':
        return AiPurposeScreen(bundle: bundle);
      case 'intake':
      case 'payment':
        return AiIntakeScreen(bundle: bundle);
      default: // 'cadastre' yoki noma'lum — kadastr qadamidan
        return AiCadastreScreen(
          scan: bundle.scan,
          draftId: bundle.draftId,
          scanJobId: scanJobId,
          areaM2: bundle.areaM2,
        );
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
                Expanded(child: _body(l, isDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(Locale l, bool isDark) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.splashGreen),
      );
    }
    if (_error != null) {
      return _Message(text: _error!, onRetry: _load, locale: l);
    }
    final drafts = _drafts ?? const [];
    if (drafts.isEmpty) {
      return _Message(text: _S.empty(l), onRetry: _load, locale: l);
    }
    return RefreshIndicator(
      color: AppColors.splashGreen,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: drafts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _DraftCard(
          draft: drafts[i],
          isDark: isDark,
          locale: l,
          onTap: () => _resume(drafts[i]),
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.isDark,
    required this.locale,
    required this.onTap,
  });

  final AiJobSummary draft;
  final bool isDark;
  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final title = (draft.cadastreNumber?.trim().isNotEmpty ?? false)
        ? draft.cadastreNumber!
        : '${_S.application(locale)} #${draft.id}';

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.splashGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.edit_document,
                    color: AppColors.splashGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5A23D).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _S.draftBadge(locale),
                            style: const TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Color(0xFFE5A23D),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _S.stepLabel(locale, draft.currentStep),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 12,
                              color: sub,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _S.resume(locale),
                    style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.splashGreen,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.splashGreen, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.onRetry,
    required this.locale,
  });

  final String text;
  final VoidCallback onRetry;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: sub),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'MTSText', fontSize: 14, color: sub),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_S.refresh(locale)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.splashGreen,
                side: const BorderSide(color: AppColors.splashGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'services.ai.drafts.title');

  static String subtitle(Locale l) => tr(l, 'services.ai.drafts.subtitle');

  static String empty(Locale l) => tr(l, 'services.ai.drafts.empty');

  static String signIn(Locale l) => tr(l, 'services.ai.common.sign_in_first');

  static String refresh(Locale l) => tr(l, 'services.ai.drafts.refresh');

  static String resume(Locale l) => tr(l, 'services.ai.common.continue');

  static String application(Locale l) => tr(l, 'services.ai.drafts.application');

  static String draftBadge(Locale l) => tr(l, 'services.ai.drafts.draft_badge');

  static String stepLabel(Locale l, String? step) {
    final name = switch (step) {
      'cadastre' => tr(l, 'services.ai.drafts.step.cadastre'),
      'client' => tr(l, 'services.ai.drafts.step.client'),
      'location' => tr(l, 'services.ai.drafts.step.location'),
      'purpose' => tr(l, 'services.ai.drafts.step.purpose'),
      'intake' => tr(l, 'services.ai.drafts.step.intake'),
      'payment' => tr(l, 'services.ai.drafts.step.payment'),
      _ => tr(l, 'services.ai.drafts.step.start'),
    };
    return '${tr(l, 'services.ai.drafts.step_prefix')}: $name';
  }
}
