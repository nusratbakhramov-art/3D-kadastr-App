import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/api_config.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_http_client.dart';
import '../auth/auth_storage.dart';
import '../settings/settings_state.dart';
import '../scans/splat_viewer_screen.dart';
import '../services/api_ai_valuation_job_service.dart';
import '../services/api_photogrammetry_service.dart';
import '../services/data/model_preview.dart';
import '../services/data/room_plan_scanner.dart';
import '../services/widgets/segmented_tabs.dart';
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

  static String scan3d(String lang) => switch (lang) {
    'ru' => '3D скан объекта',
    'en' => 'Object 3D scan',
    _ => 'Obyekt 3D skani',
  };

  static String scan3dHint(String lang) => switch (lang) {
    'ru' => 'Нажмите, чтобы открыть в AR',
    'en' => 'Tap to view in AR',
    _ => 'AR’da ko‘rish uchun bosing',
  };

  static String scanPhotos(String lang) => switch (lang) {
    'ru' => 'Снимки скана',
    'en' => 'Scan photos',
    _ => 'Skan rasmlari',
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
          item.hasDeliverable
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
        Container(
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
        ),
        // AI Baholash arizasiga biriktirilgan teksturali 3D (USDZ) skan —
        // har qanday statusda (skan submit paytida yuklanadi). Foydalanuvchi
        // AR’da ko‘rish uchun bosadi.
        if (item.aiScanJobId != null) ...[
          const SizedBox(height: 14),
          _AiScanCard(jobId: item.aiScanJobId!),
          // Skan paytida olingan rasmlar (frames) — scan_files'dan. Eski
          // arizalarda rasm bo'lmasa, kartani o'zi yashiradi.
          _AiScanFramesGallery(jobId: item.aiScanJobId!),
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
        downloadUrl: '${ApiConfig.baseUrl}/ai-valuations/${widget.jobId}/scan',
        format: 'glb',
        prefix: 'aival',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = total > 0 ? received / total : null);
        },
      );
      if (!mounted) return;
      // Backend GLB (yangi asosiy format) yoki eski USDZ qaytaradi — kontent
      // bo'yicha to'g'ri viewer tanlaymiz: GLB → model_viewer_plus, USDZ →
      // QuickLook. (openScanModel — resume ekrani bilan bir xil, markazlashgan.)
      await openScanModel(context, filePath);
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
                    _DetailStrings.scan3d(lang),
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
                        ? _DetailStrings.downloading(lang)
                        : _DetailStrings.scan3dHint(lang),
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
            Icon(Icons.chevron_right_rounded,
                color: ColorTokens.secondaryText(context)),
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
      final frames = (snap.scanFiles?['frames'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
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
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _FramesViewerPage(
        urls: _frames.map(_url).toList(growable: false),
        headers: _headers,
        initialIndex: index,
      ),
    ));
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
                Icon(Icons.photo_library_outlined,
                    size: 18, color: ColorTokens.secondaryText(context)),
                const SizedBox(width: 8),
                Text(
                  '${_DetailStrings.scanPhotos(lang)} (${_frames.length})',
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
                  onTap: () => _openViewer(i),
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
                                        strokeWidth: 2),
                                  ),
                                ),
                      errorBuilder: (context, _, _) => Container(
                        width: 96,
                        height: 96,
                        color: ColorTokens.iconBg(context),
                        alignment: Alignment.center,
                        child: Icon(Icons.broken_image_outlined,
                            color: ColorTokens.secondaryText(context)),
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
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
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
                                    color: Colors.white)),
                    errorBuilder: (context, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
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
