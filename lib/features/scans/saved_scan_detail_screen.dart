import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import '../settings/settings_state.dart';
import 'saved_scan_service.dart';

class SavedScanDetailScreen extends StatefulWidget {
  const SavedScanDetailScreen({required this.scanId, super.key});

  final int scanId;

  @override
  State<SavedScanDetailScreen> createState() => _SavedScanDetailScreenState();
}

class _SavedScanDetailScreenState extends State<SavedScanDetailScreen>
    with
        SingleTickerProviderStateMixin,
        RevealEntryMixin<SavedScanDetailScreen> {
  @override
  int get currentToken => 1;

  final _service = SavedScanService();
  SavedScanItem? _item;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final item = await _service.get(widget.scanId);
    if (mounted) {
      setState(() {
        _item = item;
        _loading = false;
      });
    }
  }

  Future<void> _process() async {
    if (_processing) return;
    final locale = localeNotifier.value;
    setState(() => _processing = true);
    try {
      final result = await _service.process(widget.scanId);
      if (!mounted) return;
      if (result == null) {
        // Foydalanuvchi cancel qildi
        setState(() => _processing = false);
        return;
      }
      AppToast.success(context, _Strings.processDone(locale, result.version));
      await _load();
      setState(() => _processing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      AppToast.error(context, '$e');
    }
  }

  /// Xom LiDAR mesh'ni ko'rish — anchors.bin'dan to'g'ridan-to'g'ri, hech qanday
  /// pipeline'siz (textura/TSDF/clean yo'q). Tez ochiladi, versiya saqlanmaydi.
  Future<void> _viewLidarMesh() async {
    if (_processing) return;
    final locale = localeNotifier.value;
    setState(() => _processing = true);
    try {
      // Native LidarMeshExporter mesh'ni quradi va SceneKit viewer'da ochadi
      // (simulatorда ham ishlaydi). Alohida preview chaqiruvi kerak emas.
      final path = await _service.viewLidarMesh(widget.scanId);
      if (!mounted) return;
      setState(() => _processing = false);
      if (path == null) {
        AppToast.error(context, _Strings.lidarMeshNotFound(locale));
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      AppToast.error(context, '$e');
    }
  }

  Future<void> _viewOutput(SavedScanOutput output) async {
    final locale = localeNotifier.value;
    final path = await _service.outputPath(widget.scanId, output.version);
    if (path == null) {
      if (mounted) AppToast.error(context, _Strings.fileNotFound(locale));
      return;
    }
    await _service.preview(path);
  }

  Future<void> _deleteOutput(SavedScanOutput output) async {
    final locale = localeNotifier.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_Strings.deleteOutputTitle(locale)),
        content: Text(_Strings.deleteOutputPrompt(locale, output.version)),
        actions: [
          TextButton(
            onPressed: hapticTap(() => Navigator.pop(ctx, false)),
            child: Text(_Strings.cancel(locale)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: hapticTap(() => Navigator.pop(ctx, true)),
            child: Text(_Strings.delete(locale)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _service.deleteOutput(widget.scanId, output.version);
    if (ok) {
      await _load();
    } else {
      if (mounted) AppToast.error(context, _Strings.deleteError(locale));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => Scaffold(
        backgroundColor: ColorTokens.scaffoldBg(context),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const AppGlowBackground(),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppReveal(
                      controller: entryController,
                      interval: const Interval(
                        0.0,
                        0.4,
                        curve: Curves.easeOutCubic,
                      ),
                      child: AppHeaderBack(
                        title:
                            _item?.name ??
                            _Strings.scanTitle(locale, widget.scanId),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_item == null)
                      Center(
                        child: Text(
                          _Strings.scanNotFound(locale),
                          style: TextStyle(
                            color: ColorTokens.primaryText(context),
                          ),
                        ),
                      )
                    else ...[
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.1,
                          0.6,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _InfoCard(item: _item!, locale: locale),
                      ),
                      const SizedBox(height: 16),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.2,
                          0.7,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _ProcessButton(
                          item: _item!,
                          locale: locale,
                          processing: _processing,
                          onTap: _process,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.25,
                          0.75,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _ClayButton(
                          locale: locale,
                          processing: _processing,
                          onTap: _viewLidarMesh,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_item!.outputs.isNotEmpty) ...[
                        Text(
                          _Strings.resultsTitle(locale, _item!.outputs.length),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: ColorTokens.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _item!.outputs.length; i++) ...[
                          AppReveal(
                            controller: entryController,
                            interval: Interval(
                              (0.3 + i * 0.05).clamp(0.0, 0.9),
                              (0.7 + i * 0.05).clamp(0.0, 1.0),
                              curve: Curves.easeOutCubic,
                            ),
                            child: _OutputCard(
                              output: _item!.outputs[i],
                              locale: locale,
                              isLatest: i == 0,
                              onView: () => _viewOutput(_item!.outputs[i]),
                              onDelete: () => _deleteOutput(_item!.outputs[i]),
                            ),
                          ),
                          if (i != _item!.outputs.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.item, required this.locale});
  final SavedScanItem item;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _Strings.infoTitle(locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          _Row(
            label: _Strings.photoCountLabel(locale),
            value: '${item.photoCount}',
          ),
          _Row(
            label: _Strings.areaLabel(locale),
            value: '${item.areaSqm.toStringAsFixed(2)} m²',
          ),
          _Row(
            label: _Strings.createdLabel(locale),
            value: _formatDate(item.createdAt),
          ),
          _Row(
            label: _Strings.statusLabel(locale),
            value: item.outputs.isEmpty
                ? _Strings.unprocessed(locale)
                : _Strings.outputCount(locale, item.outputs.length),
            valueColor: item.outputs.isEmpty ? Colors.orange : Colors.green,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}, $timeStr';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                color: ColorTokens.secondaryText(context),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: valueColor ?? ColorTokens.primaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessButton extends StatelessWidget {
  const _ProcessButton({
    required this.item,
    required this.locale,
    required this.processing,
    required this.onTap,
  });

  final SavedScanItem item;
  final Locale locale;
  final bool processing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isReprocess = item.outputs.isNotEmpty;
    return Material(
      color: processing
          ? ColorTokens.brandPrimary(context).withValues(alpha: 0.5)
          : ColorTokens.brandPrimary(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: hapticTap(processing ? null : onTap),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (processing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  isReprocess ? Icons.refresh : Icons.auto_fix_high,
                  color: Colors.white,
                  size: 22,
                ),
              const SizedBox(width: 10),
              Text(
                processing
                    ? _Strings.processing(locale)
                    : (isReprocess
                          ? _Strings.reprocess(
                              locale,
                              item.outputs.first.version + 1,
                            )
                          : _Strings.startTexturing(locale)),
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClayButton extends StatelessWidget {
  const _ClayButton({
    required this.locale,
    required this.processing,
    required this.onTap,
  });

  final Locale locale;
  final bool processing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = ColorTokens.brandPrimary(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: hapticTap(processing ? null : onTap),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: brand.withValues(alpha: processing ? 0.25 : 0.6),
              width: 1.4,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.grid_4x4,
                color: brand.withValues(alpha: processing ? 0.5 : 1.0),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                _Strings.viewLidarMesh(locale),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: brand.withValues(alpha: processing ? 0.5 : 1.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutputCard extends StatelessWidget {
  const _OutputCard({
    required this.output,
    required this.locale,
    required this.isLatest,
    required this.onView,
    required this.onDelete,
  });

  final SavedScanOutput output;
  final Locale locale;
  final bool isLatest;
  final VoidCallback onView;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: isLatest
            ? Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: hapticTap(onView),
          onLongPress: onDelete,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isLatest
                        ? Colors.green.withValues(alpha: 0.15)
                        : ColorTokens.iconBg(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.view_in_ar,
                    size: 22,
                    color: isLatest
                        ? Colors.green
                        : ColorTokens.brandPrimary(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'v${output.version}',
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: ColorTokens.primaryText(context),
                            ),
                          ),
                          if (isLatest) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _Strings.latest(locale),
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                          if (output.params['clay'] == '1') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.brown.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'clay',
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                  color: Colors.brown,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDate(output.createdAt)} · ${output.sizeFormatted}',
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 11,
                          color: ColorTokens.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.withValues(alpha: 0.6),
                  onPressed: hapticTap(onDelete),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayOfScan = DateTime(d.year, d.month, d.day);
    final diff = today.difference(dayOfScan).inDays;
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return _Strings.todayAt(locale, timeStr);
    if (diff == 1) return _Strings.yesterdayAt(locale, timeStr);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}, $timeStr';
  }
}

class _Strings {
  static String processDone(Locale l, int version) => _p(
    l,
    'scan.saved_detail.process_done',
    'Qayta ishlash yakunlandi (v$version)',
    'Обработка завершена (v$version)',
    'Processing finished (v$version)',
  );
  static String lidarMeshNotFound(Locale l) => _p(
    l,
    'scan.saved_detail.lidar_mesh_not_found',
    'LiDAR mesh topilmadi',
    'LiDAR mesh не найден',
    'LiDAR mesh not found',
  );
  static String fileNotFound(Locale l) => _p(
    l,
    'common.file_not_found',
    'Fayl topilmadi',
    'Файл не найден',
    'File not found',
  );
  static String deleteOutputTitle(Locale l) => _p(
    l,
    'scan.saved_detail.delete_output_title',
    'Natija o\'chirilsinmi?',
    'Удалить результат?',
    'Delete output?',
  );
  static String deleteOutputPrompt(Locale l, int version) => _p(
    l,
    'scan.saved_detail.delete_output_prompt',
    'v$version ni o\'chirishni tasdiqlaysizmi?',
    'Подтвердить удаление v$version?',
    'Confirm deleting v$version?',
  );
  static String cancel(Locale l) =>
      _p(l, 'common.cancel', 'Bekor qilish', 'Отмена', 'Cancel');
  static String delete(Locale l) =>
      _p(l, 'common.delete', 'O\'chirish', 'Удалить', 'Delete');
  static String deleteError(Locale l) => _p(
    l,
    'common.delete_error',
    'O\'chirishda xatolik',
    'Ошибка удаления',
    'Delete error',
  );
  static String scanTitle(Locale l, int id) => _p(
    l,
    'scan.saved_detail.scan_title',
    'Skan #$id',
    'Скан #$id',
    'Scan #$id',
  );
  static String scanNotFound(Locale l) => _p(
    l,
    'scan.saved_detail.scan_not_found',
    'Skan topilmadi',
    'Скан не найден',
    'Scan not found',
  );
  static String resultsTitle(Locale l, int count) => _p(
    l,
    'scan.saved_detail.results_title',
    'Natijalar ($count)',
    'Результаты ($count)',
    'Results ($count)',
  );
  static String infoTitle(Locale l) => _p(
    l,
    'scan.saved_detail.info_title',
    'Skan ma\'lumotlari',
    'Данные скана',
    'Scan details',
  );
  static String photoCountLabel(Locale l) => _p(
    l,
    'scan.saved_detail.photo_count_label',
    'Foto soni',
    'Количество фото',
    'Photo count',
  );
  static String areaLabel(Locale l) =>
      _p(l, 'common.area', 'Maydon', 'Площадь', 'Area');
  static String createdLabel(Locale l) =>
      _p(l, 'common.created', 'Yaratilgan', 'Создано', 'Created');
  static String statusLabel(Locale l) =>
      _p(l, 'common.status', 'Holat', 'Статус', 'Status');
  static String unprocessed(Locale l) => _p(
    l,
    'scan.saved_detail.unprocessed',
    'Hali qayta ishlanmagan',
    'Ещё не обработан',
    'Not processed yet',
  );
  static String outputCount(Locale l, int count) => _p(
    l,
    'scan.saved_detail.output_count',
    '$count ta natija',
    '$count результатов',
    '$count outputs',
  );
  static String processing(Locale l) => _p(
    l,
    'scan.saved_detail.processing',
    'Model tayyorlanmoqda…',
    'Модель обрабатывается…',
    'Model is being prepared…',
  );
  static String reprocess(Locale l, int version) => _p(
    l,
    'scan.saved_detail.reprocess',
    'Modelni qayta tayyorlash (v$version)',
    'Обработать модель заново (v$version)',
    'Process the model again (v$version)',
  );
  static String startTexturing(Locale l) => _p(
    l,
    'scan.saved_detail.start_texturing',
    '3D modelni tayyorlashni boshlash',
    'Запустить обработку 3D-модели',
    'Start 3D model processing',
  );
  static String viewLidarMesh(Locale l) => _p(
    l,
    'scan.saved_detail.view_lidar_mesh',
    'LiDAR skan to\'rini ko\'rish',
    'Посмотреть LiDAR-сетку',
    'View mesh (LiDAR)',
  );
  static String latest(Locale l) =>
      _p(l, 'common.latest', 'oxirgi', 'последний', 'latest');
  static String todayAt(Locale l, String time) => _p(
    l,
    'common.today_at',
    'Bugun, $time',
    'Сегодня, $time',
    'Today, $time',
  );
  static String yesterdayAt(Locale l, String time) => _p(
    l,
    'common.yesterday_at',
    'Kecha, $time',
    'Вчера, $time',
    'Yesterday, $time',
  );
  static String _p(Locale l, String key, String uz, String ru, String en) =>
      tr(l, key, uz: uz, ru: ru, en: en);
}
