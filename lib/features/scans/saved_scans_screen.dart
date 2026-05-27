import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import '../settings/settings_state.dart';
import 'saved_scan_detail_screen.dart';
import 'saved_scan_service.dart';

/// Phase 7: Foydalanuvchi profilida "Mening skanlarim" — endi raw skanlar
/// ro'yxati. Har scan'ning ichida outputs[] history bor (qayta ishlash
/// natijalari). Old USDZ-only `MyScansScreen` o'rniga.
class SavedScansScreen extends StatefulWidget {
  const SavedScansScreen({super.key});

  @override
  State<SavedScansScreen> createState() => _SavedScansScreenState();
}

class _SavedScansScreenState extends State<SavedScansScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<SavedScansScreen> {
  @override
  int get currentToken => 1;

  final _service = SavedScanService();
  List<SavedScanItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.list();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _openDetail(SavedScanItem item) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SavedScanDetailScreen(scanId: item.id),
    ));
    // Detail'dan qaytgach ro'yxatni yangilash (output qo'shilgan bo'lishi mumkin)
    await _load();
  }

  Future<void> _deleteScan(SavedScanItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skanni o\'chirish'),
        content: Text('"${item.name}" — barcha foto va outputlar bilan o\'chiriladi. Davom etamizmi?'),
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
    final ok = await _service.delete(item.id);
    if (ok) {
      if (!mounted) return;
      AppToast.success(context, 'Skan o\'chirildi');
      await _load();
    } else {
      if (!mounted) return;
      AppToast.error(context, 'O\'chirishda xatolik');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return Scaffold(
          backgroundColor: ColorTokens.scaffoldBg(context),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const AppGlowBackground(),
              SafeArea(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppReveal(
                          controller: entryController,
                          interval: const Interval(
                            0.0, 0.4, curve: Curves.easeOutCubic,
                          ),
                          child: const AppHeaderBack(title: 'Mening skanlarim'),
                        ),
                        const SizedBox(height: 16),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 80),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_items.isEmpty)
                          const _EmptyState()
                        else
                          for (var i = 0; i < _items.length; i++) ...[
                            AppReveal(
                              controller: entryController,
                              interval: Interval(
                                (0.1 + i * 0.05).clamp(0.0, 0.9),
                                (0.6 + i * 0.05).clamp(0.0, 1.0),
                                curve: Curves.easeOutCubic,
                              ),
                              child: _SavedScanCard(
                                item: _items[i],
                                onTap: () => _openDetail(_items[i]),
                                onDelete: () => _deleteScan(_items[i]),
                              ),
                            ),
                            if (i != _items.length - 1)
                              const SizedBox(height: 12),
                          ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavedScanCard extends StatelessWidget {
  const _SavedScanCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final SavedScanItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.cardBg(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: ColorTokens.iconBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.isProcessed ? Icons.view_in_ar : Icons.camera_alt_outlined,
                  size: 28,
                  color: ColorTokens.brandPrimary(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: ColorTokens.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(item.createdAt),
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: ColorTokens.secondaryText(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (item.areaSqm > 0.01)
                          _Chip('${item.areaSqm.toStringAsFixed(1)} m²'),
                        if (item.photoCount > 0)
                          _Chip('${item.photoCount} foto'),
                        if (item.outputs.isNotEmpty)
                          _Chip(
                            '${item.outputs.length} natija',
                            tint: Colors.green,
                          )
                        else
                          _Chip('Qayta ishlanmagan', tint: Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 22,
                color: ColorTokens.secondaryText(context),
              ),
            ],
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

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.tint});
  final String text;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final bg = tint?.withValues(alpha: 0.15) ?? ColorTokens.iconBg(context);
    final fg = tint ?? ColorTokens.secondaryText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 11,
          color: fg,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        children: [
          Icon(
            Icons.view_in_ar_outlined,
            size: 64,
            color: ColorTokens.secondaryText(context).withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Skanlar yo\'q',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI baholash → 3D skan tugmasini bosib, xonangizni skanlang. '
            'Bu yerda saqlangan ma\'lumotlar ro\'yxati ko\'rinadi.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              color: ColorTokens.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}
