/// Result screen — polls `/abc4/jobs/{id}` until terminal, then renders
/// the total + record lines and offers buttons to view the ABC HTM
/// ведомость inline (WebView) or open in the system browser.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/haptics.dart';
import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../data/smeta_api_service.dart';
import '../../models/smeta_draft.dart';
import '../../widgets/service_app_bar.dart';

class SmetaResultScreen extends StatefulWidget {
  const SmetaResultScreen({
    super.key,
    required this.jobId,
    this.service,
  });

  final String jobId;
  final SmetaApiService? service;

  @override
  State<SmetaResultScreen> createState() => _SmetaResultScreenState();
}

class _SmetaResultScreenState extends State<SmetaResultScreen> {
  // ABC driver runs are 60–180 s typically; keep polling for up to 5 min.
  static const Duration _pollEvery = Duration(seconds: 4);
  static const Duration _giveUpAfter = Duration(minutes: 5);

  late final SmetaApiService _service = widget.service ?? SmetaApiService();

  SmetaJobSnapshot? _snap;
  List<String> _exports = const [];
  String? _error;
  Timer? _timer;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _tick();
    _timer = Timer.periodic(_pollEvery, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_startedAt != null &&
        DateTime.now().difference(_startedAt!) > _giveUpAfter) {
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _error = tr(
            Localizations.localeOf(context),
            'services.smeta.result.timed_out',
          );
        });
      }
      return;
    }
    try {
      final snap = await _service.status(widget.jobId);
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _error = null;
      });
      if (snap.isTerminal) {
        _timer?.cancel();
        await _loadExports();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _loadExports() async {
    try {
      final files = await _service.exports(widget.jobId);
      if (!mounted) return;
      setState(() => _exports = files);
    } catch (_) {
      // non-fatal — just no export buttons
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final locale = Localizations.localeOf(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: ServiceAppBar(
                title: tr(locale, 'services.smeta.result.appbar'),
                subtitle:
                    '${tr(locale, 'services.smeta.result.job')} ${widget.jobId.substring(0, 8)}…',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_error != null) {
      return _ErrorView(message: _error!);
    }
    final snap = _snap;
    if (snap == null || !snap.isTerminal) {
      return _InFlightView(state: snap?.state ?? 'queued');
    }
    return _ResultView(
      snap: snap,
      exports: _exports,
      service: _service,
    );
  }
}

String _inFlightLabel(Locale l, String state) => switch (state) {
      'queued' => tr(l, 'services.smeta.result.queued'),
      'running' => tr(l, 'services.smeta.result.running'),
      _ => '${tr(l, 'services.smeta.result.status')}: $state',
    };

// ─── in-flight ────────────────────────────────────────────────────────

class _InFlightView extends StatelessWidget {
  const _InFlightView({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context);
    final muted =
        isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
          const SizedBox(height: 20),
          Text(
            _inFlightLabel(locale, state),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.textBlack,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(locale, 'services.smeta.result.in_flight_hint'),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 13,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── result ──────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.snap,
    required this.exports,
    required this.service,
  });

  final SmetaJobSnapshot snap;
  final List<String> exports;
  final SmetaApiService service;

  /// Pick the most "user-meaningful" file to show first: priced Ведомость
  /// (bv*) > priced Расчет (bp*) > input echo (Id*) > anything.
  String? get _primaryExport {
    if (exports.isEmpty) return null;
    String? best;
    int bestRank = -1;
    for (final f in exports) {
      final low = f.toLowerCase();
      int rank;
      if (low.startsWith('bv')) {
        rank = 4;
      } else if (low.startsWith('bp')) {
        rank = 3;
      } else if (low.startsWith('id')) {
        rank = 2;
      } else if (low.startsWith('tr')) {
        rank = 1;
      } else {
        rank = 0;
      }
      if (rank > bestRank) {
        bestRank = rank;
        best = f;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final records = snap.records ?? const [];
    final primary = _primaryExport;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _StatusBanner(snap: snap, hasExports: exports.isNotEmpty),
        const SizedBox(height: 16),
        if (records.isNotEmpty) ...[
          _SectionLabel(tr(locale, 'services.smeta.result.positions')),
          for (final r in records.whereType<Map<String, dynamic>>())
            _RecordCard(record: r),
        ],
        if (primary != null) ...[
          const SizedBox(height: 20),
          _SectionLabel(tr(locale, 'services.smeta.result.vedomost')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: hapticTap(() {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _VedomostViewer(
                    jobId: snap.id,
                    filename: primary,
                    service: service,
                  ),
                ),
              );
            }),
            icon: const Icon(Icons.description_outlined),
            label: Text(
              tr(locale, 'services.smeta.result.open_file')
                  .replaceFirst('{name}', primary),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: hapticTap(() => launchUrl(
              Uri.parse(service.exportUrl(snap.id, primary)),
              mode: LaunchMode.externalApplication,
            )),
            icon: const Icon(Icons.open_in_new),
            label: Text(tr(locale, 'services.smeta.result.open_external')),
          ),
        ],
        if (exports.length > 1) ...[
          const SizedBox(height: 12),
          _SectionLabel(tr(locale, 'services.smeta.result.other_files')),
          for (final f in exports.where((x) => x != primary))
            _SmallExportButton(
              filename: f,
              url: service.exportUrl(snap.id, f),
            ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.snap, required this.hasExports});
  final SmetaJobSnapshot snap;
  final bool hasExports;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ok = hasExports || (snap.result?.values.any((v) => v != null) ?? false);
    final color = ok ? AppColors.splashGreen : Colors.orange;
    final label = ok
        ? tr(locale, 'services.smeta.result.ready')
        : tr(locale, 'services.smeta.result.no_result');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted =
        isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    // Pull whatever fields look meaningful — driver's record shape is loose.
    final code = (record['code'] ?? '').toString();
    final name = (record['name'] ?? record['section'] ?? '').toString();
    final type = (record['type'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (code.isNotEmpty)
            Text(
              code,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.splashGreen,
              ),
            ),
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 13,
                  color: textColor,
                ),
              ),
            ),
          if (type.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                type,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 11,
                  color: muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF6C7278);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: muted,
        ),
      ),
    );
  }
}

class _SmallExportButton extends StatelessWidget {
  const _SmallExportButton({required this.filename, required this.url});
  final String filename;
  final String url;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TextButton.icon(
        onPressed: hapticTap(() => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        )),
        icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
        label: Text(filename),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── inline WebView for the ABC HTM file ──────────────────────────────

class _VedomostViewer extends StatefulWidget {
  const _VedomostViewer({
    required this.jobId,
    required this.filename,
    required this.service,
  });

  final String jobId;
  final String filename;
  final SmetaApiService service;

  @override
  State<_VedomostViewer> createState() => _VedomostViewerState();
}

class _VedomostViewerState extends State<_VedomostViewer> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.service.exportUrl(widget.jobId, widget.filename)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.filename)),
      body: WebViewWidget(controller: _controller),
    );
  }
}
