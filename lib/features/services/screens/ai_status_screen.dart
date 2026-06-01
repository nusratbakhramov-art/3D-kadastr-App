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

import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../api_ai_valuation_job_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';

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
        _submitError = 'Avval tizimga kiring';
      });
      return;
    }
    try {
      final id = await _api.create(
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
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      final handled =
          await NetworkErrorHandler.maybeShow(context, e, onRetry: _submit);
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
    if (_submitting) {
      return _scaffoldFrame(
        isDark: isDark,
        title: 'AI Baholash',
        subtitle: 'So\'rov yuborilmoqda...',
        progressIndex: 3,
        child: const _SpinnerBlock(label: 'Yuborilmoqda...'),
      );
    }
    if (_submitError != null) {
      return _scaffoldFrame(
        isDark: isDark,
        title: 'AI Baholash',
        subtitle: 'Yuborilmadi',
        progressIndex: 3,
        child: _ErrorBlock(message: _submitError!, onRetry: _submit),
      );
    }
    final snap = _snapshot;
    if (snap == null) {
      return _scaffoldFrame(
        isDark: isDark,
        title: 'AI Baholash',
        subtitle: 'Holat olinmoqda...',
        progressIndex: 3,
        child: const _SpinnerBlock(label: 'Holat olinmoqda...'),
      );
    }
    if (snap.status == AiJobStatus.failed) {
      return _scaffoldFrame(
        isDark: isDark,
        title: 'AI Baholash',
        subtitle: 'Xatolik',
        progressIndex: 3,
        child: _ErrorBlock(
          message: snap.errorMessage ?? 'Noma\'lum xatolik',
          onRetry: _submit,
        ),
      );
    }
    if (snap.status == AiJobStatus.completed) {
      return _ResultView(snapshot: snap, isDark: isDark);
    }
    return _scaffoldFrame(
      isDark: isDark,
      title: 'AI Baholash',
      subtitle: 'Hisoblanmoqda...',
      progressIndex: 3,
      child: _ProgressView(snapshot: snap, isDark: isDark),
    );
  }

  Widget _scaffoldFrame({
    required bool isDark,
    required String title,
    required String subtitle,
    required int progressIndex,
    required Widget child,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: ServiceAppBar(title: title, subtitle: subtitle),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: StepProgressBar(count: 4, activeIndex: progressIndex),
        ),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      children: [
        _StepRow(
          label: 'So\'rov qabul qilindi',
          done: true,
          active: false,
          isDark: isDark,
        ),
        _StepRow(
          label: 'Ma\'lumotlar yig\'ilmoqda',
          done: snapshot.status == AiJobStatus.aiPricing ||
              snapshot.status == AiJobStatus.completed,
          active: snapshot.status == AiJobStatus.gatheringInfo,
          isDark: isDark,
          details: snapshot.status == AiJobStatus.gatheringInfo ||
                  snapshot.nearbyListingsCount > 0 ||
                  snapshot.nearbyPoisCount > 0
              ? '${snapshot.nearbyListingsCount} ta e\'lon · '
                  '${snapshot.nearbyPoisCount} ta yaqin obyekt'
              : null,
        ),
        _StepRow(
          label: 'AI narx hisoblanmoqda',
          done: snapshot.status == AiJobStatus.completed,
          active: snapshot.status == AiJobStatus.aiPricing,
          isDark: isDark,
        ),
        const SizedBox(height: 36),
        Center(
          child: Text(
            'Bu jarayon 30 sekund - 2 daqiqa olishi mumkin.\n'
            'Tugagandan keyin xabar yuboramiz.',
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
                ? const Icon(Icons.check_circle,
                    color: AppColors.splashGreen, size: 24)
                : active
                    ? const CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.splashGreen,
                      )
                    : Icon(Icons.radio_button_unchecked,
                        color: sub.withValues(alpha: 0.5), size: 24),
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
            style: const TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
            ),
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
          const Icon(Icons.error_outline,
              size: 56, color: Color(0xFFE0492A)),
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
              label: 'Qayta urinish',
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
                  'AI Baholash natijasi',
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
        ),
              // AI narrative summary (plain Uzbek), if the LLM produced one.
              if ((result['summary'] as String?)?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 14),
                _SummaryCard(text: (result['summary'] as String).trim(), isDark: isDark),
              ],
              // 3-approach breakdown (cost / income / comparison + weights).
              if (result['approaches'] is Map) ...[
                const SizedBox(height: 18),
                _SectionTitle('Baholash yondashuvlari', isDark: isDark),
                const SizedBox(height: 8),
                _ApproachesCard(
                  approaches: (result['approaches'] as Map).cast<String, dynamic>(),
                  isDark: isDark,
                ),
              ],
              // Comparables actually used (the market approach evidence).
              if ((result['comparables_preview'] as List?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 18),
                _SectionTitle('Solishtirilgan e\'lonlar', isDark: isDark),
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
                _SectionTitle('Yaqin atrofdagi obyektlar', isDark: isDark),
                const SizedBox(height: 3),
                Text(
                  '1–2 km radiusda topilgan infratuzilma',
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : const Color(0xFF8A9097),
                  ),
                ),
                const SizedBox(height: 8),
                _PoiSummary(pois: pois, isDark: isDark),
              ],
            ],
          ),
        ),
        // Fixed bottom CTA — always reachable without scrolling.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ListingCtaButton(
            label: 'Asosiy sahifa',
            enabled: true,
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
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
  });

  final double? estimated;
  final double? low;
  final double? high;
  final double confidence;
  final bool isDark;

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
            'Taxminiy qiymat',
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: sub,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            estimated == null ? '—' : _formatUzs(estimated!),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w900,
              fontSize: 28,
              color: text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'so\'m',
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: sub,
            ),
          ),
          if (low != null && high != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.straighten,
                    size: 16,
                    color: AppColors.splashGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_formatUzs(low!)} — ${_formatUzs(high!)}',
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
          _ConfidenceBar(value: confidence, isDark: isDark),
        ],
      ),
    );
  }

  static String _formatUzs(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} mlrd';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)} mln';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)} ming';
    return v.toStringAsFixed(0);
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.value, required this.isDark});
  final double value;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    final track =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final pct = (value.clamp(0.0, 1.0) * 100).round();
    final label =
        pct >= 70 ? 'Yuqori' : (pct >= 45 ? 'O\'rtacha' : 'Past');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Ishonchlilik: ',
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
            valueColor:
                const AlwaysStoppedAnimation(AppColors.splashGreen),
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
          const Icon(Icons.auto_awesome, size: 18, color: AppColors.splashGreen),
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

  static const _labels = {
    'cost': 'Xarajat (qayta tiklash)',
    'income': 'Daromad (ijara)',
    'comparison': 'Qiyoslash (bozor)',
  };

  double? _d(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  String _fmt(double? v) {
    if (v == null) return '—';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} mlrd';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)} mln';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final weights = (approaches['weights'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cost = (approaches['cost_approach'] as Map?)?.cast<String, dynamic>();
    final income = (approaches['income_approach'] as Map?)?.cast<String, dynamic>();
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
              child: Text(_labels[key] ?? key,
                  style: TextStyle(
                      fontFamily: 'MTSCompact', fontSize: 13, color: text)),
            ),
            Expanded(
              flex: 3,
              child: Text(_fmt(values[key]),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: text)),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.splashGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${(w * 100).round()}%',
                  style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.splashGreen)),
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
                child: Text('Yondashuv',
                    style: TextStyle(
                        fontFamily: 'MTSCompact', fontSize: 11, color: sub)),
              ),
              Text('Qiymat · Og\'irlik',
                  style: TextStyle(
                      fontFamily: 'MTSCompact', fontSize: 11, color: sub)),
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

  String _money(double? v) {
    if (v == null || v <= 0) return '—';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} mlrd';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(0)} mln';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)} ming';
    return v.toStringAsFixed(0);
  }

  // Show only the top few comparables; the rest collapse into a footer count.
  static const int _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final visibleCount =
        comparables.length > _maxVisible ? _maxVisible : comparables.length;
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
            _row(comparables[i], i != visibleCount - 1 || extra > 0, text, sub,
                border),
          if (extra > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Text(
                'Yana $extra ta e\'lon',
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

  Widget _row(Map<String, dynamic> c, bool divider, Color text, Color sub,
      Color border) {
    final price = _d(c['price_uzs']);
    final area = _d(c['area_sqm']);
    final psm = _d(c['price_per_sqm']);
    final dist = _d(c['distance_km']);
    final addr = (c['address'] as String?)?.trim();
    final url = (c['url'] as String?)?.trim();

    final meta = <String>[
      if (area != null) '${area.toStringAsFixed(area % 1 == 0 ? 0 : 1)} m²',
      if (psm != null) '${_money(psm)}/m²',
      if (dist != null) '${dist.toStringAsFixed(dist < 1 ? 2 : 1)} km',
    ].join('  ·  ');

    return InkWell(
      onTap: (url != null && url.isNotEmpty)
          ? () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: border))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _money(price),
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

class _PoiSummary extends StatelessWidget {
  const _PoiSummary({required this.pois, required this.isDark});
  final Map<String, dynamic> pois;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final rows = pois.entries
        .where((e) => e.value is List && (e.value as List).isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(_iconFor(r.key),
                      color: AppColors.splashGreen, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _labelFor(r.key),
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13,
                        color: text,
                      ),
                    ),
                  ),
                  Text(
                    _countLabel(r.key, (r.value as List).length),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: sub,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Common, high-density amenities (bus stops) are capped at "10+" — the exact
  // count (e.g. 1230) is noise. Price-affecting / rarer ones show the real n.
  String _countLabel(String kind, int n) {
    const capped = {'bus_stop'};
    if (capped.contains(kind) && n > 10) return '10+ ta';
    return '$n ta';
  }

  String _labelFor(String kind) {
    switch (kind) {
      case 'school':
        return 'Maktablar';
      case 'kindergarten':
        return 'Bog\'chalar';
      case 'metro':
        return 'Metro bekatlari';
      case 'park':
        return 'Bog\'lar';
      case 'hospital':
        return 'Shifoxonalar';
      case 'clinic':
        return 'Poliklinikalar';
      case 'supermarket':
        return 'Supermarketlar';
      case 'bus_stop':
        return 'Avtobus bekatlari';
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
