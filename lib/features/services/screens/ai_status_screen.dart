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
import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../payments/ai_payment_sheet.dart';
import '../api_ai_valuation_job_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';

class AiStatusScreen extends StatefulWidget {
  const AiStatusScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

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
    _submit();
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
      final draftId = widget.bundle.draftId;
      final id = draftId != null
          ? await _api.submitDraft(
              draftId: draftId,
              bundleJson: widget.bundle.toJson(),
              token: token,
            )
          : await _api.create(
              bundleJson: widget.bundle.toJson(),
              token: token,
            );
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
      if (snap.status.isTerminal) {
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
      // user can re-find it via the (future) AI history list.
      canPop: _snapshot?.status.isTerminal != false,
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
        child: _ErrorBlock(message: _submitError!, onRetry: _submit),
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
          onRetry: _submit,
        ),
      );
    }
    if (snap.status == AiJobStatus.completed) {
      return _ResultView(snapshot: snap, isDark: isDark);
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
  const _ResultView({required this.snapshot, required this.isDark});

  final AiJobSnapshot snapshot;
  final bool isDark;

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
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
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
              ),
              // AI narrative summary (plain Uzbek), if the LLM produced one.
              if ((result['summary'] as String?)?.trim().isNotEmpty ??
                  false) ...[
                const SizedBox(height: 14),
                _SummaryCard(
                  text: (result['summary'] as String).trim(),
                  isDark: isDark,
                ),
              ],
              // 3-approach breakdown (cost / income / comparison + weights).
              if (result['approaches'] is Map) ...[
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
              if ((result['comparables_preview'] as List?)?.isNotEmpty ??
                  false) ...[
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
        // Fixed bottom CTA — "Ariza yuborish" → to'lov bottom-sheet'i (Payme).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ListingCtaButton(
            label: _AiStatusStrings.submitApplication(l),
            enabled: true,
            onTap: () => showAiPaymentSheet(context, referenceId: snapshot.id),
          ),
        ),
      ],
    );
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
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
  });

  final double? estimated;
  final double? low;
  final double? high;
  final double confidence;
  final bool isDark;
  final Locale locale;

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
            estimated == null ? '—' : _formatUzs(estimated!, locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w900,
              fontSize: 28,
              color: text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _AiStatusStrings.soum(locale),
            style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: sub),
          ),
          if (low != null && high != null) ...[
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
    final label = pct >= 70
        ? _AiStatusStrings.confHigh(locale)
        : (pct >= 45
              ? _AiStatusStrings.confMedium(locale)
              : _AiStatusStrings.confLow(locale));
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
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.splashGreen,
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
            valueColor: const AlwaysStoppedAnimation(AppColors.splashGreen),
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
                  switch (locale.languageCode) {
                    'ru' => 'Подход',
                    'en' => 'Approach',
                    _ => 'Yondashuv',
                  },
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontSize: 11,
                    color: sub,
                  ),
                ),
              ),
              Text(
                switch (locale.languageCode) {
                  'ru' => 'Значение · Вес',
                  'en' => 'Value · Weight',
                  _ => 'Qiymat · Og\'irlik',
                },
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
  // Categories the user has expanded to reveal the named places.
  final Set<String> _open = {};
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
    final isOpen = _open.contains(kind);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() {
            isOpen ? _open.remove(kind) : _open.add(kind);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Icon(_iconFor(kind), color: AppColors.splashGreen, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _labelFor(kind),
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      color: text,
                    ),
                  ),
                ),
                Text(
                  _countLabel(kind, list.length),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: sub,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isOpen ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: sub,
                ),
              ],
            ),
          ),
        ),
        if (isOpen) _places(list, sub, text),
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

  // Common, high-density amenities (bus stops) are capped at "10+" — the exact
  // count (e.g. 1230) is noise. Price-affecting / rarer ones show the real n.
  String _countLabel(String kind, int n) {
    const capped = {'bus_stop'};
    final l = widget.locale;
    if (capped.contains(kind) && n > 10) {
      return '10+ ${_AiStatusStrings.unitPcs(l)}';
    }
    return '$n ${_AiStatusStrings.unitPcs(l)}';
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

  static String appBarTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'AI оценка',
    'en' => 'AI valuation',
    _ => 'AI Baholash',
  };

  static String submittingSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Запрос отправляется...',
    'en' => 'Submitting the request...',
    _ => 'So\'rov yuborilmoqda...',
  };

  static String submitting(Locale l) => switch (l.languageCode) {
    'ru' => 'Отправка...',
    'en' => 'Submitting...',
    _ => 'Yuborilmoqda...',
  };

  static String notSubmitted(Locale l) => switch (l.languageCode) {
    'ru' => 'Не отправлено',
    'en' => 'Not submitted',
    _ => 'Yuborilmadi',
  };

  static String fetchingStatus(Locale l) => switch (l.languageCode) {
    'ru' => 'Получение статуса...',
    'en' => 'Fetching status...',
    _ => 'Holat olinmoqda...',
  };

  static String errorSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Ошибка',
    'en' => 'Error',
    _ => 'Xatolik',
  };

  static String unknownError(Locale l) => switch (l.languageCode) {
    'ru' => 'Неизвестная ошибка',
    'en' => 'Unknown error',
    _ => 'Noma\'lum xatolik',
  };

  static String calculating(Locale l) => switch (l.languageCode) {
    'ru' => 'Расчёт...',
    'en' => 'Calculating...',
    _ => 'Hisoblanmoqda...',
  };

  static String errLogin(Locale l) => switch (l.languageCode) {
    'ru' => 'Сначала войдите в систему',
    'en' => 'Please sign in first',
    _ => 'Avval tizimga kiring',
  };

  static String invalidData(Locale l) => switch (l.languageCode) {
    'ru' => 'Проверьте введённые данные и попробуйте снова',
    'en' => 'Please check the entered data and try again',
    _ => 'Kiritilgan ma\'lumotlarni tekshirib, qayta urinib ko\'ring',
  };

  static String stepReceived(Locale l) => switch (l.languageCode) {
    'ru' => 'Запрос принят',
    'en' => 'Request received',
    _ => 'So\'rov qabul qilindi',
  };

  static String stepGathering(Locale l) => switch (l.languageCode) {
    'ru' => 'Сбор данных',
    'en' => 'Collecting data',
    _ => 'Ma\'lumotlar yig\'ilmoqda',
  };

  static String gatheringDetails(Locale l, int listings, int pois) =>
      switch (l.languageCode) {
        'ru' => '$listings объявл. · $pois ближних объектов',
        'en' => '$listings listings · $pois nearby objects',
        _ => '$listings ta e\'lon · $pois ta yaqin obyekt',
      };

  static String stepPricing(Locale l) => switch (l.languageCode) {
    'ru' => 'AI рассчитывает цену',
    'en' => 'AI is calculating the price',
    _ => 'AI narx hisoblanmoqda',
  };

  static String durationHint(Locale l) => switch (l.languageCode) {
    'ru' =>
      'Это может занять от 30 секунд до 2 минут.\n'
          'Мы уведомим вас по завершении.',
    'en' =>
      'This may take 30 seconds to 2 minutes.\n'
          'We\'ll notify you when it\'s done.',
    _ =>
      'Bu jarayon 30 sekund - 2 daqiqa olishi mumkin.\n'
          'Tugagandan keyin xabar yuboramiz.',
  };

  static String resultTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Результат AI оценки',
    'en' => 'AI valuation result',
    _ => 'AI Baholash natijasi',
  };

  static String estimatedValue(Locale l) => switch (l.languageCode) {
    'ru' => 'Примерная стоимость',
    'en' => 'Estimated value',
    _ => 'Taxminiy qiymat',
  };

  static String soum(Locale l) => switch (l.languageCode) {
    'ru' => 'сум',
    'en' => 'soum',
    _ => 'so\'m',
  };

  static String confidenceLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Достоверность: ',
    'en' => 'Confidence: ',
    _ => 'Ishonchlilik: ',
  };

  static String confHigh(Locale l) => switch (l.languageCode) {
    'ru' => 'Высокая',
    'en' => 'High',
    _ => 'Yuqori',
  };

  static String confMedium(Locale l) => switch (l.languageCode) {
    'ru' => 'Средняя',
    'en' => 'Medium',
    _ => 'O\'rtacha',
  };

  static String confLow(Locale l) => switch (l.languageCode) {
    'ru' => 'Низкая',
    'en' => 'Low',
    _ => 'Past',
  };

  static String approachesTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Подходы к оценке',
    'en' => 'Valuation approaches',
    _ => 'Baholash yondashuvlari',
  };

  static String approachCost(Locale l) => switch (l.languageCode) {
    'ru' => 'Затраты (восстановление)',
    'en' => 'Cost (replacement)',
    _ => 'Xarajat (qayta tiklash)',
  };

  static String approachIncome(Locale l) => switch (l.languageCode) {
    'ru' => 'Доход (аренда)',
    'en' => 'Income (rent)',
    _ => 'Daromad (ijara)',
  };

  static String approachComparison(Locale l) => switch (l.languageCode) {
    'ru' => 'Сравнение (рынок)',
    'en' => 'Comparison (market)',
    _ => 'Qiyoslash (bozor)',
  };

  static String comparablesTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Сравниваемые объявления',
    'en' => 'Compared listings',
    _ => 'Solishtirilgan e\'lonlar',
  };

  static String moreListings(Locale l, int n) => switch (l.languageCode) {
    'ru' => 'Ещё $n объявлений',
    'en' => '$n more listings',
    _ => 'Yana $n ta e\'lon',
  };

  static String poisTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Объекты поблизости',
    'en' => 'Nearby objects',
    _ => 'Yaqin atrofdagi obyektlar',
  };

  static String poisSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Инфраструктура в радиусе 1–2 км',
    'en' => 'Infrastructure found within a 1–2 km radius',
    _ => '1–2 km radiusda topilgan infratuzilma',
  };

  static String morePlaces(Locale l, int n) => switch (l.languageCode) {
    'ru' => 'Ещё $n',
    'en' => '$n more',
    _ => 'Yana $n ta',
  };

  static String unnamed(Locale l) => switch (l.languageCode) {
    'ru' => 'Без названия',
    'en' => 'Unnamed',
    _ => 'Nomsiz',
  };

  static String home(Locale l) => switch (l.languageCode) {
    'ru' => 'Главная',
    'en' => 'Home',
    _ => 'Asosiy sahifa',
  };

  static String submitApplication(Locale l) => switch (l.languageCode) {
        'ru' => 'Подать заявку',
        'en' => 'Submit application',
        _ => 'Ariza yuborish',
      };

  static String unitBln(Locale l) => switch (l.languageCode) {
    'ru' => 'млрд',
    'en' => 'bln',
    _ => 'mlrd',
  };

  static String unitMln(Locale l) => switch (l.languageCode) {
    'ru' => 'млн',
    'en' => 'mln',
    _ => 'mln',
  };

  static String unitK(Locale l) => switch (l.languageCode) {
    'ru' => 'тыс',
    'en' => 'k',
    _ => 'ming',
  };

  static String unitPcs(Locale l) => switch (l.languageCode) {
    'ru' => 'шт',
    'en' => 'pcs',
    _ => 'ta',
  };

  static String poiSchools(Locale l) => switch (l.languageCode) {
    'ru' => 'Школы',
    'en' => 'Schools',
    _ => 'Maktablar',
  };

  static String poiKindergartens(Locale l) => switch (l.languageCode) {
    'ru' => 'Детские сады',
    'en' => 'Kindergartens',
    _ => 'Bog\'chalar',
  };

  static String poiMetro(Locale l) => switch (l.languageCode) {
    'ru' => 'Станции метро',
    'en' => 'Metro stations',
    _ => 'Metro bekatlari',
  };

  static String poiParks(Locale l) => switch (l.languageCode) {
    'ru' => 'Парки',
    'en' => 'Parks',
    _ => 'Bog\'lar',
  };

  static String poiHospitals(Locale l) => switch (l.languageCode) {
    'ru' => 'Больницы',
    'en' => 'Hospitals',
    _ => 'Shifoxonalar',
  };

  static String poiClinics(Locale l) => switch (l.languageCode) {
    'ru' => 'Поликлиники',
    'en' => 'Clinics',
    _ => 'Poliklinikalar',
  };

  static String poiSupermarkets(Locale l) => switch (l.languageCode) {
    'ru' => 'Супермаркеты',
    'en' => 'Supermarkets',
    _ => 'Supermarketlar',
  };

  static String poiBusStops(Locale l) => switch (l.languageCode) {
    'ru' => 'Автобусные остановки',
    'en' => 'Bus stops',
    _ => 'Avtobus bekatlari',
  };
}
