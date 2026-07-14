import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../settings/settings_state.dart';
import 'local_scan_service.dart';

class MyScansScreen extends StatefulWidget {
  const MyScansScreen({super.key});

  @override
  State<MyScansScreen> createState() => _MyScansScreenState();
}

class _MyScansScreenState extends State<MyScansScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<MyScansScreen> {
  @override
  int get currentToken => 1;

  static const _previewChannel = MethodChannel('kadastr/room_plan_scanner');

  final _service = LocalScanService();
  List<LocalScanItem> _items = [];
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

  Future<void> _openScan(LocalScanItem item) async {
    final locale = localeNotifier.value;
    final path = await _service.getPath(item.id);
    if (path == null) {
      _showSnackBar(_S.fileNotFound(locale));
      return;
    }
    try {
      await _previewChannel.invokeMethod('previewModel', {'filePath': path});
    } on PlatformException catch (e) {
      _showSnackBar(_S.openError(locale, e.message ?? ''));
    }
  }

  Future<void> _deleteScan(LocalScanItem item) async {
    final locale = localeNotifier.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_S.deleteTitle(locale)),
        content: Text(_S.deletePrompt(locale, item.name)),
        actions: [
          TextButton(
            onPressed: hapticTap(() => Navigator.pop(ctx, false)),
            child: Text(_S.cancel(locale)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: hapticTap(() => Navigator.pop(ctx, true)),
            child: Text(_S.delete(locale)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _service.delete(item.id);
    if (ok) {
      _showSnackBar(_S.deleted(locale));
      await _load();
    } else {
      _showSnackBar(_S.error(locale));
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
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
                          child: AppHeaderBack(title: _S.title(locale)),
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
                              child: _LocalScanCard(
                                item: _items[i],
                                locale: locale,
                                onTap: () => _openScan(_items[i]),
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

class _LocalScanCard extends StatelessWidget {
  const _LocalScanCard({
    required this.item,
    required this.locale,
    required this.onTap,
    required this.onDelete,
  });

  final LocalScanItem item;
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
        onTap: hapticTap(onTap),
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
                  Icons.view_in_ar,
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
                          _Chip(_S.photoCount(locale, item.photoCount)),
                        _Chip(item.sizeFormatted),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.red.withValues(alpha: 0.7),
                onPressed: hapticTap(onDelete),
                tooltip: _S.delete(locale),
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
    if (diff == 0) return _S.todayAt(locale, timeStr);
    if (diff == 1) return _S.yesterdayAt(locale, timeStr);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}, $timeStr';
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ColorTokens.iconBg(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 11,
          color: ColorTokens.secondaryText(context),
        ),
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
            _S.emptyTitle(locale),
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
            _S.emptyMessage(locale),
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

class _S {
  static String fileNotFound(Locale l) => _p(
    l,
    'common.file_not_found',
    'Fayl topilmadi',
    'Файл не найден',
    'File not found',
  );
  static String openError(Locale l, String message) =>
      '${_p(l, 'common.open_error', 'Ochishda xatolik', 'Ошибка открытия', 'Open error')}: $message';
  static String deleteTitle(Locale l) => _p(
    l,
    'scan.my.delete_title',
    'Skanni o\'chirish',
    'Удалить скан',
    'Delete scan',
  );
  static String deletePrompt(Locale l, String name) => _p(
    l,
    'scan.my.delete_prompt',
    '"$name" ni o\'chirishni tasdiqlaysizmi?',
    'Подтвердить удаление "$name"?',
    'Confirm deleting "$name"?',
  );
  static String cancel(Locale l) =>
      _p(l, 'common.cancel', 'Bekor qilish', 'Отмена', 'Cancel');
  static String delete(Locale l) =>
      _p(l, 'common.delete', 'O\'chirish', 'Удалить', 'Delete');
  static String deleted(Locale l) => _p(
    l,
    'scan.my.deleted',
    'Skan o\'chirildi',
    'Скан удалён',
    'Scan deleted',
  );
  static String error(Locale l) =>
      _p(l, 'common.error', 'Xatolik', 'Ошибка', 'Error');
  static String title(Locale l) =>
      _p(l, 'scan.my.title', 'Skanlarim', 'Мои сканы', 'My scans');
  static String emptyTitle(Locale l) => _p(
    l,
    'scan.my.empty_title',
    'Hozircha skan yo\'q',
    'Сканов пока нет',
    'No scans yet',
  );
  static String emptyMessage(Locale l) => _p(
    l,
    'scan.my.empty_message',
    'Birinchi 3D xona skanini yarating',
    'Создайте свой первый 3D скан комнаты',
    'Create your first 3D room scan',
  );

  static String photoCount(Locale l, int count) => _p(
    l,
    'scan.common.photo_count',
    '$count foto',
    '$count фото',
    '$count photos',
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
  static String _p(Locale l, String key, String uz, String ru, String en) =>
      tr(l, key, uz: uz, ru: ru, en: en);
}
