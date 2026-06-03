import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../theme/color_tokens.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_toast.dart';
import '../auth/auth_http_client.dart';
import '../scans/splat_viewer_screen.dart';
import '../services/api_photogrammetry_service.dart';
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
  void Function(int received, int total)? onProgress,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final scansDir = Directory('${dir.path}/scans');
  if (!scansDir.existsSync()) scansDir.createSync(recursive: true);
  final filePath = '${scansDir.path}/photo_$jobId.$format';
  final file = File(filePath);
  if (await file.exists() && await file.length() > 0) {
    onProgress?.call(await file.length(), await file.length());
    return filePath;
  }

  final client = AuthHttpClient();
  final req = http.Request('GET', Uri.parse(downloadUrl));
  final res = await client.send(req);
  if (res.statusCode != 200) {
    throw HttpException('Yuklab olish xatosi (${res.statusCode})');
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
    final l = Localizations.localeOf(context);
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
                title: _DetailStrings.applications(l),
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
                  _DetailTab.status => _DetailStrings.tabStatus(l),
                  _DetailTab.about => _DetailStrings.tabAbout(l),
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
    final l = Localizations.localeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineCard(steps: steps),
        const SizedBox(height: 14),
        _PrimaryBlackAction(label: _DetailStrings.contactSpecialist(l)),
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.steps});

  final List<ApplicationTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
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
              _DetailStrings.timelineEmpty(l),
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
    final l = Localizations.localeOf(context);
    final style = _TimelineStyle.fromStatus(step.status, l);
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
    Locale l,
  ) =>
      switch (status) {
        ApplicationTimelineStatus.accepted => _TimelineStyle(
          label: switch (l.languageCode) {
            'ru' => 'Заявка принята',
            'en' => 'Application accepted',
            _ => 'Ariza qabul qilindi',
          },
          icon: Icons.description_outlined,
          bg: const Color(0xFF18B4E8),
        ),
        ApplicationTimelineStatus.sentToSystem => _TimelineStyle(
          label: switch (l.languageCode) {
            'ru' => 'Отправлено в систему',
            'en' => 'Sent to the system',
            _ => 'Tizimga yuborildi',
          },
          icon: Icons.send_rounded,
          bg: const Color(0xFF6A16F6),
        ),
        ApplicationTimelineStatus.assignedSpecialist => _TimelineStyle(
          label: switch (l.languageCode) {
            'ru' => 'Назначен специалист',
            'en' => 'Assigned to a specialist',
            _ => 'Mutaxassisga tayinlandi',
          },
          icon: Icons.badge_outlined,
          bg: const Color(0xFFFF9800),
        ),
        ApplicationTimelineStatus.scanned => _TimelineStyle(
          label: switch (l.languageCode) {
            'ru' => 'Отсканировано',
            'en' => 'Scanned',
            _ => 'Skan qilindi',
          },
          icon: Icons.crop_free_rounded,
          bg: const Color(0xFF03C050),
        ),
        ApplicationTimelineStatus.reportReady => _TimelineStyle(
          label: switch (l.languageCode) {
            'ru' => 'Отчёт готов',
            'en' => 'Report ready',
            _ => 'Hisobot tayyorlandi',
          },
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
    final l = Localizations.localeOf(context);
    final rows = item.detailRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item.hasDeliverable
              ? _DetailStrings.report(l)
              : _DetailStrings.applicationData(l),
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
                    _DetailStrings.noData(l),
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
            label: _DetailStrings.viewInAr(l),
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

class _FileCard extends StatelessWidget {
  const _FileCard();

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
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
            label: _DetailStrings.download(l),
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
    final l = Localizations.localeOf(context);
    final jobId = _photogrammetryJobId;
    if (jobId == null) {
      AppToast.success(context, _DetailStrings.model3dUnavailable(l));
      return;
    }

    setState(() => _loading = true);
    try {
      // 1. Job holatini tekshirish — completed bo'lishi shart
      final api = PhotogrammetryApiService();
      final job = await api.getJob(jobId);

      if (!job.isCompleted) {
        if (!mounted) return;
        AppToast.success(
          context,
          job.status == 'failed'
              ? _DetailStrings.model3dFailed(l, job.errorMessage)
              : _DetailStrings.model3dNotReadyYet(l, job.status),
        );
        return;
      }
      if (job.downloadUrl == null) {
        if (!mounted) return;
        AppToast.error(context, _DetailStrings.downloadUrlMissing(l));
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
              title: _DetailStrings.scan3dTitle(l, jobId),
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
      AppToast.error(context, _DetailStrings.errorWith(l, '$e'));
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
    final l = Localizations.localeOf(context);
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
                  '3D Model',
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
                      ? _DetailStrings.roomPlanWillOpen(l)
                      : _total > 0
                          ? '${_DetailStrings.downloading(l)} ${(_progress! * 100).toStringAsFixed(0)}% '
                              '(${_fmtBytes(_received)} / ${_fmtBytes(_total)})'
                          : '${_DetailStrings.downloading(l)} ${_fmtBytes(_received)}',
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
              label: _DetailStrings.view(l),
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
    final l = Localizations.localeOf(context);
    final id = widget.item.id;
    if (!id.startsWith('photo_')) {
      AppToast.success(context, _DetailStrings.arUnavailable(l));
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
        AppToast.success(context, _DetailStrings.model3dNotReady(l));
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
              title: _DetailStrings.scan3dTitle(l, jobId),
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
      AppToast.error(context, _DetailStrings.errorWith(l, '$e'));
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

class _DetailStrings {
  const _DetailStrings._();

  static String applications(Locale l) => switch (l.languageCode) {
        'ru' => 'Заявки',
        'en' => 'Applications',
        _ => 'Arizalar',
      };

  static String tabStatus(Locale l) => switch (l.languageCode) {
        'ru' => 'Статус заявки',
        'en' => 'Application status',
        _ => 'Ariza holati',
      };

  static String tabAbout(Locale l) => switch (l.languageCode) {
        'ru' => 'О заявке',
        'en' => 'About',
        _ => 'Ariza haqida',
      };

  static String contactSpecialist(Locale l) => switch (l.languageCode) {
        'ru' => 'Связаться со специалистом',
        'en' => 'Contact a specialist',
        _ => "Mutaxasis bilan bog'lanish",
      };

  static String timelineEmpty(Locale l) => switch (l.languageCode) {
        'ru' => 'Данных о процессе пока нет',
        'en' => 'No process information yet',
        _ => 'Jarayon maʼlumotlari hali yoʻq',
      };

  static String report(Locale l) => switch (l.languageCode) {
        'ru' => 'Отчёт',
        'en' => 'Report',
        _ => 'Hisobot',
      };

  static String applicationData(Locale l) => switch (l.languageCode) {
        'ru' => 'Данные заявки',
        'en' => 'Application details',
        _ => 'Ariza maʼlumotlari',
      };

  static String noData(Locale l) => switch (l.languageCode) {
        'ru' => 'Данные отсутствуют',
        'en' => 'No data available',
        _ => 'Maʼlumot mavjud emas',
      };

  static String download(Locale l) => switch (l.languageCode) {
        'ru' => 'Скачать',
        'en' => 'Download',
        _ => 'Yuklash',
      };

  static String view(Locale l) => switch (l.languageCode) {
        'ru' => 'Открыть',
        'en' => 'View',
        _ => "Ko'rish",
      };

  static String viewInAr(Locale l) => switch (l.languageCode) {
        'ru' => 'Посмотреть в AR',
        'en' => 'View in AR',
        _ => "AR orqali ko'rish",
      };

  static String roomPlanWillOpen(Locale l) => switch (l.languageCode) {
        'ru' => 'Откроется просмотрщик RoomPlan',
        'en' => 'RoomPlan viewer will open',
        _ => 'RoomPlan viewer ochiladi',
      };

  static String downloading(Locale l) => switch (l.languageCode) {
        'ru' => 'Загрузка…',
        'en' => 'Downloading…',
        _ => 'Yuklab olinmoqda…',
      };

  static String scan3dTitle(Locale l, int jobId) => switch (l.languageCode) {
        'ru' => '3D-скан #$jobId',
        'en' => '3D scan #$jobId',
        _ => '3D skan #$jobId',
      };

  static String model3dUnavailable(Locale l) => switch (l.languageCode) {
        'ru' => '3D-модель недоступна для этого типа заявки',
        'en' => '3D model is not available for this application type',
        _ => '3D model bu ariza turida mavjud emas',
      };

  static String arUnavailable(Locale l) => switch (l.languageCode) {
        'ru' => 'Просмотр в AR недоступен для этого типа заявки',
        'en' => 'AR view is not available for this application type',
        _ => "AR ko'rish bu ariza turida mavjud emas",
      };

  static String model3dNotReady(Locale l) => switch (l.languageCode) {
        'ru' => '3D-модель ещё не готова',
        'en' => '3D model is not ready yet',
        _ => '3D model hali tayyor emas',
      };

  static String model3dNotReadyYet(Locale l, String status) =>
      switch (l.languageCode) {
        'ru' => '3D-модель ещё не готова ($status). Пожалуйста, подождите.',
        'en' => '3D model is not ready yet ($status). Please wait.',
        _ => '3D model hali tayyor emas ($status). Iltimos, kuting.',
      };

  static String model3dFailed(Locale l, String? error) {
    final reason = error ??
        switch (l.languageCode) {
          'ru' => 'ошибка',
          'en' => 'error',
          _ => 'xato',
        };
    return switch (l.languageCode) {
      'ru' => 'Не удалось построить 3D-модель: $reason',
      'en' => 'Failed to build 3D model: $reason',
      _ => "3D model qurib bo'lmadi: $reason",
    };
  }

  static String downloadUrlMissing(Locale l) => switch (l.languageCode) {
        'ru' => 'Ссылка для скачивания не получена',
        'en' => 'Download URL was not provided',
        _ => 'Download URL kelmadi',
      };

  static String errorWith(Locale l, String details) => switch (l.languageCode) {
        'ru' => 'Ошибка: $details',
        'en' => 'Error: $details',
        _ => 'Xato: $details',
      };
}
