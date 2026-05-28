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

import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
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
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(8),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.splashGreen,
            ),
          ),
        ),
        const SizedBox(height: 16),
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
    final comps = (result['comparables_preview'] as List?) ?? const [];
    final pois = (result['pois'] as Map?)?.cast<String, dynamic>() ?? const {};
    final method = result['method']?.toString();
    final compsCount = (result['comparables_count'] as int?) ?? 0;

    return ListView(
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
        const SizedBox(height: 18),
        _MethodCard(
          method: method,
          comparablesCount: compsCount,
          poisCount: pois.values.fold<int>(
            0,
            (acc, v) => acc + (v is List ? v.length : 0),
          ),
          isDark: isDark,
        ),
        if (comps.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle('Yaqin atrofdagi e\'lonlar', isDark: isDark),
          const SizedBox(height: 8),
          for (final c in comps.take(6))
            _ComparableTile(data: c as Map, isDark: isDark),
        ],
        if (pois.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle('Yaqin atrofdagi obyektlar', isDark: isDark),
          const SizedBox(height: 8),
          _PoiSummary(pois: pois, isDark: isDark),
        ],
        const SizedBox(height: 24),
        ListingCtaButton(
          label: 'Asosiy sahifa',
          enabled: true,
          onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
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

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.comparablesCount,
    required this.poisCount,
    required this.isDark,
  });

  final String? method;
  final int comparablesCount;
  final int poisCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (method != null && method!.isNotEmpty) ...[
            Text(
              method!,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                height: 1.4,
                color: text,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _Pill(
                icon: Icons.home_work_outlined,
                label: '$comparablesCount ta e\'lon',
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _Pill(
                icon: Icons.place_outlined,
                label: '$poisCount ta obyekt',
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Internal alignment with `sub` palette for cohesion.
          Text(
            ' ',
            style: TextStyle(fontSize: 0, color: sub),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.isDark,
  });
  final IconData icon;
  final String label;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    final fill =
        AppColors.splashGreen.withValues(alpha: isDark ? 0.18 : 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.splashGreen, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppColors.splashGreen,
            ),
          ),
        ],
      ),
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

class _ComparableTile extends StatelessWidget {
  const _ComparableTile({required this.data, required this.isDark});
  final Map data;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final price = (data['price_uzs'] as num?)?.toDouble();
    final area = (data['area_sqm'] as num?)?.toDouble();
    final distance = (data['distance_km'] as num?)?.toDouble();
    final addr = data['address']?.toString();
    final url = data['url']?.toString();

    return GestureDetector(
      onTap: url == null ? null : () => _open(context, url),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    price == null
                        ? '—'
                        : '${_PriceCard._formatUzs(price)} so\'m'
                            '${area == null ? '' : ' · ${area.toStringAsFixed(0)} m²'}',
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: text,
                    ),
                  ),
                  if (addr != null && addr.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      addr,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12,
                        color: sub,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (distance != null) ...[
              const SizedBox(width: 10),
              Text(
                '${distance.toStringAsFixed(1)} km',
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
    );
  }

  void _open(BuildContext context, String url) {
    // Just toast the URL for now — Market detail screen is the natural
    // landing, but plumbing that is out of scope for this status screen.
    AppToast.success(context, url);
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
                    '${(r.value as List).length} ta',
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
