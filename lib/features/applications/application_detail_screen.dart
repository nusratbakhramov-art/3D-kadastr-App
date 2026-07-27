import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_config.dart';
import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_http_client.dart';
import '../auth/auth_storage.dart';
import '../settings/settings_state.dart';
import '../scans/splat_viewer_screen.dart';
import '../services/ai_draft_resume.dart';
import '../services/api_ai_valuation_job_service.dart';
import '../services/api_photogrammetry_service.dart';
import '../services/models/ai_baholash_bundle.dart' show RoomKind;
import '../services/data/model_preview.dart';
import '../services/data/room_plan_scanner.dart';
import '../services/widgets/segmented_tabs.dart';
import '../services/widgets/schema_answers_view.dart';
import 'application_model.dart';
import 'pdf_viewer_screen.dart';

/// Stream the 3D result file (.usdz or .splat) to disk with progress.
///
/// `format` ("usdz" yoki "splat") fayl kengaytmasini hal qiladi.
/// [onProgress] is called with `(received, total)` byte counts; `total` is
/// -1 if the server didn't send Content-Length.
Future<String> _ensureResultCached({
  required int jobId,
  required String downloadUrl,
  required String format, // 'usdz' | 'splat'
  String prefix = 'photo', // cache fayl nomi prefiksi (photo / aival)
  void Function(int received, int total)? onProgress,
}) async {
  // Resolve a writable cache dir. On a fresh iOS container the Documents dir
  // may not be materialized yet and createSync can throw errno 2 even with
  // recursive:true — fall back to the temp dir so downloads never crash.
  Directory scansDir;
  try {
    final dir = await getApplicationDocumentsDirectory();
    scansDir = Directory('${dir.path}/scans');
    await scansDir.create(recursive: true);
  } catch (_) {
    final tmpRoot = await getTemporaryDirectory();
    scansDir = Directory('${tmpRoot.path}/scans');
    await scansDir.create(recursive: true);
  }
  final filePath = '${scansDir.path}/${prefix}_$jobId.$format';
  final file = File(filePath);
  if (await file.exists() && await file.length() > 0) {
    onProgress?.call(await file.length(), await file.length());
    return filePath;
  }

  final client = AuthHttpClient();
  final req = http.Request('GET', Uri.parse(downloadUrl));
  final res = await client.send(req);
  if (res.statusCode != 200) {
    throw HttpException(
      tr(localeNotifier.value, 'applications.detail.download_error')
          .replaceFirst('{code}', '${res.statusCode}'),
    );
  }
  final total = res.contentLength ?? -1;
  // Write to a tmp file first; rename on success so partials don't poison cache.
  final tmp = File('$filePath.part');
  final sink = tmp.openWrite();
  var received = 0;
  try {
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  await tmp.rename(filePath);
  return filePath;
}

/// Source rect for the iOS share-sheet popover (required on iPad / some iOS).
Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class ApplicationDetailScreen extends StatefulWidget {
  const ApplicationDetailScreen({super.key, required this.item});

  final ApplicationItem item;

  @override
  State<ApplicationDetailScreen> createState() =>
      _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState extends State<ApplicationDetailScreen> {
  _DetailTab _tab = _DetailTab.status;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final steps = widget.item.timeline
        .where((s) => s.completed)
        .toList(growable: false);
    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeaderBack(
                title: tr(Locale(lang), 'applications.title'),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 2),
              Text(
                widget.item.orderNo != null
                    ? '${widget.item.serviceLabel} #${widget.item.orderNo}'
                    : widget.item.serviceLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.3,
                  color: ColorTokens.secondaryText(context),
                ),
              ),
              const SizedBox(height: 14),
              SegmentedTabs<_DetailTab>(
                values: _DetailTab.values,
                labelOf: (t) => switch (t) {
                  _DetailTab.status => tr(Locale(lang), 'applications.detail.status_tab'),
                  _DetailTab.about => tr(Locale(lang), 'applications.detail.about_tab'),
                },
                selected: _tab,
                onChanged: (next) => setState(() => _tab = next),
              ),
              const SizedBox(height: 14),
              if (_tab == _DetailTab.status)
                _StatusTab(steps: steps, item: widget.item)
              else
                _AboutTab(item: widget.item),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DetailTab { status, about }

class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.steps, required this.item});

  final List<ApplicationTimelineStep> steps;
  final ApplicationItem item;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final canResume = item.isDraft && item.resumeJobId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineCard(steps: steps),
        const SizedBox(height: 14),
        if (canResume)
          _ResumeDraftAction(
            label: tr(Locale(lang), 'applications.detail.continue_draft'),
            jobId: item.resumeJobId!,
          )
        else
          _PrimaryBlackAction(label: tr(Locale(lang), 'applications.detail.contact_specialist')),
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.steps});

  final List<ApplicationTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final visible = steps.isEmpty ? const <ApplicationTimelineStep>[] : steps;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ColorTokens.outline(context), width: 0.6),
      ),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++)
            _TimelineRow(step: visible[i], showTail: i != visible.length - 1),
          if (visible.isEmpty)
            Text(
              tr(
                Localizations.localeOf(context),
                'applications.detail.no_timeline_yet',
              ),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: ColorTokens.secondaryText(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.showTail});

  final ApplicationTimelineStep step;
  final bool showTail;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final style = _TimelineStyle.fromStatus(step.status, lang);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: style.bg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(style.icon, color: Colors.white, size: 22),
              ),
              if (showTail)
                Container(
                  width: 1,
                  height: 34,
                  color: ColorTokens.outline(context),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                    color: ColorTokens.primaryText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAt(step.at),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    height: 1.3,
                    color: ColorTokens.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineStyle {
  const _TimelineStyle({
    required this.label,
    required this.icon,
    required this.bg,
  });

  final String label;
  final IconData icon;
  final Color bg;

  static _TimelineStyle fromStatus(
    ApplicationTimelineStatus status,
    String lang,
  ) => switch (status) {
    ApplicationTimelineStatus.draft => _TimelineStyle(
      label: tr(Locale(lang), 'applications.detail.timeline_draft'),
      icon: Icons.edit_note_rounded,
      bg: const Color(0xFFE0A12A), // amber — matches the "Qoralama" badge
    ),
    ApplicationTimelineStatus.accepted => _TimelineStyle(
      label: tr(Locale(lang), 'applications.detail.timeline_accepted'),
      icon: Icons.description_outlined,
      bg: const Color(0xFF18B4E8),
    ),
    ApplicationTimelineStatus.sentToSystem => _TimelineStyle(
      label: tr(Locale(lang), 'applications.detail.timeline_sent'),
      icon: Icons.send_rounded,
      bg: const Color(0xFF6A16F6),
    ),
    ApplicationTimelineStatus.assignedSpecialist => _TimelineStyle(
      label: tr(Locale(lang), 'applications.detail.timeline_assigned'),
      icon: Icons.badge_outlined,
      bg: const Color(0xFFFF9800),
    ),
    ApplicationTimelineStatus.scanned => _TimelineStyle(
      label: tr(Locale(lang), 'applications.detail.timeline_scanned'),
      icon: Icons.crop_free_rounded,
      bg: const Color(0xFF03C050),
    ),
    ApplicationTimelineStatus.reportReady => _TimelineStyle(
      label: tr(Locale(lang), 'applications.detail.timeline_report_ready'),
      icon: Icons.description_outlined,
      bg: const Color(0xFF1A9BF4),
    ),
  };
}

/// Eski tekis (label → value) ro'yxat kartasi — dinamik sxema bo'lmagan
/// arizalar va sxema yuklanmagan holat uchun zaxira.
Widget _flatRowsCard(
  BuildContext context,
  String lang,
  List<(String, String)> rows,
) {
  return Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
    decoration: BoxDecoration(
      color: ColorTokens.cardBg(context),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: ColorTokens.outline(context), width: 0.6),
    ),
    child: rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              tr(Locale(lang), 'applications.detail.no_data'),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: ColorTokens.secondaryText(context),
              ),
            ),
          )
        : Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                _InfoRow(label: rows[i].$1, value: rows[i].$2),
                if (i != rows.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: ColorTokens.divider(context),
                  ),
              ],
            ],
          ),
  );
}

/// Section title with a green accent bar — groups the detail cards visually.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: ColorTokens.brandPrimary(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: ColorTokens.primaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.item});

  final ApplicationItem item;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final rows = item.detailRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          (item.hasDeliverable ||
                  item.aiReportJobId != null ||
                  item.k3dReportJobId != null ||
                  item.k3dModelJobId != null)
              ? tr(Locale(lang), 'applications.detail.report')
              : tr(Locale(lang), 'applications.detail.details'),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: ColorTokens.primaryText(context),
          ),
        ),
        const SizedBox(height: 10),
        // AI Baholash — to'liq job snapshot'ini (so'rov + natija) olib, BARCHA
        // maydonlarni bo'limlarga ajratib ko'rsatamiz. Yuklanmasa yoki xato
        // bo'lsa yengil ro'yxatga (rows) qaytadi.
        if (item.aiJobId != null)
          _AiFullDetail(
            jobId: item.aiJobId!,
            fallback: _flatRowsCard(context, lang, rows),
          )
        // 3D Kadastr — to'liq job snapshot'ini (so'rov payload) olib, BARCHA
        // maydonlarni bo'limlarga ajratib ko'rsatamiz (obyekt, buyurtmachi,
        // joylashuv, qavat, xonalar). Yuklanmasa yengil ro'yxatga qaytadi.
        else if (item.k3dJobId != null)
          _Kadastr3dFullDetail(
            jobId: item.k3dJobId!,
            fallback: _flatRowsCard(context, lang, rows),
          )
        // Dinamik forma (TZ) arizalari — backend sxemasi bo'yicha to'liq
        // (barcha to'ldirilgan maydonlar, bo'limga ajratilgan). Sxema yuklanmasa
        // eski tekis ro'yxatga qaytadi.
        else if (item.formKey != null &&
            (item.formPayload?.isNotEmpty ?? false))
          SchemaAnswersView(
            formKey: item.formKey!,
            payload: item.formPayload!,
            fallback: _flatRowsCard(context, lang, rows),
          )
        else
          _flatRowsCard(context, lang, rows),
        // Baholash guruhi xulosasi (izoh + sabab) — yozilgan bo'lsa
        // foydalanuvchiga ko'rsatiladi (under_review yoki completed).
        if ((item.estimatorCause?.trim().isNotEmpty ?? false) ||
            (item.estimatorComment?.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: 14),
          _EstimatorCard(
            comment: item.estimatorComment,
            cause: item.estimatorCause,
          ),
        ],
        // Yakuniy baholash hisoboti (Xulosa, PDF) — ariza COMPLETED bo'lганда.
        if (item.aiReportJobId != null) ...[
          const SizedBox(height: 14),
          _AiXulosaCard(jobId: item.aiReportJobId!),
          // Narxlash Orderi — dizaynli AI baholash orderi (alohida PDF).
          const SizedBox(height: 14),
          _AiOrderCard(jobId: item.aiReportJobId!),
        ],
        // AI Baholash arizasiga biriktirilgan teksturali 3D (USDZ) skan —
        // har qanday statusda (skan submit paytida yuklanadi). "3D Kadastr"
        // ariza detali bilan bir xil ko‘rinish: "3D model → Ochish" karta +
        // pastda "AR orqali ko‘rish" yashil tugmasi.
        if (item.aiScanJobId != null) ...[
          const SizedBox(height: 14),
          _AiScanCard(jobId: item.aiScanJobId!),
          // Skan paytida olingan rasmlar (frames) — scan_files'dan. Eski
          // arizalarda rasm bo'lmasa, kartani o'zi yashiradi.
          _AiScanFramesGallery(jobId: item.aiScanJobId!),
        ],
        // 3D Kadastr — specialist-delivered conclusion PDF + 3D model, shown
        // once the ariza is COMPLETED (cards appear only for the files present).
        if (item.k3dReportJobId != null) ...[
          const SizedBox(height: 14),
          _K3dReportCard(jobId: item.k3dReportJobId!),
        ],
        if (item.k3dModelJobId != null) ...[
          const SizedBox(height: 14),
          _K3dModelCard(jobId: item.k3dModelJobId!, ext: item.k3dModelExt),
        ],
        // The downloadable report / 3D model / AR view only exist for a
        // finished deliverable (completed photogrammetry scan). For jobs that
        // are still just submitted, we don't fake a report.
        if (item.hasDeliverable) ...[
          const SizedBox(height: 14),
          const _FileCard(),
          const SizedBox(height: 14),
          _ModelCard(item: item),
          const SizedBox(height: 18),
          _PrimaryGreenAction(
            label: tr(Locale(lang), 'applications.detail.view_via_ar'),
            item: item,
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.3,
                color: ColorTokens.secondaryText(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.3,
                  color: ColorTokens.primaryText(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI Baholash arizasining TO'LIQ tafsiloti — yengil ro'yxat o'rniga butun job
/// snapshot'ini (`/ai-valuations/{id}`: so'rov + natija payload) olib, barcha
/// maydonlarni bo'limlarga ajratib ko'rsatadi (Obyekt, Buyurtmachi, Joylashuv,
/// Xonalar, Natija). Yuklanayotганда spinner, xatoда `fallback` ko'rsatiladi.
class _AiFullDetail extends StatefulWidget {
  const _AiFullDetail({required this.jobId, required this.fallback});

  final int jobId;
  final Widget fallback;

  @override
  State<_AiFullDetail> createState() => _AiFullDetailState();
}

class _AiFullDetailState extends State<_AiFullDetail> {
  /// Sessiya davomida job snapshot'larini keshda saqlaymiz — detal ekrani
  /// (yoki "Ariza haqida" tab'i) har ochilganda `/ai-valuations/{id}` ni qayta
  /// so'ramasligi uchun. Ilova qayta ishga tushmaguncha yashaydi.
  static final Map<int, AiJobSnapshot> _cache = {};

  AiJobSnapshot? _snap;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.jobId];
    if (cached != null) {
      _snap = cached;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final client = AuthHttpClient();
      final res = await client.get(
        Uri.parse('${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}'),
      );
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final snap = AiJobSnapshot.fromJson(json);
      _cache[widget.jobId] = snap;
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final snap = _snap;
    if (_error || snap == null) return widget.fallback;

    final lang = Localizations.localeOf(context).languageCode;
    final sections = _buildAiSections(lang, snap);
    if (sections.isEmpty) return widget.fallback;

    final summary = (snap.resultPayload?['summary'] as String?)?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i != 0) const SizedBox(height: 8),
          _SectionHeader(title: sections[i].$1),
          _flatRowsCard(context, lang, sections[i].$2),
        ],
        if (summary != null && summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionHeader(
            title: tr(Locale(lang), 'applications.detail.ai_summary'),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ColorTokens.cardBg(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: ColorTokens.outline(context),
                width: 0.6,
              ),
            ),
            child: Text(
              summary,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.4,
                color: ColorTokens.primaryText(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Localized room label: map the stored `kind` wire to RoomKind.label so it
/// shows in the user's language (was leaking the raw English wire like
/// "bedroom"). A custom room ('other') or unknown kind falls back to the
/// user-entered name.
String _roomLabel(String lang, Map<String, dynamic> m) {
  final wire = m['kind']?.toString();
  final name = m['name']?.toString().trim();
  RoomKind? rk;
  for (final k in RoomKind.values) {
    if (k.wire == wire) {
      rk = k;
      break;
    }
  }
  if (rk != null && rk != RoomKind.other) return rk.label(Locale(lang));
  if (name != null && name.isNotEmpty) return name;
  return rk?.label(Locale(lang)) ?? tr(Locale(lang), 'applications.detail.room');
}


/// Thousands-grouped UZS amount, e.g. 622794192 → "622 794 192 so'm".
String _aiMoney(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return "${v < 0 ? '-' : ''}${b.toString()} so'm";
}

/// Build the grouped (sectionTitle, rows) list from a full AI job snapshot.
/// Only non-empty fields/sections are included.
List<(String, List<(String, String)>)> _buildAiSections(
  String lang,
  AiJobSnapshot snap,
) {
  final req = snap.requestPayload;
  final kad = (req['kadastr'] as Map?)?.cast<String, dynamic>() ?? const {};
  final client = (req['client'] as Map?)?.cast<String, dynamic>() ?? const {};
  final loc = (req['location'] as Map?)?.cast<String, dynamic>() ?? const {};
  final rooms = (req['rooms'] as List?) ?? const [];
  final res = snap.resultPayload ?? const {};

  String? str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  void add(List<(String, String)> rows, String label, String? value) {
    if (value != null) rows.add((label, value));
  }

  final sections = <(String, List<(String, String)>)>[];

  // ── Obyekt ──────────────────────────────────────────────────────────
  final prop = <(String, String)>[];
  add(
    prop,
    tr(Locale(lang), 'applications.detail.cadastre_no'),
    str(kad['cadastre_number']),
  );
  add(
    prop,
    tr(Locale(lang), 'applications.address'),
    str(kad['address']) ?? str(loc['address']),
  );
  add(
    prop,
    tr(Locale(lang), 'applications.object_type'),
    str(kad['object_type_hint']),
  );
  add(
    prop,
    tr(Locale(lang), 'applications.detail.total_area'),
    kad['total_area'] != null ? '${kad['total_area']} m²' : null,
  );
  add(
    prop,
    tr(Locale(lang), 'applications.detail.living_area'),
    kad['living_area'] != null ? '${kad['living_area']} m²' : null,
  );
  final floor = str(req['floor']);
  if (floor != null) {
    final total = str(req['total_floors']);
    add(
      prop,
      tr(Locale(lang), 'applications.detail.floor'),
      total != null ? '$floor / $total' : floor,
    );
  }
  if (kad['cadastre_value'] is num) {
    add(
      prop,
      tr(Locale(lang), 'applications.detail.cadastre_value'),
      _aiMoney(kad['cadastre_value'] as num),
    );
  }
  if (prop.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_property'), prop));
  }

  // ── Buyurtmachi ─────────────────────────────────────────────────────
  final cl = <(String, String)>[];
  add(cl, tr(Locale(lang), 'applications.detail.name'), str(client['name']));
  add(cl, tr(Locale(lang), 'applications.detail.phone'), str(client['phone']));
  add(cl, tr(Locale(lang), 'applications.detail.tin_label'), str(client['stir']));
  add(cl, tr(Locale(lang), 'applications.detail.email_label'), str(client['email']));
  if (cl.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_client'), cl));
  }

  // ── Joylashuv ───────────────────────────────────────────────────────
  final lc = <(String, String)>[];
  if (loc['lat'] != null && loc['lng'] != null) {
    add(
      lc,
      tr(Locale(lang), 'applications.detail.coordinates'),
      '${loc['lat']}, ${loc['lng']}',
    );
  }
  add(lc, tr(Locale(lang), 'applications.detail.purpose'), str(req['purpose']));
  if (lc.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_location'), lc));
  }

  // ── Xonalar ─────────────────────────────────────────────────────────
  final rm = <(String, String)>[];
  for (final r in rooms) {
    if (r is! Map) continue;
    final m = r.cast<String, dynamic>();
    final name = _roomLabel(lang, m);
    final parts = <String>[];
    if (m['count'] != null) {
      parts.add('${m['count']} ${tr(Locale(lang), 'applications.unit.pcs')}');
    }
    if (m['area'] != null) parts.add('${m['area']} m²');
    rm.add((name, parts.isEmpty ? '—' : parts.join(' · ')));
  }
  if (rm.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_rooms'), rm));
  }

  // ── Natija ──────────────────────────────────────────────────────────
  final rs = <(String, String)>[];
  if (res['estimated_value'] is num) {
    add(
      rs,
      tr(Locale(lang), 'applications.detail.estimated_value'),
      _aiMoney(res['estimated_value'] as num),
    );
  }
  final ppsq = res['price_per_sqm'] ?? res['value_per_sqm'];
  if (ppsq is num) {
    add(
      rs,
      tr(Locale(lang), 'applications.detail.price_per_sqm'),
      _aiMoney(ppsq),
    );
  }
  final conf = res['confidence'];
  if (conf is num) {
    add(
      rs,
      tr(Locale(lang), 'applications.detail.confidence'),
      conf <= 1 ? '${(conf * 100).round()}%' : conf.toString(),
    );
  }
  if (snap.nearbyListingsCount > 0) {
    add(
      rs,
      tr(Locale(lang), 'applications.detail.comparables'),
      '${snap.nearbyListingsCount}',
    );
  }
  if (snap.nearbyPoisCount > 0) {
    add(
      rs,
      tr(Locale(lang), 'applications.detail.nearby_pois'),
      '${snap.nearbyPoisCount}',
    );
  }
  if (rs.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_result'), rs));
  }

  return sections;
}

// ── 3D Kadastr full detail ───────────────────────────────────────────────
// Fetches the FULL job (`GET /3d-kadastr-jobs/{id}`) and renders every field
// the user submitted, grouped into sections — same look as the AI Baholash
// detail. Falls back to the lightweight rows on load failure.
class _Kadastr3dFullDetail extends StatefulWidget {
  const _Kadastr3dFullDetail({required this.jobId, required this.fallback});

  final int jobId;
  final Widget fallback;

  @override
  State<_Kadastr3dFullDetail> createState() => _Kadastr3dFullDetailState();
}

class _Kadastr3dFullDetailState extends State<_Kadastr3dFullDetail> {
  Map<String, dynamic>? _payload;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = AuthHttpClient();
      final res = await client.get(
        Uri.parse('${ApiConfig.baseUrl}/3d-kadastr-jobs/${widget.jobId}'),
      );
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _payload =
            (json['request_payload'] as Map?)?.cast<String, dynamic>() ?? {};
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final payload = _payload;
    if (_error || payload == null) return widget.fallback;

    final lang = Localizations.localeOf(context).languageCode;
    final sections = _buildKadastr3dSections(lang, payload);
    if (sections.isEmpty) return widget.fallback;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i != 0) const SizedBox(height: 8),
          _SectionHeader(title: sections[i].$1),
          _flatRowsCard(context, lang, sections[i].$2),
        ],
      ],
    );
  }
}

String _k3dObjectType(String lang, String? wire) => switch (wire) {
  'residential' => tr(Locale(lang), 'applications.object.residential'),
  'non_residential' => tr(Locale(lang), 'applications.object.non_residential'),
  'warehouse' => tr(Locale(lang), 'applications.object.warehouse'),
  'industrial' => tr(Locale(lang), 'applications.detail.object_industrial'),
  _ => wire ?? '',
};

/// Build the grouped (sectionTitle, rows) list from a 3D Kadastr request
/// payload. Only non-empty fields/sections are included.
List<(String, List<(String, String)>)> _buildKadastr3dSections(
  String lang,
  Map<String, dynamic> req,
) {
  final kad = (req['kadastr'] as Map?)?.cast<String, dynamic>() ?? const {};
  final client = (req['client'] as Map?)?.cast<String, dynamic>() ?? const {};
  final loc = (req['location'] as Map?)?.cast<String, dynamic>() ?? const {};
  final rooms = (req['rooms'] as List?) ?? const [];
  final imageKeys = (req['image_keys'] as List?) ?? const [];
  final kadastrKeys = (req['kadastr_keys'] as List?) ?? const [];

  String? str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  void add(List<(String, String)> rows, String label, String? value) {
    if (value != null) rows.add((label, value));
  }

  final sections = <(String, List<(String, String)>)>[];

  // ── Obyekt ────────────────────────────────────────────────────────────
  final prop = <(String, String)>[];
  add(
    prop,
    tr(Locale(lang), 'applications.detail.cadastre_no'),
    str(kad['cadastre_number']),
  );
  add(
    prop,
    tr(Locale(lang), 'applications.address'),
    str(kad['address']) ?? str(loc['address_text']),
  );
  final ot = str(req['object_type']);
  if (ot != null) {
    add(
      prop,
      tr(Locale(lang), 'applications.object_type'),
      _k3dObjectType(lang, ot),
    );
  }
  add(
    prop,
    tr(Locale(lang), 'applications.detail.davreestr_type'),
    str(kad['object_type_hint']),
  );
  add(
    prop,
    tr(Locale(lang), 'applications.detail.total_area'),
    kad['total_area'] != null ? '${kad['total_area']} m²' : null,
  );
  add(
    prop,
    tr(Locale(lang), 'applications.detail.living_area'),
    kad['living_area'] != null ? '${kad['living_area']} m²' : null,
  );
  final floor = str(req['floor']);
  if (floor != null) {
    final total = str(req['total_floors']);
    add(
      prop,
      tr(Locale(lang), 'applications.detail.floor'),
      total != null ? '$floor / $total' : floor,
    );
  }
  if (kad['cadastre_value'] is num) {
    add(
      prop,
      tr(Locale(lang), 'applications.detail.cadastre_value'),
      _aiMoney(kad['cadastre_value'] as num),
    );
  }
  if (prop.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_property'), prop));
  }

  // ── Buyurtmachi ─────────────────────────────────────────────────────────
  final cl = <(String, String)>[];
  add(cl, tr(Locale(lang), 'applications.detail.name'), str(client['name']));
  add(cl, tr(Locale(lang), 'applications.detail.phone'), str(client['phone']));
  add(cl, tr(Locale(lang), 'applications.detail.tin_label'), str(client['stir']));
  add(cl, tr(Locale(lang), 'applications.detail.email_label'), str(client['email']));
  if (cl.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_client'), cl));
  }

  // ── Joylashuv ───────────────────────────────────────────────────────────
  final lc = <(String, String)>[];
  if (loc['lat'] != null && loc['lng'] != null) {
    add(
      lc,
      tr(Locale(lang), 'applications.detail.coordinates'),
      '${loc['lat']}, ${loc['lng']}',
    );
  }
  if (lc.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_location'), lc));
  }

  // ── Xonalar ─────────────────────────────────────────────────────────────
  final rm = <(String, String)>[];
  for (final r in rooms) {
    if (r is! Map) continue;
    final m = r.cast<String, dynamic>();
    final name = _roomLabel(lang, m);
    final parts = <String>[];
    if (m['count'] != null) {
      parts.add('${m['count']} ${tr(Locale(lang), 'applications.unit.pcs')}');
    }
    if (m['area'] != null) parts.add('${m['area']} m²');
    rm.add((name, parts.isEmpty ? '—' : parts.join(' · ')));
  }
  if (rm.isNotEmpty) {
    sections.add((tr(Locale(lang), 'applications.detail.section_rooms'), rm));
  }

  // ── Yuklangan fayllar ────────────────────────────────────────────────────
  final files = <(String, String)>[];
  if (imageKeys.isNotEmpty) {
    add(
      files,
      tr(Locale(lang), 'applications.detail.object_photos'),
      '${imageKeys.length} ${tr(Locale(lang), 'applications.unit.pcs')}',
    );
  }
  if (kadastrKeys.isNotEmpty) {
    add(
      files,
      tr(Locale(lang), 'applications.detail.cadastre_docs'),
      '${kadastrKeys.length} ${tr(Locale(lang), 'applications.unit.pcs')}',
    );
  }
  if (files.isNotEmpty) {
    sections.add((
      tr(Locale(lang), 'applications.detail.section_files'),
      files,
    ));
  }

  return sections;
}

/// AI Baholash arizasiga biriktirilgan teksturali 3D (USDZ) skanni ko‘rsatadi:
/// bosilganda `/ai-valuations/{id}/scan` dan auth bilan yuklab oladi (progress
/// bilan) va iOS QuickLook (AR) orqali ochadi.
class _AiScanCard extends StatefulWidget {
  const _AiScanCard({required this.jobId});
  final int jobId;

  @override
  State<_AiScanCard> createState() => _AiScanCardState();
}

class _AiScanCardState extends State<_AiScanCard> {
  bool _loading = false;
  double? _progress; // 0..1 while downloading; null if unknown/idle

  Future<void> _onTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final filePath = await _ensureResultCached(
        jobId: widget.jobId,
        // GLB (asosiy format, yuqori sifat) yuklaymiz. openScanModel uni
        // single-sided qilib model_viewer'да "dollhouse" ko'rsatadi: kameraga
        // qaragan devor ko'rinmas, xona ichi ko'rinadi. Eski USDZ-only ariza
        // bo'lsa → QuickLook (openScanModel kontent bo'yicha tanlaydi).
        downloadUrl: '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/scan',
        format: 'glb',
        prefix: 'aival',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = total > 0 ? received / total : null);
        },
      );
      if (!mounted) return;
      await openScanModel(context, filePath);
    } on HttpException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${tr(localeNotifier.value, 'applications.error')}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return InkWell(
      onTap: hapticTap(_onTap),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ColorTokens.iconBg(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        value: _progress,
                        color: const Color(0xFF03B54F),
                      ),
                    )
                  : SvgPicture.asset(
                      'assets/icons/chart-scatter-3d.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        ColorTokens.secondaryText(context),
                        BlendMode.srcIn,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(Locale(lang), 'applications.detail.scan_3d'),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: ColorTokens.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _loading
                        ? tr(Locale(lang), 'applications.detail.downloading')
                        : tr(Locale(lang), 'applications.detail.scan_3d_hint'),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 13,
                      color: ColorTokens.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: ColorTokens.secondaryText(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skan rasmlari galereyasi — ariza detalida `scan_files['frames']` kalitlaridan
/// gorizontal thumbnaillar. Har rasm `GET /ai-valuations/{id}/scan-file?key=…`
/// dan auth header bilan yuklanadi. Bosilganda to'liq ekran ko'ruvchi (pager).
/// Rasm yo'q (eski ariza) yoki login yo'q bo'lsa — hech narsa ko'rsatmaydi.
class _AiScanFramesGallery extends StatefulWidget {
  const _AiScanFramesGallery({required this.jobId});
  final int jobId;

  @override
  State<_AiScanFramesGallery> createState() => _AiScanFramesGalleryState();
}

class _AiScanFramesGalleryState extends State<_AiScanFramesGallery> {
  bool _loading = true;
  String? _token;
  List<String> _frames = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final svc = AiValuationJobService();
    try {
      final snap = await svc.get(widget.jobId, token: token);
      final frames =
          (snap.scanFiles?['frames'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[];
      if (!mounted) return;
      setState(() {
        _token = token;
        _frames = frames;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      svc.dispose();
    }
  }

  String _url(String key) =>
      '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/scan-file'
      '?key=${Uri.encodeQueryComponent(key)}';

  Map<String, String> get _headers => {'Authorization': 'Bearer $_token'};

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FramesViewerPage(
          urls: _frames.map(_url).toList(growable: false),
          headers: _headers,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _frames.isEmpty) return const SizedBox.shrink();
    final lang = Localizations.localeOf(context).languageCode;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 18,
                  color: ColorTokens.secondaryText(context),
                ),
                const SizedBox(width: 8),
                Text(
                  '${tr(Locale(lang), 'applications.detail.scan_photos')} (${_frames.length})',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: ColorTokens.primaryText(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _frames.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: hapticTap(() => _openViewer(i)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _url(_frames[i]),
                      headers: _headers,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : Container(
                              width: 96,
                              height: 96,
                              color: ColorTokens.iconBg(context),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                      errorBuilder: (context, _, _) => Container(
                        width: 96,
                        height: 96,
                        color: ColorTokens.iconBg(context),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: ColorTokens.secondaryText(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// To'liq ekran rasm ko'ruvchi — frames galereyasi uchun (swipe + zoom).
class _FramesViewerPage extends StatefulWidget {
  const _FramesViewerPage({
    required this.urls,
    required this.headers,
    required this.initialIndex,
  });

  final List<String> urls;
  final Map<String, String> headers;
  final int initialIndex;

  @override
  State<_FramesViewerPage> createState() => _FramesViewerPageState();
}

class _FramesViewerPageState extends State<_FramesViewerPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    widget.urls[i],
                    headers: widget.headers,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                    errorBuilder: (context, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: hapticTap(() => Navigator.of(context).maybePop()),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Text(
                '${_index + 1} / ${widget.urls.length}',
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ColorTokens.outline(context), width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ColorTokens.iconBg(context),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/icons/application-ready.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(
                ColorTokens.secondaryText(context),
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(localeNotifier.value, 'applications.detail.k3d_report_title'),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                    color: ColorTokens.primaryText(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '3.1 MB',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    height: 1.3,
                    color: ColorTokens.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          _MiniPillButton(
            label: tr(Localizations.localeOf(context), 'applications.detail.download'),
            fg: const Color(0xFF03B54F),
            bg: isDark
                ? const Color(0xFF03B54F).withValues(alpha: 0.18)
                : const Color(0xFFD7F3E3),
            iconAsset: 'assets/icons/download.svg',
          ),
        ],
      ),
    );
  }
}

/// Baholash guruhi (estimate group) xulosasi — egasi bilan bog'langач yozilgan
/// baho sababi va izoh. "Shown to the end user" — ariza detalida ko'rsatiladi.
class _EstimatorCard extends StatelessWidget {
  const _EstimatorCard({this.comment, this.cause});

  final String? comment;
  final String? cause;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final c = comment?.trim() ?? '';
    final cz = cause?.trim() ?? '';

    Widget block(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w400,
            fontSize: 12,
            height: 1.3,
            color: ColorTokens.secondaryText(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.35,
            color: ColorTokens.primaryText(context),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ColorTokens.outline(context), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(Locale(lang), 'applications.detail.specialist_conclusion'),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.3,
              color: ColorTokens.primaryText(context),
            ),
          ),
          if (cz.isNotEmpty) ...[
            const SizedBox(height: 12),
            block(tr(Locale(lang), 'applications.detail.cause_label'), cz),
          ],
          if (c.isNotEmpty) ...[
            const SizedBox(height: 12),
            block(tr(Locale(lang), 'applications.detail.comment_label'), c),
          ],
        ],
      ),
    );
  }
}

/// Yakuniy baholash hisoboti (Xulosa, PDF) yuklab olish kartasi — ariza
/// COMPLETED bo'lganda. `/ai-valuations/{id}/report` dan auth bilan (bayt-aniq
/// progress) yuklab oladi va tizim "ulashish/saqlash" oynasi orqali ochadi.
class _AiXulosaCard extends StatefulWidget {
  const _AiXulosaCard({required this.jobId});
  final int jobId;

  @override
  State<_AiXulosaCard> createState() => _AiXulosaCardState();
}

class _AiXulosaCardState extends State<_AiXulosaCard> {
  bool _loading = false;
  double? _progress;
  int _total = 0;

  String _fmtBytes(int n) {
    if (n <= 0) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static const String _shareName = 'Baholash_Xulosa';

  Future<void> _run(Future<void> Function(String path) action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final path = await _ensureResultCached(
        jobId: widget.jobId,
        downloadUrl:
            '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/report',
        format: 'pdf',
        prefix: 'xulosa',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _total = total;
            _progress = total > 0 ? received / total : null;
          });
        },
      );
      if (!mounted) return;
      await action(path);
    } on HttpException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${tr(localeNotifier.value, 'applications.error')}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
          _total = 0;
        });
      }
    }
  }

  // Tap the card → view in-app.
  void _open() => _run((path) async {
    final lang = localeNotifier.value.languageCode;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerScreen(
          filePath: path,
          title: '${tr(Locale(lang), 'applications.detail.report_file')} #${widget.jobId}',
          shareName: '${_shareName}_${widget.jobId}.pdf',
        ),
      ),
    );
  });

  // Tap "Yuklash" → download / save / share.
  void _download() => _run((path) async {
    await Share.shareXFiles([
      XFile(
        path,
        mimeType: 'application/pdf',
        name: '${_shareName}_${widget.jobId}.pdf',
      ),
    ], sharePositionOrigin: _shareOrigin(context));
  });

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final subtitle = _loading
        ? (_progress != null
              ? '${(_progress! * 100).toStringAsFixed(0)}%'
              : (_total > 0 ? _fmtBytes(_total) : '…'))
        : 'PDF';
    return InkWell(
      onTap: hapticTap(_loading ? null : _open),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ColorTokens.iconBg(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/application-ready.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  ColorTokens.secondaryText(context),
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr(Locale(lang), 'applications.detail.report_file')} #${widget.jobId}',
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.3,
                      color: ColorTokens.primaryText(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 1.3,
                      color: ColorTokens.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
            _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _progress,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DownloadIconButton(onTap: _download),
                      const SizedBox(width: 8),
                      _ViewChip(onTap: _open),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

/// Narxlash Orderi — the styled AI valuation order (separate designed PDF).
/// Downloads from `/ai-valuations/{id}/order`. Mirrors `_AiXulosaCard`.
class _AiOrderCard extends StatefulWidget {
  const _AiOrderCard({required this.jobId});
  final int jobId;

  @override
  State<_AiOrderCard> createState() => _AiOrderCardState();
}

class _AiOrderCardState extends State<_AiOrderCard> {
  bool _loading = false;
  double? _progress;

  Future<void> _run(Future<void> Function(String path) action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final path = await _ensureResultCached(
        jobId: widget.jobId,
        downloadUrl: '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/order',
        format: 'pdf',
        prefix: 'order',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = total > 0 ? received / total : null);
        },
      );
      if (!mounted) return;
      await action(path);
    } on HttpException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${tr(localeNotifier.value, 'applications.error')}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
        });
      }
    }
  }

  void _open() => _run((path) async {
    final lang = localeNotifier.value.languageCode;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerScreen(
          filePath: path,
          title: '${tr(Locale(lang), 'applications.detail.order_file')} #${widget.jobId}',
          shareName: 'Narxlash_Malumotnomasi_${widget.jobId}.pdf',
        ),
      ),
    );
  });

  void _download() => _run((path) async {
    await Share.shareXFiles([
      XFile(
        path,
        mimeType: 'application/pdf',
        name: 'Narxlash_Malumotnomasi_${widget.jobId}.pdf',
      ),
    ], sharePositionOrigin: _shareOrigin(context));
  });

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return InkWell(
      onTap: hapticTap(_loading ? null : _open),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ColorTokens.iconBg(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.receipt_long_rounded,
                size: 20,
                color: ColorTokens.secondaryText(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr(Locale(lang), 'applications.detail.order_file')} #${widget.jobId}',
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.3,
                      color: ColorTokens.primaryText(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _loading
                        ? tr(Locale(lang), 'applications.detail.downloading')
                        : tr(Locale(lang), 'applications.detail.order_hint'),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 1.3,
                      color: ColorTokens.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
            _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _progress,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DownloadIconButton(onTap: _download),
                      const SizedBox(width: 8),
                      _ViewChip(onTap: _open),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

/// 3D Kadastr — specialist-delivered conclusion PDF. Mirrors `_AiXulosaCard`
/// but downloads from `/3d-kadastr-jobs/{id}/report`.
class _K3dReportCard extends StatefulWidget {
  const _K3dReportCard({required this.jobId});
  final int jobId;

  @override
  State<_K3dReportCard> createState() => _K3dReportCardState();
}

class _K3dReportCardState extends State<_K3dReportCard> {
  bool _loading = false;
  double? _progress;
  int _total = 0;

  String _fmtBytes(int n) {
    if (n <= 0) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static const String _shareName = '3D_Kadastr_Xulosa';

  Future<void> _run(Future<void> Function(String path) action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final path = await _ensureResultCached(
        jobId: widget.jobId,
        downloadUrl:
            '${ApiConfig.baseUrl}/3d-kadastr-jobs/${widget.jobId}/report',
        format: 'pdf',
        prefix: 'k3dxulosa',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _total = total;
            _progress = total > 0 ? received / total : null;
          });
        },
      );
      if (!mounted) return;
      await action(path);
    } on HttpException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${tr(localeNotifier.value, 'applications.error')}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
          _total = 0;
        });
      }
    }
  }

  void _open() => _run((path) async {
    final lang = localeNotifier.value.languageCode;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerScreen(
          filePath: path,
          title: '${tr(Locale(lang), 'applications.detail.report_file')} #${widget.jobId}',
          shareName: '${_shareName}_${widget.jobId}.pdf',
        ),
      ),
    );
  });

  void _download() => _run((path) async {
    await Share.shareXFiles([
      XFile(
        path,
        mimeType: 'application/pdf',
        name: '${_shareName}_${widget.jobId}.pdf',
      ),
    ], sharePositionOrigin: _shareOrigin(context));
  });

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final subtitle = _loading
        ? (_progress != null
              ? '${(_progress! * 100).toStringAsFixed(0)}%'
              : (_total > 0 ? _fmtBytes(_total) : '…'))
        : 'PDF';
    return InkWell(
      onTap: hapticTap(_loading ? null : _open),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ColorTokens.iconBg(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/application-ready.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  ColorTokens.secondaryText(context),
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr(Locale(lang), 'applications.detail.report_file')} #${widget.jobId}',
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.3,
                      color: ColorTokens.primaryText(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 1.3,
                      color: ColorTokens.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
            _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _progress,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DownloadIconButton(onTap: _download),
                      const SizedBox(width: 8),
                      _ViewChip(onTap: _open),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

/// 3D Kadastr — specialist-delivered 3D model (.glb/.usdz). Mirrors
/// `_AiScanCard` but downloads from `/3d-kadastr-jobs/{id}/model` and uses the
/// known extension to cache + open with the right viewer.
class _K3dModelCard extends StatefulWidget {
  const _K3dModelCard({required this.jobId, this.ext});
  final int jobId;
  final String? ext;

  @override
  State<_K3dModelCard> createState() => _K3dModelCardState();
}

class _K3dModelCardState extends State<_K3dModelCard> {
  bool _loading = false;
  double? _progress;

  Future<void> _onTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final ext = (widget.ext == 'usdz') ? 'usdz' : 'glb';
      final filePath = await _ensureResultCached(
        jobId: widget.jobId,
        downloadUrl:
            '${ApiConfig.baseUrl}/3d-kadastr-jobs/${widget.jobId}/model',
        format: ext,
        prefix: 'k3dmodel',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = total > 0 ? received / total : null);
        },
      );
      if (!mounted) return;
      // Content-aware viewer (GLB → model_viewer_plus, USDZ → QuickLook).
      await openScanModel(context, filePath);
    } on HttpException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${tr(localeNotifier.value, 'applications.error')}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return InkWell(
      onTap: hapticTap(_onTap),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ColorTokens.iconBg(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        value: _progress,
                        color: const Color(0xFF03B54F),
                      ),
                    )
                  : SvgPicture.asset(
                      'assets/icons/chart-scatter-3d.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        ColorTokens.secondaryText(context),
                        BlendMode.srcIn,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(Locale(lang), 'applications.detail.scan_3d'),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: ColorTokens.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _loading
                        ? tr(Locale(lang), 'applications.detail.downloading')
                        : tr(Locale(lang), 'applications.detail.scan_3d_hint'),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 13,
                      color: ColorTokens.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: ColorTokens.secondaryText(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatefulWidget {
  const _ModelCard({required this.item});
  final ApplicationItem item;

  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  bool _loading = false;
  // 0..1 while downloading; null when not active or size unknown.
  double? _progress;
  // Bytes received / total for byte-precise label.
  int _received = 0;
  int _total = 0;

  String _fmtBytes(int n) {
    if (n <= 0) return '0 B';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Photogrammetry job ID — `photo_NNN` formatdan parse qilamiz.
  /// Boshqa application turlari uchun null.
  int? get _photogrammetryJobId {
    final id = widget.item.id;
    if (!id.startsWith('photo_')) return null;
    return int.tryParse(id.substring('photo_'.length));
  }

  Future<void> _onTap() async {
    if (_loading) return;
    final jobId = _photogrammetryJobId;
    if (jobId == null) {
      AppToast.success(context, tr(localeNotifier.value, 'applications.detail.model_unavailable'));
      return;
    }

    setState(() => _loading = true);
    try {
      // 1. Job holatini tekshirish — completed bo'lishi shart
      final api = PhotogrammetryApiService();
      final job = await api.getJob(jobId);

      if (!job.isCompleted) {
        if (!mounted) return;
        final locale = localeNotifier.value;
        AppToast.success(
          context,
          job.status == 'failed'
              ? '${tr(locale, 'applications.detail.model_build_failed')}: ${job.errorMessage ?? tr(locale, 'applications.detail.error_word')}'
              : tr(locale, 'applications.detail.model_not_ready')
                    .replaceFirst('{status}', job.status),
        );
        return;
      }
      if (job.downloadUrl == null) {
        if (!mounted) return;
        AppToast.error(context, tr(localeNotifier.value, 'applications.detail.download_url_missing'));
        return;
      }

      // 2. Faylni cache'dan olish yoki yuklab olish (auth bilan)
      final format = job.resultFormat ?? 'usdz';
      final filePath = await _ensureResultCached(
        jobId: jobId,
        downloadUrl: job.downloadUrl!,
        format: format,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            _progress = total > 0 ? received / total : null;
          });
        },
      );

      // 3. Format'ga qarab viewer'ni tanlash:
      //    - splat → Flutter WebView (Gaussian Splatting, mkkellogg/GS3D)
      //    - usdz  → iOS QuickLook (eski mesh, native AR Quick Look)
      if (!mounted) return;
      if (format == 'splat' || format == 'ksplat') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SplatViewerScreen(
              splatFilePath: filePath,
              title: tr(localeNotifier.value, 'applications.detail.scan_title').replaceFirst('{id}', '$jobId'),
            ),
          ),
        );
      } else {
        await RoomPlanScanner.preview(filePath);
      }
    } on PhotogrammetryApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } on HttpException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${tr(localeNotifier.value, 'applications.error')}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
          _received = 0;
          _total = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return InkWell(
      onTap: hapticTap(_onTap),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColorTokens.outline(context), width: 0.6),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ColorTokens.iconBg(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'assets/icons/chart-scatter-3d.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  ColorTokens.secondaryText(context),
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(Locale(lang), 'applications.detail.model_3d'),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.3,
                      color: ColorTokens.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    !_loading
                        ? tr(Locale(lang), 'applications.detail.roomplan_opens')
                        : _total > 0
                        ? '${tr(Locale(lang), 'applications.detail.downloading')} ${(_progress! * 100).toStringAsFixed(0)}% '
                              '(${_fmtBytes(_received)} / ${_fmtBytes(_total)})'
                        : '${tr(Locale(lang), 'applications.detail.downloading')} ${_fmtBytes(_received)}',
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 1.3,
                      color: ColorTokens.secondaryText(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 4,
                        backgroundColor: ColorTokens.iconBg(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!_loading)
              _MiniPillButton(
                label: tr(Locale(lang), 'applications.detail.view'),
                fg: ColorTokens.primaryText(context),
                bg: ColorTokens.iconBg(context),
                iconAsset: 'assets/icons/chevron-right.svg',
              ),
          ],
        ),
      ),
    );
  }
}

/// Primary "Ko'rish" (view) chip — opens the in-app PDF viewer.
class _ViewChip extends StatelessWidget {
  const _ViewChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Localizations.localeOf(context).languageCode;
    const fg = Color(0xFF03B54F);
    final bg = isDark
        ? const Color(0xFF03B54F).withValues(alpha: 0.18)
        : const Color(0xFFD7F3E3);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10000),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(Locale(lang), 'applications.detail.view'),
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: fg,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.visibility_outlined, size: 17, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small circular download icon button (sits next to the view chip).
class _DownloadIconButton extends StatelessWidget {
  const _DownloadIconButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.iconBg(context),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: SvgPicture.asset(
              'assets/icons/download.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                ColorTokens.secondaryText(context),
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPillButton extends StatelessWidget {
  const _MiniPillButton({
    required this.label,
    required this.fg,
    required this.bg,
    required this.iconAsset,
  });

  final String label;
  final Color fg;
  final Color bg;
  final String iconAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10000),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          SvgPicture.asset(
            iconAsset,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
          ),
        ],
      ),
    );
  }
}

class _PrimaryBlackAction extends StatelessWidget {
  const _PrimaryBlackAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final bg = ColorTokens.primaryText(context);
    final fg = ColorTokens.scaffoldBg(context);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(() {}),
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: fg,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.call_outlined, size: 24, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Green CTA shown on a DRAFT's detail — resumes the wizard at the saved step.
class _ResumeDraftAction extends StatelessWidget {
  const _ResumeDraftAction({required this.label, required this.jobId});

  final String label;
  final int jobId;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(() => resumeAiDraft(context, jobId)),
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.buttonTextBlack,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 22,
                color: AppColors.buttonTextBlack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryGreenAction extends StatefulWidget {
  const _PrimaryGreenAction({required this.label, required this.item});

  final String label;
  final ApplicationItem item;

  @override
  State<_PrimaryGreenAction> createState() => _PrimaryGreenActionState();
}

class _PrimaryGreenActionState extends State<_PrimaryGreenAction> {
  bool _loading = false;

  Future<void> _onTap() async {
    if (_loading) return;
    final id = widget.item.id;
    if (!id.startsWith('photo_')) {
      AppToast.success(context, tr(localeNotifier.value, 'applications.detail.ar_unavailable'));
      return;
    }
    final jobId = int.tryParse(id.substring('photo_'.length));
    if (jobId == null) return;

    setState(() => _loading = true);
    try {
      final api = PhotogrammetryApiService();
      final job = await api.getJob(jobId);
      if (!job.isCompleted || job.downloadUrl == null) {
        if (!mounted) return;
        AppToast.success(context, tr(localeNotifier.value, 'applications.detail.model_not_ready_short'));
        return;
      }
      final format = job.resultFormat ?? 'usdz';
      final filePath = await _ensureResultCached(
        jobId: jobId,
        downloadUrl: job.downloadUrl!,
        format: format,
      );
      if (!mounted) return;
      // Splat format hozircha AR'da ko'rsatilmaydi (Gaussian Splatting AR
      // standart emas). USDZ → QuickLook AR mode, splat → WebView fallback.
      if (format == 'splat' || format == 'ksplat') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SplatViewerScreen(
              splatFilePath: filePath,
              title: tr(localeNotifier.value, 'applications.detail.scan_title').replaceFirst('{id}', '$jobId'),
            ),
          ),
        );
      } else {
        // QuickLook AR rejimda ham ochadi (Object/AR toggle)
        await RoomPlanScanner.preview(filePath);
      }
    } on HttpException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${tr(localeNotifier.value, 'applications.error')}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF00E135),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(_onTap),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _loading
                ? const [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.black,
                      ),
                    ),
                  ]
                : [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SvgPicture.asset(
                      'assets/icons/camera.svg',
                      width: 30,
                      height: 30,
                      colorFilter: const ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

String _formatAt(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year},$hh:$mi';
}
