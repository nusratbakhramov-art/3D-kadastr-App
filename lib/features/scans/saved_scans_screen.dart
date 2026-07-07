import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/app_translations.dart';
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
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(SavedScanItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedScanDetailScreen(scanId: item.id),
      ),
    );
    // Detail'dan qaytgach ro'yxatni yangilash (output qo'shilgan bo'lishi mumkin)
    await _load();
  }

  Future<void> _deleteScan(SavedScanItem item) async {
    final locale = localeNotifier.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_Strings.deleteTitle(locale)),
        content: Text(_Strings.deletePrompt(locale, item.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_Strings.cancel(locale)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_Strings.delete(locale)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _service.delete(item.id);
    if (ok) {
      if (!mounted) return;
      AppToast.success(context, _Strings.deleted(locale));
      await _load();
    } else {
      if (!mounted) return;
      AppToast.error(context, _Strings.deleteError(locale));
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
                            0.0,
                            0.4,
                            curve: Curves.easeOutCubic,
                          ),
                          child: AppHeaderBack(title: _Strings.title(locale)),
                        ),
                        const SizedBox(height: 16),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 80),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_items.isEmpty)
                          _EmptyState(locale: locale)
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
                                locale: locale,
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
    required this.locale,
    required this.onTap,
    required this.onDelete,
  });

  final SavedScanItem item;
  final Locale locale;
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
                  item.isProcessed
                      ? Icons.view_in_ar
                      : Icons.camera_alt_outlined,
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
                          _Chip(_Strings.photoCount(locale, item.photoCount)),
                        if (item.outputs.isNotEmpty)
                          _Chip(
                            _Strings.resultCount(locale, item.outputs.length),
                            tint: Colors.green,
                          )
                        else
                          _Chip(
                            _Strings.unprocessed(locale),
                            tint: Colors.orange,
                          ),
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
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return _Strings.todayAt(locale, timeStr);
    if (diff == 1) return _Strings.yesterdayAt(locale, timeStr);
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
        style: TextStyle(fontFamily: 'MTSText', fontSize: 11, color: fg),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.locale});

  final Locale locale;

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
            _Strings.emptyTitle(locale),
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
            _Strings.emptyMessage(locale),
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

class _Strings {
  static String title(Locale l) =>
      _p(l, 'scan.saved.title', 'Mening skanlarim', 'Мои сканы', 'My scans');
  static String deleteTitle(Locale l) => _p(
    l,
    'scan.saved.delete_title',
    'Skanni o\'chirish',
    'Удалить скан',
    'Delete scan',
  );
  static String deletePrompt(Locale l, String name) => _p(
    l,
    'scan.saved.delete_prompt',
    '"$name" — barcha foto va outputlar bilan o\'chiriladi. Davom etamizmi?',
    '"$name" будет удалён вместе со всеми фото и результатами. Продолжить?',
    '"$name" will be deleted together with all photos and outputs. Continue?',
  );
  static String cancel(Locale l) =>
      _p(l, 'common.cancel', 'Bekor qilish', 'Отмена', 'Cancel');
  static String delete(Locale l) =>
      _p(l, 'common.delete', 'O\'chirish', 'Удалить', 'Delete');
  static String deleted(Locale l) => _p(
    l,
    'scan.saved.deleted',
    'Skan o\'chirildi',
    'Скан удалён',
    'Scan deleted',
  );
  static String deleteError(Locale l) => _p(
    l,
    'scan.saved.delete_error',
    'O\'chirishda xatolik',
    'Ошибка удаления',
    'Delete error',
  );
  static String photoCount(Locale l, int count) => _p(
    l,
    'scan.common.photo_count',
    '$count foto',
    '$count фото',
    '$count photos',
  );
  static String resultCount(Locale l, int count) => _p(
    l,
    'scan.saved.result_count',
    '$count natija',
    '$count результатов',
    '$count results',
  );
  static String unprocessed(Locale l) => _p(
    l,
    'scan.saved.unprocessed',
    'Qayta ishlanmagan',
    'Не обработан',
    'Not processed',
  );
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
  static String emptyTitle(Locale l) => _p(
    l,
    'scan.saved.empty_title',
    'Skanlar yo\'q',
    'Сканов нет',
    'No scans yet',
  );
  static String emptyMessage(Locale l) => _p(
    l,
    'scan.saved.empty_message',
    'AI baholash bo\'limida 3D skan tugmasini bosib, xonangizni skan qiling. '
        'Bu yerda saqlangan ma\'lumotlar ro\'yxati ko\'rinadi.',
    'Нажмите AI оценка → 3D-скан и отсканируйте комнату. '
        'Здесь появится список сохранённых данных.',
    'Tap AI valuation → 3D scan and scan your room. '
        'Your saved scans will appear here.',
  );
  static String _p(Locale l, String key, String uz, String ru, String en) =>
      tr(l, key, uz: uz, ru: ru, en: en);
}
