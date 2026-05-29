import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import 'saved_scan_service.dart';

class SavedScanDetailScreen extends StatefulWidget {
  const SavedScanDetailScreen({required this.scanId, super.key});

  final int scanId;

  @override
  State<SavedScanDetailScreen> createState() => _SavedScanDetailScreenState();
}

class _SavedScanDetailScreenState extends State<SavedScanDetailScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<SavedScanDetailScreen> {
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
    if (mounted) setState(() { _item = item; _loading = false; });
  }

  Future<void> _process() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final result = await _service.process(widget.scanId);
      if (!mounted) return;
      if (result == null) {
        // Foydalanuvchi cancel qildi
        setState(() => _processing = false);
        return;
      }
      AppToast.success(
        context,
        'Qayta ishlash yakunlandi (v${result.version})',
      );
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
    setState(() => _processing = true);
    try {
      // Native LidarMeshExporter mesh'ni quradi va SceneKit viewer'da ochadi
      // (simulatorда ham ishlaydi). Alohida preview chaqiruvi kerak emas.
      final path = await _service.viewLidarMesh(widget.scanId);
      if (!mounted) return;
      setState(() => _processing = false);
      if (path == null) {
        AppToast.error(context, 'LiDAR mesh topilmadi');
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      AppToast.error(context, '$e');
    }
  }

  Future<void> _viewOutput(SavedScanOutput output) async {
    final path = await _service.outputPath(widget.scanId, output.version);
    if (path == null) {
      if (mounted) AppToast.error(context, 'Fayl topilmadi');
      return;
    }
    await _service.preview(path);
  }

  Future<void> _deleteOutput(SavedScanOutput output) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Natija o\'chirilsinmi?'),
        content: Text('v${output.version} ni o\'chirishni tasdiqlaysizmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _service.deleteOutput(widget.scanId, output.version);
    if (ok) {
      await _load();
    } else {
      if (mounted) AppToast.error(context, 'O\'chirishda xatolik');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    interval: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
                    child: AppHeaderBack(
                      title: _item?.name ?? 'Skan #${widget.scanId}',
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
                        'Skan topilmadi',
                        style: TextStyle(color: ColorTokens.primaryText(context)),
                      ),
                    )
                  else ...[
                    AppReveal(
                      controller: entryController,
                      interval: const Interval(0.1, 0.6, curve: Curves.easeOutCubic),
                      child: _InfoCard(item: _item!),
                    ),
                    const SizedBox(height: 16),
                    AppReveal(
                      controller: entryController,
                      interval: const Interval(0.2, 0.7, curve: Curves.easeOutCubic),
                      child: _ProcessButton(
                        item: _item!,
                        processing: _processing,
                        onTap: _process,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppReveal(
                      controller: entryController,
                      interval: const Interval(0.25, 0.75, curve: Curves.easeOutCubic),
                      child: _ClayButton(
                        processing: _processing,
                        onTap: _viewLidarMesh,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_item!.outputs.isNotEmpty) ...[
                      Text(
                        'Natijalar (${_item!.outputs.length})',
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
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.item});
  final SavedScanItem item;

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
            'Skan ma\'lumotlari',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          _Row(label: 'Foto soni', value: '${item.photoCount}'),
          _Row(label: 'Maydon', value: '${item.areaSqm.toStringAsFixed(2)} m²'),
          _Row(label: 'Yaratilgan', value: _formatDate(item.createdAt)),
          _Row(
            label: 'Holat',
            value: item.outputs.isEmpty
                ? 'Qayta ishlanmagan'
                : '${item.outputs.length} ta natija',
            valueColor: item.outputs.isEmpty ? Colors.orange : Colors.green,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
    required this.processing,
    required this.onTap,
  });

  final SavedScanItem item;
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
        onTap: processing ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (processing)
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              else
                Icon(
                  isReprocess ? Icons.refresh : Icons.auto_fix_high,
                  color: Colors.white, size: 22,
                ),
              const SizedBox(width: 10),
              Text(
                processing
                    ? 'Qayta ishlanmoqda…'
                    : (isReprocess ? 'Qayta ishlash (v${item.outputs.first.version + 1})' : 'Texturing boshlash'),
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
  const _ClayButton({required this.processing, required this.onTap});

  final bool processing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = ColorTokens.brandPrimary(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: processing ? null : onTap,
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
              Icon(Icons.grid_4x4,
                  color: brand.withValues(alpha: processing ? 0.5 : 1.0), size: 20),
              const SizedBox(width: 10),
              Text(
                'Mesh ko\'rish (LiDAR)',
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
    required this.isLatest,
    required this.onView,
    required this.onDelete,
  });

  final SavedScanOutput output;
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
          onTap: onView,
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'oxirgi',
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  onPressed: onDelete,
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
    final timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Bugun, $timeStr';
    if (diff == 1) return 'Kecha, $timeStr';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}, $timeStr';
  }
}
