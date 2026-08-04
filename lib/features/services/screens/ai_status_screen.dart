/// Step 4 of AI Baholash — submit + poll job status + render the result.
///
/// On open: POSTs the bundle, then polls `GET /ai-valuations/{id}` every
/// few seconds until `completed` / `failed`. Renders one of three screens:
///   - in-flight progress (queued / gathering_info / ai_pricing)
///   - completed result (price, range, confidence, top comparables, POIs)
///   - failure (error_message + retry-by-resubmit)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../home/user_profile.dart' show paymentsHidden;
import '../../market/widgets/listing_cta_button.dart';
import '../../support/support_service.dart';
import '../api_ai_valuation_job_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/terms_consent.dart';
import 'ai_credentials_screen.dart';

class AiStatusScreen extends StatefulWidget {
  /// Wizard entry — submits [bundle] (draft → queued), then polls + renders.
  const AiStatusScreen({super.key, required this.bundle}) : existingJobId = null;

  /// "Davom etish → to'lov" entry: reopen an EXISTING preview-ready job by id
  /// (no re-submit) so the user lands back on the result + paywall screen they
  /// left off at and can continue to payment. Used from the "Jarayonda" card.
  const AiStatusScreen.existing({super.key, required int jobId})
      : bundle = null,
        existingJobId = jobId;

  /// Non-null only on the wizard (submit) entry.
  final AiBaholashBundle? bundle;

  /// Non-null only on the reopen-existing entry.
  final int? existingJobId;

  @override
  State<AiStatusScreen> createState() => _AiStatusScreenState();
}

class _AiStatusScreenState extends State<AiStatusScreen> {
  static const Duration _pollInterval = Duration(seconds: 4);

  final AiValuationJobService _api = AiValuationJobService();

  int? _jobId;
  AiJobSnapshot? _snapshot;
  bool _submitting = true;
  String? _submitError;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (widget.existingJobId != null) {
      _openExisting();
    } else {
      _submit();
    }
  }

  // ── Reopen an existing job (no submit) ───────────────────────────────
  // For a preview-ready ariza the user already saw but left without paying:
  // skip submit, just fetch the snapshot and poll. The result view + paywall
  // render exactly as they did the first time.
  Future<void> _openExisting() async {
    setState(() => _submitting = false);
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _submitError =
          _AiStatusStrings.errLogin(Localizations.localeOf(context)));
      return;
    }
    setState(() => _jobId = widget.existingJobId);
    _startPolling(token);
  }

  /// Retry the right entry: reopen-existing has no bundle to re-submit.
  void _retry() {
    if (widget.existingJobId != null) {
      _openExisting();
    } else {
      _submit();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _api.dispose();
    super.dispose();
  }

  // ── Submit + poll ────────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = _AiStatusStrings.errLogin(
          Localizations.localeOf(context),
        );
      });
      return;
    }
    try {
      // MAVJUD draft bo'lsa (skan/3D model biriktirilgan) — uни yakunlaymiz
      // (draft → queued), yangi job YARATMAYMIZ. Aks holda yangi job.
      final bundle = widget.bundle!; // non-null on the wizard (submit) entry
      final draftId = bundle.draftId;
      final id = draftId != null
          ? await _api.submitDraft(
              draftId: draftId,
              bundleJson: bundle.toJson(),
              token: token,
            )
          : await _api.create(bundleJson: bundle.toJson(), token: token);
      // Maqsadli narx/maydon natijadan OLDIN kiritilgan bo'lsa — ariza
      // yaratilgach darhol biriktiramiz (best-effort; uzilsa bloklamaymiz).
      final price = bundle.targetSellPrice;
      final area = bundle.areaM2;
      if (price != null || area != null) {
        try {
          await _api.setTargetPrice(
            jobId: id,
            price: price,
            areaM2: area,
            token: token,
          );
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _jobId = id;
        _submitting = false;
      });
      HapticFeedback.lightImpact();
      _startPolling(token);
    } on AiValuationApiException catch (e) {
      if (!mounted) return;
      // DEV diagnostika: 422 da qaysi maydon validatsiyadan o'tmaganini logga
      // chiqaramiz (foydalanuvchiga ko'rsatmaymiz).
      if (e.statusCode == 422) {
        debugPrint('AI valuation 422 detail: ${e.message}');
      }
      setState(() {
        _submitting = false;
        // 422 = server-side input validation. Don't surface the raw backend
        // detail — show a clean localized message.
        _submitError = e.statusCode == 422
            ? _AiStatusStrings.invalidData(Localizations.localeOf(context))
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      final handled = await NetworkErrorHandler.maybeShow(
        context,
        e,
        onRetry: _submit,
      );
      if (!mounted) return;
      if (handled) return;
      setState(() {
        _submitting = false;
        _submitError = '$e';
      });
    }
  }

  void _startPolling(String token) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce(token));
    // Fire the first one immediately so user sees status flip ASAP.
    _pollOnce(token);
  }

  Future<void> _pollOnce(String token) async {
    final id = _jobId;
    if (id == null) return;
    try {
      final snap = await _api.get(id, token: token);
      if (!mounted) return;
      setState(() => _snapshot = snap);
      // Stop polling once the AI value is ready (under_review) or the job is
      // terminal (completed/failed). Final completion happens later via the
      // estimate group — the user re-opens the ariza to see it.
      if (snap.status.hasResult || snap.status.isTerminal) {
        _pollTimer?.cancel();
        HapticFeedback.mediumImpact();
      }
    } catch (_) {
      // Transient polling errors are fine — keep trying.
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return PopScope(
      // Block accidental back navigation while a job is in flight — the
      // user can re-find it via the (future) AI history list. Once the result
      // is ready (under_review) or the job is terminal, allow back.
      canPop: _snapshot == null ||
          _snapshot!.status.hasResult ||
          _snapshot!.status.isTerminal,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final maxContent = c.maxWidth.clamp(0.0, 640.0);
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContent),
                  child: _body(context, isDark),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool isDark) {
    final l = Localizations.localeOf(context);
    if (_submitting) {
      return _scaffoldFrame(
        isDark: isDark,
        title: _AiStatusStrings.appBarTitle(l),
        subtitle: _AiStatusStrings.submittingSubtitle(l),
        child: _SpinnerBlock(label: _AiStatusStrings.submitting(l)),
      );
    }
    if (_submitError != null) {
      return _scaffoldFrame(
        isDark: isDark,
        title: _AiStatusStrings.appBarTitle(l),
        subtitle: _AiStatusStrings.notSubmitted(l),
        child: _ErrorBlock(message: _submitError!, onRetry: _retry),
      );
    }
    final snap = _snapshot;
    if (snap == null) {
      return _scaffoldFrame(
        isDark: isDark,
        title: _AiStatusStrings.appBarTitle(l),
        subtitle: _AiStatusStrings.fetchingStatus(l),
        child: _SpinnerBlock(label: _AiStatusStrings.fetchingStatus(l)),
      );
    }
    if (snap.status == AiJobStatus.failed) {
      return _scaffoldFrame(
        isDark: isDark,
        title: _AiStatusStrings.appBarTitle(l),
        subtitle: _AiStatusStrings.errorSubtitle(l),
        child: _ErrorBlock(
          message: snap.errorMessage ?? _AiStatusStrings.unknownError(l),
          onRetry: _retry,
        ),
      );
    }
    // Result is viewable as soon as the AI value lands (under_review) — not
    // only after the estimate group finalizes the report (completed).
    if (snap.status.hasResult) {
      return _ResultView(
        snapshot: snap,
        isDark: isDark,
        // Reopened from the "Jarayonda" card → back pops one route to Arizalar.
        // Wizard entry → back unwinds the whole wizard stack to the root.
        isExistingView: widget.existingJobId != null,
      );
    }
    return _scaffoldFrame(
      isDark: isDark,
      title: _AiStatusStrings.appBarTitle(l),
      subtitle: _AiStatusStrings.calculating(l),
      child: _ProgressView(snapshot: snap, isDark: isDark),
    );
  }

  Widget _scaffoldFrame({
    required bool isDark,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    // No step bar here — this is the processing/result screen, not an input
    // step. The wizard progress bar lives on the input steps (Cadastre…Review).
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: ServiceAppBar(title: title, subtitle: subtitle),
        ),
        const SizedBox(height: 8),
        Expanded(child: child),
      ],
    );
  }
}

// ── In-flight progress ────────────────────────────────────────────────

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.snapshot, required this.isDark});

  final AiJobSnapshot snapshot;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      children: [
        _StepRow(
          label: _AiStatusStrings.stepReceived(l),
          done: true,
          active: false,
          isDark: isDark,
        ),
        _StepRow(
          label: _AiStatusStrings.stepGathering(l),
          done:
              snapshot.status == AiJobStatus.aiPricing ||
              snapshot.status == AiJobStatus.completed,
          active: snapshot.status == AiJobStatus.gatheringInfo,
          isDark: isDark,
          details:
              snapshot.status == AiJobStatus.gatheringInfo ||
                  snapshot.nearbyListingsCount > 0 ||
                  snapshot.nearbyPoisCount > 0
              ? _AiStatusStrings.gatheringDetails(
                  l,
                  snapshot.nearbyListingsCount,
                  snapshot.nearbyPoisCount,
                )
              : null,
        ),
        _StepRow(
          label: _AiStatusStrings.stepPricing(l),
          done: snapshot.status == AiJobStatus.completed,
          active: snapshot.status == AiJobStatus.aiPricing,
          isDark: isDark,
        ),
        const SizedBox(height: 36),
        Center(
          child: Text(
            _AiStatusStrings.durationHint(l),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              height: 1.4,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.6)
                  : const Color(0xFF8A9097),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.active,
    required this.isDark,
    this.details,
  });

  final String label;
  final bool done;
  final bool active;
  final bool isDark;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: done
                ? const Icon(
                    Icons.check_circle,
                    color: AppColors.splashGreen,
                    size: 24,
                  )
                : active
                ? const CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.splashGreen,
                  )
                : Icon(
                    Icons.radio_button_unchecked,
                    color: sub.withValues(alpha: 0.5),
                    size: 24,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: active || done ? text : sub,
                  ),
                ),
                if (details != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    details!,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 12,
                      color: sub,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinnerBlock extends StatelessWidget {
  const _SpinnerBlock({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.splashGreen),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(fontFamily: 'MTSText', fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 56, color: Color(0xFFE0492A)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ListingCtaButton(
              label: L.retry(Localizations.localeOf(context)),
              enabled: true,
              onTap: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Completed result ──────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.snapshot,
    required this.isDark,
    this.isExistingView = false,
  });

  final AiJobSnapshot snapshot;
  final bool isDark;

  /// True when reopened from the "Jarayonda" card (single pushed route) — back
  /// pops once instead of unwinding to the navigator root.
  final bool isExistingView;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final result = snapshot.resultPayload ?? const {};
    final estimated = _asDouble(result['estimated_value']);
    final low = _asDouble(result['range_low']);
    final high = _asDouble(result['range_high']);
    final confidence = _asDouble(result['confidence']) ?? 0.0;
    final pois = (result['pois'] as Map?)?.cast<String, dynamic>() ?? const {};

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : AppColors.textBlack,
                      ),
                      onPressed: () => isExistingView
                          ? Navigator.of(context).pop()
                          : Navigator.of(context).popUntil((r) => r.isFirst),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _AiStatusStrings.resultTitle(l),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : AppColors.textBlack,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _PriceCard(
                estimated: estimated,
                low: low,
                high: high,
                confidence: confidence,
                isDark: isDark,
                locale: l,
                suppressed: result['needs_call_center'] == true,
              ),
              // Backend decided the market data cannot support a value (no
              // comparable ads at all, or nothing priced). Showing a figure we
              // have just said we cannot stand behind is worse than saying so,
              // so the number is suppressed and the user gets a person.
              if (result['needs_call_center'] == true) ...[
                const SizedBox(height: 14),
                _CallCenterCard(
                  reason: result['call_center_reason'] as String?,
                  isDark: isDark,
                  locale: l,
                ),
              ],
              // AI narrative summary (plain Uzbek), if the LLM produced one.
              // The LLM narrative explains how the value was reached, so it has
              // nothing honest to say about a value we are not showing.
              if (result['needs_call_center'] != true &&
                  ((result['summary'] as String?)?.trim().isNotEmpty ??
                      false)) ...[
                const SizedBox(height: 14),
                _SummaryCard(
                  text: (result['summary'] as String).trim(),
                  isDark: isDark,
                ),
              ],
              // 3-approach breakdown (cost / income / comparison + weights).
              // Hidden when the value is suppressed: the approaches card prints
              // the very figure we just replaced with «—», so leaving it would
              // hand back the number two cards further down.
              if (result['needs_call_center'] != true &&
                  result['approaches'] is Map) ...[
                const SizedBox(height: 18),
                _SectionTitle(
                  _AiStatusStrings.approachesTitle(l),
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _ApproachesCard(
                  approaches: (result['approaches'] as Map)
                      .cast<String, dynamic>(),
                  isDark: isDark,
                ),
              ],
              // Comparables actually used (the market approach evidence).
              // Also hidden when suppressed — the reason we suppressed IS that
              // there is no usable comparable evidence.
              if (result['needs_call_center'] != true &&
                  ((result['comparables_preview'] as List?)?.isNotEmpty ??
                      false)) ...[
                const SizedBox(height: 18),
                _SectionTitle(
                  _AiStatusStrings.comparablesTitle(l),
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _ComparablesCard(
                  comparables: (result['comparables_preview'] as List)
                      .whereType<Map>()
                      .map((e) => e.cast<String, dynamic>())
                      .toList(),
                  isDark: isDark,
                ),
              ],
              if (pois.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SectionTitle(_AiStatusStrings.poisTitle(l), isDark: isDark),
                const SizedBox(height: 3),
                Text(
                  _AiStatusStrings.poisSubtitle(l),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : const Color(0xFF8A9097),
                  ),
                ),
                const SizedBox(height: 8),
                _PoiSummary(pois: pois, isDark: isDark, locale: l),
              ],
            ],
          ),
        ),
        // Paywall — the demo ends here. Consent checkbox + the paid CTA
        // ("Pullik xizmatdan foydalanish") → appraiser docs → to'lov (Payme).
        // Reviewer (demo) akkaunti uchun yashiriladi — AI dastlabki natijasi
        // bepul ko'rinadi, lekin pullik rasmiy ariza topshirish ko'rsatilmaydi.
        //
        // Ham yashiriladi `needs_call_center` bo'lганda: biz endigina «bu
        // obyektni baholab bo'lmadi, aloqa markaziga qo'ng'iroq qiling» deб
        // turib, o'sha ekranda pullik baholash uchun to'lov taklif qilish —
        // qarama-qarshi. Foydalanuvchida bitta aniq yo'l qolishi kerak.
        if (!paymentsHidden && result['needs_call_center'] != true)
          _PaidSubmitBar(referenceId: snapshot.id),
      ],
    );
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// Paywall bar shown at the end of the free demo: the consent checkbox
// ("Yolg'on ma'lumot yuklamayman") gates the paid submission button. Stateful
// so the tick lives here without turning _ResultView stateful.
class _PaidSubmitBar extends StatelessWidget {
  const _PaidSubmitBar({required this.referenceId});

  final int? referenceId;

  // Tapping the paid CTA opens the terms as a scroll-through consent drawer.
  // The user must read to the end and tap "QABUL QILAMAN" before the paid
  // (appraiser docs → payment) flow opens.
  Future<void> _onTap(BuildContext context) async {
    final accepted = await showTermsAcceptanceSheet(context);
    if (!accepted || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiCredentialsScreen(referenceId: referenceId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ListingCtaButton(
        label: _AiStatusStrings.usePaidService(l),
        enabled: true,
        onTap: () => _onTap(context),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.estimated,
    required this.low,
    required this.high,
    required this.confidence,
    required this.isDark,
    required this.locale,
    this.suppressed = false,
  });

  final double? estimated;
  final double? low;
  final double? high;
  final double confidence;
  final bool isDark;
  final Locale locale;

  /// Backend `needs_call_center` — bozor ma'lumoti bahoni qo'llab-quvvatlay
  /// olmaydi. Shunday paytda raqam ko'rsatilmaydi: o'zimiz "ishonib bo'lmaydi"
  /// deb turib, baribir aniq son chiqarish — foydalanuvchini chalg'itish.
  final bool suppressed;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _AiStatusStrings.estimatedValue(locale),
            style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: sub),
          ),
          const SizedBox(height: 6),
          Text(
            (suppressed || estimated == null)
                ? '—'
                : _formatUzs(estimated!, locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w900,
              fontSize: 28,
              color: suppressed ? sub : text,
            ),
          ),
          if (!suppressed) ...[
            const SizedBox(height: 4),
            Text(
              _AiStatusStrings.soum(locale),
              style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: sub),
            ),
          ],
          if (!suppressed && low != null && high != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.straighten, size: 16, color: AppColors.splashGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_formatUzs(low!, locale)} — ${_formatUzs(high!, locale)}',
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      color: sub,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _ConfidenceBar(value: confidence, isDark: isDark, locale: locale),
        ],
      ),
    );
  }

  static String _formatUzs(double v, Locale l) {
    if (v >= 1e9) {
      return '${(v / 1e9).toStringAsFixed(2)} ${_AiStatusStrings.unitBln(l)}';
    }
    if (v >= 1e6) {
      return '${(v / 1e6).toStringAsFixed(1)} ${_AiStatusStrings.unitMln(l)}';
    }
    if (v >= 1e3) {
      return '${(v / 1e3).toStringAsFixed(0)} ${_AiStatusStrings.unitK(l)}';
    }
    return v.toStringAsFixed(0);
  }
}

/// Bozor ma'lumoti baho uchun yetarli bo'lmaganda ko'rsatiladigan karta:
/// sababi + aloqa markaziga qo'ng'iroq tugmasi.
///
/// Backend `needs_call_center` bayrog'ini o'zi qo'yadi — bu yerda hech qanday
/// chegara qayta hisoblanmaydi, aks holda ikki joyda ikki xil qoida bo'lib
/// qolardi. Bayroq shu hafta 41 ta arizadan 3 tasida yoqilgan (hammasi bitta
/// obyekt — Buxorodagi 38.3 m² xonadon, unga o'xshash e'lon umuman topilmagan).
class _CallCenterCard extends StatefulWidget {
  const _CallCenterCard({
    required this.reason,
    required this.isDark,
    required this.locale,
  });

  final String? reason;
  final bool isDark;
  final Locale locale;

  @override
  State<_CallCenterCard> createState() => _CallCenterCardState();
}

class _CallCenterCardState extends State<_CallCenterCard> {
  String? _number;

  @override
  void initState() {
    super.initState();
    SupportService()
        .fetchInfo()
        .then((info) {
          if (mounted) setState(() => _number = info.callNumber);
        })
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.isDark
        ? const Color(0xFF332B1A)
        : const Color(0xFFFFF6E0);
    final fg = widget.isDark
        ? const Color(0xFFFFD68A)
        : const Color(0xFF8A6F1A);
    final number = _number;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _AiStatusStrings.callCenterNote(widget.locale, widget.reason),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12.5,
                    height: 1.35,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (number != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('tel:$number')),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.splashGreen,
                borderRadius: BorderRadius.circular(100),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_AiStatusStrings.callCenter(widget.locale)} · $number',
                    style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF00320C),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.call, size: 16, color: Color(0xFF00320C)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Ishonchlilik darajalari chegarasi (foizda). Backend modeli o'zgarsa
/// (masalan ҳолат тузатиши тузалиб, тарқоқлик пасайса) shu ikki son qayta
/// sozlanadi — boshqa joyda takrorlanmaydi.
const int _confHighFrom = 65;
const int _confMediumFrom = 40;

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({
    required this.value,
    required this.isDark,
    required this.locale,
  });
  final double value;
  final bool isDark;
  final Locale locale;
  @override
  Widget build(BuildContext context) {
    final track = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final pct = (value.clamp(0.0, 1.0) * 100).round();
    // Bands are cut against how the backend's confidence model actually
    // scores. Measured over 106 real jobs it runs min 0.15, median 0.38,
    // max 0.74 — so the previous «>=70 Yuqori» was unreachable (1 job in 106)
    // and «<45 Past» labelled the median valuation as low. An ordinary job
    // now reads «O'rtacha», which is what it is.
    final label = pct >= _confHighFrom
        ? _AiStatusStrings.confHigh(locale)
        : (pct >= _confMediumFrom
              ? _AiStatusStrings.confMedium(locale)
              : _AiStatusStrings.confLow(locale));
    // The bar used to be brand green at every value, so «44% · Past» rendered
    // in the same success colour as a strong result — and colour beats text at
    // a glance. It now follows the band.
    final levelColor = pct >= _confHighFrom
        ? AppColors.splashGreen
        : (pct >= _confMediumFrom
              ? const Color(0xFFEF9F27)
              : const Color(0xFFE24B4A));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _AiStatusStrings.confidenceLabel(locale),
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 12,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.6)
                    : const Color(0xFF8A9097),
              ),
            ),
            Text(
              '$pct% · $label',
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: levelColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: track,
            valueColor: AlwaysStoppedAnimation(levelColor),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.isDark});
  final String text;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: isDark ? Colors.white : AppColors.textBlack,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.text, required this.isDark});
  final String text;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final color = isDark ? Colors.white : AppColors.textBlack;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome,
            size: 18,
            color: AppColors.splashGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 13.5,
                height: 1.4,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApproachesCard extends StatelessWidget {
  const _ApproachesCard({required this.approaches, required this.isDark});
  final Map<String, dynamic> approaches;
  final bool isDark;

  String _label(String key, Locale l) {
    switch (key) {
      case 'cost':
        return _AiStatusStrings.approachCost(l);
      case 'income':
        return _AiStatusStrings.approachIncome(l);
      case 'comparison':
        return _AiStatusStrings.approachComparison(l);
      default:
        return key;
    }
  }

  double? _d(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  String _fmt(double? v, Locale l) {
    if (v == null) return '—';
    if (v >= 1e9) {
      return '${(v / 1e9).toStringAsFixed(2)} ${_AiStatusStrings.unitBln(l)}';
    }
    if (v >= 1e6) {
      return '${(v / 1e6).toStringAsFixed(1)} ${_AiStatusStrings.unitMln(l)}';
    }
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final weights =
        (approaches['weights'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cost = (approaches['cost_approach'] as Map?)?.cast<String, dynamic>();
    final income = (approaches['income_approach'] as Map?)
        ?.cast<String, dynamic>();
    final comparison = _d(approaches['comparison_value']);

    final values = <String, double?>{
      'cost': cost == null ? null : _d(cost['value']),
      'income': income == null ? null : _d(income['value']),
      'comparison': comparison,
    };

    Widget row(String key) {
      final w = _d(weights[key]);
      if (w == null || w <= 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                _label(key, locale),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 13,
                  color: text,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _fmt(values[key], locale),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: text,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.splashGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(w * 100).round()}%',
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.splashGreen,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Cost approach comes only from an owner-supplied смета. When none was entered
    // it isn't computed (weight 0) — show it explicitly, greyed, instead of
    // silently omitting the row, so the user knows WHY there's no cost figure.
    Widget costNotApplied() {
      final w = _d(weights['cost']);
      if (cost != null && w != null && w > 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                _AiStatusStrings.approachCost(locale),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 13,
                  color: sub,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _AiStatusStrings.costNotApplied(locale),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: sub,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _AiStatusStrings.approachHeader(locale),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontSize: 11,
                    color: sub,
                  ),
                ),
              ),
              Text(
                _AiStatusStrings.valueWeightHeader(locale),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 11,
                  color: sub,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          row('comparison'),
          row('income'),
          row('cost'),
          costNotApplied(),
        ],
      ),
    );
  }
}

class _ComparablesCard extends StatelessWidget {
  const _ComparablesCard({required this.comparables, required this.isDark});
  final List<Map<String, dynamic>> comparables;
  final bool isDark;

  double? _d(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  String _money(double? v, Locale l) {
    if (v == null || v <= 0) return '—';
    if (v >= 1e9) {
      return '${(v / 1e9).toStringAsFixed(2)} ${_AiStatusStrings.unitBln(l)}';
    }
    if (v >= 1e6) {
      return '${(v / 1e6).toStringAsFixed(0)} ${_AiStatusStrings.unitMln(l)}';
    }
    if (v >= 1e3) {
      return '${(v / 1e3).toStringAsFixed(0)} ${_AiStatusStrings.unitK(l)}';
    }
    return v.toStringAsFixed(0);
  }

  // Show only the top few comparables; the rest collapse into a footer count.
  static const int _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final visibleCount = comparables.length > _maxVisible
        ? _maxVisible
        : comparables.length;
    final extra = comparables.length - visibleCount;

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < visibleCount; i++)
            _row(
              comparables[i],
              i != visibleCount - 1 || extra > 0,
              text,
              sub,
              border,
              locale,
            ),
          if (extra > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Text(
                _AiStatusStrings.moreListings(locale, extra),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: sub,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    Map<String, dynamic> c,
    bool divider,
    Color text,
    Color sub,
    Color border,
    Locale locale,
  ) {
    final price = _d(c['price_uzs']);
    final area = _d(c['area_sqm']);
    final psm = _d(c['price_per_sqm']);
    final dist = _d(c['distance_km']);
    final addr = (c['address'] as String?)?.trim();
    final url = (c['url'] as String?)?.trim();

    final meta = <String>[
      if (area != null) '${area.toStringAsFixed(area % 1 == 0 ? 0 : 1)} m²',
      if (psm != null) '${_money(psm, locale)}/m²',
      if (dist != null) '${dist.toStringAsFixed(dist < 1 ? 2 : 1)} km',
    ].join('  ·  ');

    return InkWell(
      onTap: (url != null && url.isNotEmpty)
          ? () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: divider ? Border(bottom: BorderSide(color: border)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _money(price, locale),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 12,
                      color: sub,
                    ),
                  ),
                  if (addr != null && addr.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      addr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 11.5,
                        color: sub,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (url != null && url.isNotEmpty)
              Icon(Icons.open_in_new, size: 16, color: sub),
          ],
        ),
      ),
    );
  }
}

class _PoiSummary extends StatefulWidget {
  const _PoiSummary({
    required this.pois,
    required this.isDark,
    required this.locale,
  });
  final Map<String, dynamic> pois;
  final bool isDark;
  final Locale locale;
  @override
  State<_PoiSummary> createState() => _PoiSummaryState();
}

class _PoiSummaryState extends State<_PoiSummary> {
  // Named places listed per category before a "+N ta" tail.
  static const int _maxPlaces = 8;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final dividerColor = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);

    final rows = widget.pois.entries
        .where((e) => e.value is List && (e.value as List).isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _category(rows[i], i != rows.length - 1, text, sub, dividerColor),
        ],
      ),
    );
  }

  Widget _category(
    MapEntry<String, dynamic> r,
    bool divider,
    Color text,
    Color sub,
    Color dividerColor,
  ) {
    final kind = r.key;
    final list = r.value as List;
    return Column(
      children: [
        // Collapse control hidden for now — categories stay expanded, and the
        // label carries a trailing colon (e.g. "Bog'lar:", "Maktablar:").
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Icon(_iconFor(kind), color: AppColors.splashGreen, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_labelFor(kind)}:',
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    color: text,
                  ),
                ),
              ),
            ],
          ),
        ),
        _places(list, sub, text),
        if (divider) Divider(height: 1, thickness: 1, color: dividerColor),
      ],
    );
  }

  Widget _places(List raw, Color sub, Color text) {
    final places =
        raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
          ..sort((a, b) => _distOf(a).compareTo(_distOf(b)));
    final shown = places.take(_maxPlaces).toList();
    final extra = places.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(left: 28, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _nameOf(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12.5,
                        color: text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _distLabel(p),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontSize: 12,
                      color: sub,
                    ),
                  ),
                ],
              ),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _AiStatusStrings.morePlaces(widget.locale, extra),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 11.5,
                  color: sub,
                ),
              ),
            ),
        ],
      ),
    );
  }

  num _distOf(Map<String, dynamic> p) {
    final d = p['distance_m'];
    return d is num ? d : (1 << 30);
  }

  String _nameOf(Map<String, dynamic> p) {
    final n = (p['name'] as String?)?.trim();
    return (n != null && n.isNotEmpty)
        ? n
        : _AiStatusStrings.unnamed(widget.locale);
  }

  String _distLabel(Map<String, dynamic> p) {
    final d = p['distance_m'];
    if (d is! num) return '';
    if (d < 1000) return '${d.round()} m';
    return '${(d / 1000).toStringAsFixed(d < 10000 ? 1 : 0)} km';
  }

  String _labelFor(String kind) {
    final l = widget.locale;
    switch (kind) {
      case 'school':
        return _AiStatusStrings.poiSchools(l);
      case 'kindergarten':
        return _AiStatusStrings.poiKindergartens(l);
      case 'metro':
        return _AiStatusStrings.poiMetro(l);
      case 'park':
        return _AiStatusStrings.poiParks(l);
      case 'hospital':
        return _AiStatusStrings.poiHospitals(l);
      case 'clinic':
        return _AiStatusStrings.poiClinics(l);
      case 'supermarket':
        return _AiStatusStrings.poiSupermarkets(l);
      case 'bus_stop':
        return _AiStatusStrings.poiBusStops(l);
      default:
        return kind;
    }
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'school':
      case 'kindergarten':
        return Icons.school_outlined;
      case 'metro':
        return Icons.train;
      case 'park':
        return Icons.park_outlined;
      case 'hospital':
      case 'clinic':
        return Icons.local_hospital_outlined;
      case 'supermarket':
        return Icons.shopping_cart_outlined;
      case 'bus_stop':
        return Icons.directions_bus_outlined;
      default:
        return Icons.place_outlined;
    }
  }
}

class _AiStatusStrings {
  const _AiStatusStrings._();

  static String appBarTitle(Locale l) =>
      tr(l, 'services.scan.status.app_bar_title');

  static String submittingSubtitle(Locale l) =>
      tr(l, 'services.scan.status.submitting_subtitle');

  static String submitting(Locale l) =>
      tr(l, 'services.scan.status.submitting');

  static String notSubmitted(Locale l) =>
      tr(l, 'services.scan.status.not_submitted');

  static String fetchingStatus(Locale l) =>
      tr(l, 'services.scan.status.fetching_status');

  static String errorSubtitle(Locale l) =>
      tr(l, 'services.scan.status.error_subtitle');

  static String unknownError(Locale l) =>
      tr(l, 'services.scan.status.unknown_error');

  static String calculating(Locale l) =>
      tr(l, 'services.scan.status.calculating');

  static String errLogin(Locale l) =>
      tr(l, 'services.scan.status.err_login');

  static String invalidData(Locale l) =>
      tr(l, 'services.scan.status.invalid_data');

  static String stepReceived(Locale l) =>
      tr(l, 'services.scan.status.step_received');

  static String stepGathering(Locale l) =>
      tr(l, 'services.scan.status.step_gathering');

  static String gatheringDetails(Locale l, int listings, int pois) =>
      tr(l, 'services.scan.status.gathering_details')
          .replaceAll(r'$listings', '$listings')
          .replaceAll(r'$pois', '$pois');

  static String stepPricing(Locale l) =>
      tr(l, 'services.scan.status.step_pricing');

  static String durationHint(Locale l) =>
      tr(l, 'services.scan.status.duration_hint');

  static String resultTitle(Locale l) =>
      tr(l, 'services.scan.status.result_title');

  static String estimatedValue(Locale l) =>
      tr(l, 'services.scan.status.estimated_value');

  static String soum(Locale l) => tr(l, 'services.scan.status.soum');

  static String confidenceLabel(Locale l) =>
      tr(l, 'services.scan.status.confidence_label');

  static String confHigh(Locale l) =>
      tr(l, 'services.scan.status.conf_high');

  static String confMedium(Locale l) =>
      tr(l, 'services.scan.status.conf_medium');

  static String confLow(Locale l) => tr(l, 'services.scan.status.conf_low');

  static String callCenter(Locale l) =>
      tr(l, 'services.scan.status.call_center');

  /// Nega baho bo'lmagani — sabab bo'yicha turli matn. Noma'lum sabab
  /// umumiy matnga tushadi, hech qachon bo'sh qolmaydi.
  static String callCenterNote(Locale l, String? reason) => tr(
    l,
    reason == 'no_comparables'
        ? 'services.scan.status.cc_no_comparables'
        : (reason == 'low_confidence'
              ? 'services.scan.status.cc_low_confidence'
              : 'services.scan.status.cc_generic'),
  );

  static String approachesTitle(Locale l) =>
      tr(l, 'services.scan.status.approaches_title');

  static String approachCost(Locale l) =>
      tr(l, 'services.scan.status.approach_cost');

  static String costNotApplied(Locale l) =>
      tr(l, 'services.scan.status.cost_not_applied');

  static String approachIncome(Locale l) =>
      tr(l, 'services.scan.status.approach_income');

  static String approachComparison(Locale l) =>
      tr(l, 'services.scan.status.approach_comparison');

  static String comparablesTitle(Locale l) =>
      tr(l, 'services.scan.status.comparables_title');

  static String moreListings(Locale l, int n) =>
      tr(l, 'services.scan.status.more_listings').replaceAll(r'$n', '$n');

  static String poisTitle(Locale l) =>
      tr(l, 'services.scan.status.pois_title');

  static String poisSubtitle(Locale l) =>
      tr(l, 'services.scan.status.pois_subtitle');

  static String morePlaces(Locale l, int n) =>
      tr(l, 'services.scan.status.more_places').replaceAll(r'$n', '$n');

  static String unnamed(Locale l) => tr(l, 'services.scan.status.unnamed');

  static String usePaidService(Locale l) => tr(l, 'ai.credentials.use_service');

  static String unitBln(Locale l) => tr(l, 'services.scan.status.unit_bln');

  static String unitMln(Locale l) => tr(l, 'services.scan.status.unit_mln');

  static String unitK(Locale l) => tr(l, 'services.scan.status.unit_k');

  static String poiSchools(Locale l) =>
      tr(l, 'services.scan.status.poi_schools');

  static String poiKindergartens(Locale l) =>
      tr(l, 'services.scan.status.poi_kindergartens');

  static String poiMetro(Locale l) => tr(l, 'services.scan.status.poi_metro');

  static String poiParks(Locale l) => tr(l, 'services.scan.status.poi_parks');

  static String poiHospitals(Locale l) =>
      tr(l, 'services.scan.status.poi_hospitals');

  static String poiClinics(Locale l) =>
      tr(l, 'services.scan.status.poi_clinics');

  static String poiSupermarkets(Locale l) =>
      tr(l, 'services.scan.status.poi_supermarkets');

  static String poiBusStops(Locale l) =>
      tr(l, 'services.scan.status.poi_bus_stops');

  static String approachHeader(Locale l) =>
      tr(l, 'services.scan.status.approach_header');

  static String valueWeightHeader(Locale l) =>
      tr(l, 'services.scan.status.value_weight_header');
}
