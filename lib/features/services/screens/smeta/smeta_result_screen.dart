/// Result screen — polls `/abc4/jobs/{id}` until terminal, then renders
/// the total + record lines and offers buttons to view the ABC HTM
/// ведомость inline (WebView) or open in the system browser.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
          _error = _Strings.timedOut(Localizations.localeOf(context));
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
                title: _Strings.appBar(locale),
                subtitle: _Strings.jobSubtitle(
                  locale,
                  '${widget.jobId.substring(0, 8)}…',
                ),
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

class _Strings {
  const _Strings._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String appBar(Locale l) =>
      _pick(l, 'Smeta natijasi', 'Результат сметы', 'Estimate result');

  static String jobSubtitle(Locale l, String id) =>
      _pick(l, 'Vazifa $id', 'Задача $id', 'Job $id');

  static String timedOut(Locale l) => _pick(
        l,
        "Vaqt tugadi (5 daqiqa). Driver ishlamayotgan bo'lishi mumkin.",
        'Время истекло (5 минут). Возможно, драйвер не работает.',
        'Timed out (5 minutes). The driver may be down.',
      );

  static String inFlightLabel(Locale l, String state) => switch (state) {
        'queued' => _pick(l, 'Navbatda kutilmoqda…', 'В очереди…', 'Queued…'),
        'running' =>
          _pick(l, 'ABC hisoblamoqda…', 'ABC рассчитывает…', 'ABC is calculating…'),
        _ => _pick(l, 'Holat: $state', 'Статус: $state', 'Status: $state'),
      };

  static String inFlightHint(Locale l) => _pick(
        l,
        'Bu odatda 1–3 daqiqa davom etadi.',
        'Обычно это занимает 1–3 минуты.',
        'This usually takes 1–3 minutes.',
      );

  static String positions(Locale l) =>
      _pick(l, 'Pozitsiyalar', 'Позиции', 'Positions');

  static String vedomost(Locale l) => _pick(
        l,
        "Vedomost (Form N5/N6)",
        'Ведомость (Форма N5/N6)',
        'Statement (Form N5/N6)',
      );

  static String otherFiles(Locale l) =>
      _pick(l, 'Boshqa fayllar', 'Другие файлы', 'Other files');

  static String smetaReady(Locale l) =>
      _pick(l, 'Smeta tayyor', 'Смета готова', 'Estimate ready');

  static String smetaNoResult(Locale l) => _pick(
        l,
        'Hisob tugadi, lekin natija topilmadi',
        'Расчёт завершён, но результат не найден',
        'Calculation finished, but no result found',
      );

  static String openExternal(Locale l) => _pick(
        l,
        'Tashqi brauzerda ochish',
        'Открыть во внешнем браузере',
        'Open in external browser',
      );

  static String openFile(Locale l, String name) => _pick(
        l,
        "$name ko'rish",
        'Открыть $name',
        'View $name',
      );
}

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
            _Strings.inFlightLabel(locale, state),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.textBlack,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _Strings.inFlightHint(locale),
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
          _SectionLabel(_Strings.positions(locale)),
          for (final r in records.whereType<Map<String, dynamic>>())
            _RecordCard(record: r),
        ],
        if (primary != null) ...[
          const SizedBox(height: 20),
          _SectionLabel(_Strings.vedomost(locale)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _VedomostViewer(
                    jobId: snap.id,
                    filename: primary,
                    service: service,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.description_outlined),
            label: Text(_Strings.openFile(locale, primary)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(service.exportUrl(snap.id, primary)),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: Text(_Strings.openExternal(locale)),
          ),
        ],
        if (exports.length > 1) ...[
          const SizedBox(height: 12),
          _SectionLabel(_Strings.otherFiles(locale)),
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
        ? _Strings.smetaReady(locale)
        : _Strings.smetaNoResult(locale);

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
        onPressed: () => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
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
