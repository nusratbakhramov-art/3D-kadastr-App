import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_config.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_http_client.dart';
import '../settings/settings_state.dart';
import '../scans/splat_viewer_screen.dart';
import '../services/api_ai_valuation_job_service.dart';
import '../services/api_photogrammetry_service.dart';
import '../services/data/room_plan_scanner.dart';
import '../services/widgets/segmented_tabs.dart';
import '../services/widgets/schema_answers_view.dart';
import 'application_model.dart';

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
  final dir = await getApplicationDocumentsDirectory();
  final scansDir = Directory('${dir.path}/scans');
  if (!scansDir.existsSync()) scansDir.createSync(recursive: true);
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
      _DetailStrings.downloadError(
        localeNotifier.value.languageCode,
        res.statusCode,
      ),
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

/// Localized strings for the application detail screen. Uzbek = default.
class _DetailStrings {
  const _DetailStrings._();

  static String applications(String lang) => switch (lang) {
    'ru' => 'Заявки',
    'en' => 'Applications',
    _ => 'Arizalar',
  };

  static String applicationStatus(String lang) => switch (lang) {
    'ru' => 'Статус заявки',
    'en' => 'Application status',
    _ => 'Ariza holati',
  };

  static String aboutApplication(String lang) => switch (lang) {
    'ru' => 'О заявке',
    'en' => 'About application',
    _ => 'Ariza haqida',
  };

  static String applicationDetails(String lang) => switch (lang) {
    'ru' => 'Данные заявки',
    'en' => 'Application details',
    _ => 'Ariza maʼlumotlari',
  };

  static String report(String lang) => switch (lang) {
    'ru' => 'Отчёт',
    'en' => 'Report',
    _ => 'Hisobot',
  };

  static String reportFile(String lang) => switch (lang) {
    'ru' => 'Заключение об оценке',
    'en' => 'Valuation report',
    _ => 'Baholash xulosasi',
  };

  static String specialistConclusion(String lang) => switch (lang) {
    'ru' => 'Заключение специалиста',
    'en' => 'Specialist conclusion',
    _ => 'Mutaxassis xulosasi',
  };

  static String commentLabel(String lang) => switch (lang) {
    'ru' => 'Комментарий',
    'en' => 'Comment',
    _ => 'Izoh',
  };

  static String causeLabel(String lang) => switch (lang) {
    'ru' => 'Обоснование оценки',
    'en' => 'Valuation basis',
    _ => 'Baholash sababi',
  };

  static String noData(String lang) => switch (lang) {
    'ru' => 'Данные отсутствуют',
    'en' => 'No data available',
    _ => 'Maʼlumot mavjud emas',
  };

  static String noTimelineYet(String lang) => switch (lang) {
    'ru' => 'Данные о процессе ещё отсутствуют',
    'en' => 'No process information yet',
    _ => 'Jarayon maʼlumotlari hali yoʻq',
  };

  static String contactSpecialist(String lang) => switch (lang) {
    'ru' => 'Связаться со специалистом',
    'en' => 'Contact a specialist',
    _ => 'Mutaxasis bilan bog\'lanish',
  };

  static String viewViaAr(String lang) => switch (lang) {
    'ru' => 'Посмотреть через AR',
    'en' => 'View via AR',
    _ => 'AR orqali ko\'rish',
  };

  static String download(String lang) => switch (lang) {
    'ru' => 'Скачать',
    'en' => 'Download',
    _ => 'Yuklash',
  };

  static String view(String lang) => switch (lang) {
    'ru' => 'Открыть',
    'en' => 'Open',
    _ => 'Ko\'rish',
  };

  static String model3d(String lang) => switch (lang) {
    'ru' => '3D модель',
    'en' => '3D model',
    _ => '3D Model',
  };

  static String roomPlanViewerOpens(String lang) => switch (lang) {
    'ru' => 'Откроется просмотрщик RoomPlan',
    'en' => 'RoomPlan viewer will open',
    _ => 'RoomPlan viewer ochiladi',
  };

  static String downloading(String lang) => switch (lang) {
    'ru' => 'Загрузка…',
    'en' => 'Downloading…',
    _ => 'Yuklab olinmoqda…',
  };

  static String downloadError(String lang, int statusCode) => switch (lang) {
    'ru' => 'Ошибка загрузки ($statusCode)',
    'en' => 'Download error ($statusCode)',
    _ => 'Yuklab olish xatosi ($statusCode)',
  };

  // Timeline step labels.
  static String accepted(String lang) => switch (lang) {
    'ru' => 'Заявка принята',
    'en' => 'Application accepted',
    _ => 'Ariza qabul qilindi',
  };

  static String sentToSystem(String lang) => switch (lang) {
    'ru' => 'Отправлено в систему',
    'en' => 'Sent to system',
    _ => 'Tizimga yuborildi',
  };

  static String assignedSpecialist(String lang) => switch (lang) {
    'ru' => 'Назначен специалист',
    'en' => 'Specialist assigned',
    _ => 'Mutaxassisga tayinlandi',
  };

  static String scanned(String lang) => switch (lang) {
    'ru' => 'Сканировано',
    'en' => 'Scanned',
    _ => 'Skan qilindi',
  };

  static String reportReady(String lang) => switch (lang) {
    'ru' => 'Отчёт готов',
    'en' => 'Report ready',
    _ => 'Hisobot tayyorlandi',
  };
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
                title: _DetailStrings.applications(lang),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 2),
              Text(
                widget.item.serviceLabel,
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
                  _DetailTab.status => _DetailStrings.applicationStatus(lang),
                  _DetailTab.about => _DetailStrings.aboutApplication(lang),
                },
                selected: _tab,
                onChanged: (next) => setState(() => _tab = next),
              ),
              const SizedBox(height: 14),
              if (_tab == _DetailTab.status)
                _StatusTab(steps: steps)
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
  const _StatusTab({required this.steps});

  final List<ApplicationTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineCard(steps: steps),
        const SizedBox(height: 14),
        _PrimaryBlackAction(label: _DetailStrings.contactSpecialist(lang)),
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
              _DetailStrings.noTimelineYet(
                Localizations.localeOf(context).languageCode,
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
    ApplicationTimelineStatus.accepted => _TimelineStyle(
      label: _DetailStrings.accepted(lang),
      icon: Icons.description_outlined,
      bg: const Color(0xFF18B4E8),
    ),
    ApplicationTimelineStatus.sentToSystem => _TimelineStyle(
      label: _DetailStrings.sentToSystem(lang),
      icon: Icons.send_rounded,
      bg: const Color(0xFF6A16F6),
    ),
    ApplicationTimelineStatus.assignedSpecialist => _TimelineStyle(
      label: _DetailStrings.assignedSpecialist(lang),
      icon: Icons.badge_outlined,
      bg: const Color(0xFFFF9800),
    ),
    ApplicationTimelineStatus.scanned => _TimelineStyle(
      label: _DetailStrings.scanned(lang),
      icon: Icons.crop_free_rounded,
      bg: const Color(0xFF03C050),
    ),
    ApplicationTimelineStatus.reportReady => _TimelineStyle(
      label: _DetailStrings.reportReady(lang),
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
              _DetailStrings.noData(lang),
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
          (item.hasDeliverable || item.aiReportJobId != null)
              ? _DetailStrings.report(lang)
              : _DetailStrings.applicationDetails(lang),
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
        // Dinamik forma (TZ) arizalari — backend sxemasi bo'yicha to'liq
        // (barcha to'ldirilgan maydonlar, bo'limga ajratilgan). Sxema yuklanmasa
        // eski tekis ro'yxatga qaytadi.
        else if (item.formKey != null && (item.formPayload?.isNotEmpty ?? false))
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
        ],
        // AI Baholash arizasiga biriktirilgan teksturali 3D (USDZ) skan —
        // har qanday statusda (skan submit paytida yuklanadi). "3D Kadastr"
        // ariza detali bilan bir xil ko‘rinish: "3D model → Ochish" karta +
        // pastda "AR orqali ko‘rish" yashil tugmasi.
        if (item.aiScanJobId != null) ...[
          const SizedBox(height: 14),
          _AiModelCard(jobId: item.aiScanJobId!),
          const SizedBox(height: 18),
          _AiArAction(jobId: item.aiScanJobId!),
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
            label: _DetailStrings.viewViaAr(lang),
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
  AiJobSnapshot? _snap;
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
      final res = await client
          .get(Uri.parse('${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}'));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _snap = AiJobSnapshot.fromJson(json);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Text(
              sections[i].$1,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: ColorTokens.primaryText(context),
              ),
            ),
          ),
          _flatRowsCard(context, lang, sections[i].$2),
        ],
        if (summary != null && summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Text(
              _aiLbl(lang, 'AI izoh', 'Комментарий AI', 'AI summary'),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: ColorTokens.primaryText(context),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ColorTokens.cardBg(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: ColorTokens.outline(context), width: 0.6),
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

/// Localized label picker (uz default).
String _aiLbl(String lang, String uz, String ru, String en) => switch (lang) {
      'ru' => ru,
      'en' => en,
      _ => uz,
    };

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
  add(prop, _aiLbl(lang, 'Kadastr raqami', 'Кадастровый номер', 'Cadastre no.'),
      str(kad['cadastre_number']));
  add(prop, _aiLbl(lang, 'Manzil', 'Адрес', 'Address'),
      str(kad['address']) ?? str(loc['address']));
  add(prop, _aiLbl(lang, 'Obyekt turi', 'Тип объекта', 'Object type'),
      str(kad['object_type_hint']));
  add(prop, _aiLbl(lang, 'Umumiy maydon', 'Общая площадь', 'Total area'),
      kad['total_area'] != null ? '${kad['total_area']} m²' : null);
  add(prop, _aiLbl(lang, 'Yashash maydoni', 'Жилая площадь', 'Living area'),
      kad['living_area'] != null ? '${kad['living_area']} m²' : null);
  final floor = str(req['floor']);
  if (floor != null) {
    final total = str(req['total_floors']);
    add(prop, _aiLbl(lang, 'Qavat', 'Этаж', 'Floor'),
        total != null ? '$floor / $total' : floor);
  }
  if (kad['cadastre_value'] is num) {
    add(prop, _aiLbl(lang, 'Kadastr qiymati', 'Кадастровая стоимость',
        'Cadastre value'), _aiMoney(kad['cadastre_value'] as num));
  }
  if (prop.isNotEmpty) {
    sections.add((_aiLbl(lang, 'Obyekt', 'Объект', 'Property'), prop));
  }

  // ── Buyurtmachi ─────────────────────────────────────────────────────
  final cl = <(String, String)>[];
  add(cl, _aiLbl(lang, 'Ism', 'Имя', 'Name'), str(client['name']));
  add(cl, _aiLbl(lang, 'Telefon', 'Телефон', 'Phone'), str(client['phone']));
  add(cl, 'STIR / JSHSHIR', str(client['stir']));
  add(cl, 'Email', str(client['email']));
  if (cl.isNotEmpty) {
    sections.add((_aiLbl(lang, 'Buyurtmachi', 'Заказчик', 'Client'), cl));
  }

  // ── Joylashuv ───────────────────────────────────────────────────────
  final lc = <(String, String)>[];
  if (loc['lat'] != null && loc['lng'] != null) {
    add(lc, _aiLbl(lang, 'Koordinatalar', 'Координаты', 'Coordinates'),
        '${loc['lat']}, ${loc['lng']}');
  }
  add(lc, _aiLbl(lang, 'Maqsad', 'Цель', 'Purpose'), str(req['purpose']));
  if (lc.isNotEmpty) {
    sections.add((_aiLbl(lang, 'Joylashuv', 'Локация', 'Location'), lc));
  }

  // ── Xonalar ─────────────────────────────────────────────────────────
  final rm = <(String, String)>[];
  for (final r in rooms) {
    if (r is! Map) continue;
    final m = r.cast<String, dynamic>();
    final name = str(m['name']) ?? str(m['kind']) ??
        _aiLbl(lang, 'Xona', 'Помещение', 'Room');
    final parts = <String>[];
    if (m['count'] != null) {
      parts.add('${m['count']} ${_aiLbl(lang, 'ta', 'шт', 'pcs')}');
    }
    if (m['area'] != null) parts.add('${m['area']} m²');
    rm.add((name, parts.isEmpty ? '—' : parts.join(' · ')));
  }
  if (rm.isNotEmpty) {
    sections.add((_aiLbl(lang, 'Xonalar', 'Помещения', 'Rooms'), rm));
  }

  // ── Natija ──────────────────────────────────────────────────────────
  final rs = <(String, String)>[];
  if (res['estimated_value'] is num) {
    add(rs, _aiLbl(lang, 'Taxminiy qiymat', 'Оценочная стоимость',
        'Estimated value'), _aiMoney(res['estimated_value'] as num));
  }
  final ppsq = res['price_per_sqm'] ?? res['value_per_sqm'];
  if (ppsq is num) {
    add(rs, _aiLbl(lang, '1 m² narxi', 'Цена за 1 м²', 'Price per m²'),
        _aiMoney(ppsq));
  }
  final conf = res['confidence'];
  if (conf is num) {
    add(rs, _aiLbl(lang, 'Ishonchlilik', 'Достоверность', 'Confidence'),
        conf <= 1 ? '${(conf * 100).round()}%' : conf.toString());
  }
  if (snap.nearbyListingsCount > 0) {
    add(rs, _aiLbl(lang, 'Taqqoslangan e\'lonlar', 'Сравнимые объявления',
        'Comparables'), '${snap.nearbyListingsCount}');
  }
  if (snap.nearbyPoisCount > 0) {
    add(rs, _aiLbl(lang, 'Atrofdagi obyektlar', 'Объекты рядом', 'Nearby POIs'),
        '${snap.nearbyPoisCount}');
  }
  if (rs.isNotEmpty) {
    sections.add((_aiLbl(lang, 'Natija', 'Результат', 'Result'), rs));
  }

  return sections;
}

/// AI Baholash arizasiga biriktirilgan teksturali 3D (USDZ) skanni "3D Kadastr"
/// ariza detalidagi "3D model" kartasi bilan bir xil ko‘rinishda ko‘rsatadi:
/// bosilganda `/ai-valuations/{id}/scan` dan auth bilan yuklab oladi (bayt-aniq
/// progress bilan) va iOS QuickLook (RoomPlan/AR) orqali ochadi.
class _AiModelCard extends StatefulWidget {
  const _AiModelCard({required this.jobId});
  final int jobId;

  @override
  State<_AiModelCard> createState() => _AiModelCardState();
}

class _AiModelCardState extends State<_AiModelCard> {
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

  Future<void> _onTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final filePath = await _ensureResultCached(
        jobId: widget.jobId,
        downloadUrl: '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/scan',
        format: 'usdz',
        prefix: 'aival',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            _progress = total > 0 ? received / total : null;
          });
        },
      );
      if (!mounted) return;
      await RoomPlanScanner.preview(filePath);
    } on HttpException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, switch (localeNotifier.value.languageCode) {
        'ru' => 'Ошибка: $e',
        'en' => 'Error: $e',
        _ => 'Xato: $e',
      });
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
      onTap: _onTap,
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
                    _DetailStrings.model3d(lang),
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
                        ? _DetailStrings.roomPlanViewerOpens(lang)
                        : _total > 0
                            ? '${_DetailStrings.downloading(lang)} ${(_progress! * 100).toStringAsFixed(0)}% '
                                '(${_fmtBytes(_received)} / ${_fmtBytes(_total)})'
                            : '${_DetailStrings.downloading(lang)} ${_fmtBytes(_received)}',
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
                label: _DetailStrings.view(lang),
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

/// AI Baholash 3D skanini AR (QuickLook) rejimida ochadigan asosiy yashil tugma —
/// "3D Kadastr" ariza detalidagi "AR orqali ko‘rish" tugmasi bilan bir xil.
class _AiArAction extends StatefulWidget {
  const _AiArAction({required this.jobId});
  final int jobId;

  @override
  State<_AiArAction> createState() => _AiArActionState();
}

class _AiArActionState extends State<_AiArAction> {
  bool _loading = false;

  Future<void> _onTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final filePath = await _ensureResultCached(
        jobId: widget.jobId,
        downloadUrl: '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/scan',
        format: 'usdz',
        prefix: 'aival',
      );
      if (!mounted) return;
      await RoomPlanScanner.preview(filePath);
    } on HttpException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, switch (localeNotifier.value.languageCode) {
        'ru' => 'Ошибка: $e',
        'en' => 'Error: $e',
        _ => 'Xato: $e',
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return Material(
      color: const Color(0xFF00E135),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _onTap,
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
                      _DetailStrings.viewViaAr(lang),
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
                  '3D_Kadastr_Xulosa.pdf',
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
            label: _DetailStrings.download(
              Localizations.localeOf(context).languageCode,
            ),
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
            _DetailStrings.specialistConclusion(lang),
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
            block(_DetailStrings.causeLabel(lang), cz),
          ],
          if (c.isNotEmpty) ...[
            const SizedBox(height: 12),
            block(_DetailStrings.commentLabel(lang), c),
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

  Future<void> _onTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final filePath = await _ensureResultCached(
        jobId: widget.jobId,
        downloadUrl: '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/report',
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
      await Share.shareXFiles(
        [
          XFile(
            filePath,
            mimeType: 'application/pdf',
            name: 'Baholash_Xulosa_${widget.jobId}.pdf',
          ),
        ],
      );
    } on HttpException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, switch (localeNotifier.value.languageCode) {
        'ru' => 'Ошибка: $e',
        'en' => 'Error: $e',
        _ => 'Xato: $e',
      });
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Localizations.localeOf(context).languageCode;
    final subtitle = _loading
        ? (_progress != null
            ? '${(_progress! * 100).toStringAsFixed(0)}%'
            : (_total > 0 ? _fmtBytes(_total) : '…'))
        : 'PDF';
    return InkWell(
      onTap: _loading ? null : _onTap,
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
                    '${_DetailStrings.reportFile(lang)} #${widget.jobId}',
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
                : _MiniPillButton(
                    label: _DetailStrings.download(lang),
                    fg: const Color(0xFF03B54F),
                    bg: isDark
                        ? const Color(0xFF03B54F).withValues(alpha: 0.18)
                        : const Color(0xFFD7F3E3),
                    iconAsset: 'assets/icons/download.svg',
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
      AppToast.success(context, switch (localeNotifier.value.languageCode) {
        'ru' => '3D-модель недоступна для этого типа заявки',
        'en' => '3D model is not available for this application type',
        _ => '3D model bu ariza turida mavjud emas',
      });
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
              ? switch (locale.languageCode) {
                  'ru' => 'Не удалось построить 3D-модель: ${job.errorMessage ?? 'ошибка'}',
                  'en' => 'Failed to build 3D model: ${job.errorMessage ?? 'error'}',
                  _ => '3D model qurib bo\'lmadi: ${job.errorMessage ?? 'xato'}',
                }
              : switch (locale.languageCode) {
                  'ru' => '3D-модель ещё не готова (${job.status}). Пожалуйста, подождите.',
                  'en' => '3D model is not ready yet (${job.status}). Please wait.',
                  _ => '3D model hali tayyor emas (${job.status}). Iltimos, kuting.',
                },
        );
        return;
      }
      if (job.downloadUrl == null) {
        if (!mounted) return;
        AppToast.error(context, switch (localeNotifier.value.languageCode) {
          'ru' => 'URL для загрузки не получен',
          'en' => 'Download URL not received',
          _ => 'Download URL kelmadi',
        });
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
              title: '3D skan #$jobId',
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
      AppToast.error(context, switch (localeNotifier.value.languageCode) {
        'ru' => 'Ошибка: $e',
        'en' => 'Error: $e',
        _ => 'Xato: $e',
      });
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
      onTap: _onTap,
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
                  _DetailStrings.model3d(lang),
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
                      ? _DetailStrings.roomPlanViewerOpens(lang)
                      : _total > 0
                          ? '${_DetailStrings.downloading(lang)} ${(_progress! * 100).toStringAsFixed(0)}% '
                              '(${_fmtBytes(_received)} / ${_fmtBytes(_total)})'
                          : '${_DetailStrings.downloading(lang)} ${_fmtBytes(_received)}',
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
              label: _DetailStrings.view(lang),
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
        onTap: () {},
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
      AppToast.success(context, switch (localeNotifier.value.languageCode) {
        'ru' => 'AR-просмотр недоступен для этого типа заявки',
        'en' => 'AR view is not available for this application type',
        _ => 'AR ko\'rish bu ariza turida mavjud emas',
      });
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
        AppToast.success(context, switch (localeNotifier.value.languageCode) {
          'ru' => '3D-модель ещё не готова',
          'en' => '3D model is not ready yet',
          _ => '3D model hali tayyor emas',
        });
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
              title: '3D skan #$jobId',
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
      AppToast.error(context, switch (localeNotifier.value.languageCode) {
        'ru' => 'Ошибка: $e',
        'en' => 'Error: $e',
        _ => 'Xato: $e',
      });
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
        onTap: _onTap,
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
