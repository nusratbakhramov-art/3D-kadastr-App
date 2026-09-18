import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_banner.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../home/user_profile.dart';
import '../settings/settings_state.dart';
import 'notification_date.dart';
import 'notification_detail_screen.dart';
import 'notification_row.dart';
import 'notification_model.dart';
import 'notifications_api.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsApi _api = NotificationsApi();
  bool _loading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await refreshNotifications();
    if (mounted) setState(() => _loading = false);
  }

  /// Bitta to'liq aylanish. Tugma FAQAT shu qadamlarda to'xtaydi, shuning
  /// uchun tez javob ham, sekin javob ham butun aylanish bilan tugaydi.
  static const Duration _spinTurn = Duration(milliseconds: 700);

  Future<void> _markAll() async {
    if (_markingAll) return; // uchib ketayotgan so'rov ustiga ikkinchisi yo'q
    setState(() => _markingAll = true);

    // Optimistik: ro'yxat darhol o'qilgan ko'rinadi. Xato bo'lsa qaytaramiz —
    // aks holda foydalanuvchi o'qilmaganlar yo'qolgan deb o'ylaydi.
    final previous = notificationsNotifier.value;
    final elapsed = Stopwatch()..start();
    markAllNotificationsRead();
    notificationUnreadNotifier.value = 0;

    var ok = true;
    try {
      await _api.markAllRead();
    } catch (_) {
      ok = false;
      notificationsNotifier.value = previous;
      notificationUnreadNotifier.value = unreadNotificationCount();
    }

    // Aylanishni o'rtasida kesmaymiz: qolgan qismini kutamiz.
    final remainder =
        elapsed.elapsedMilliseconds % _spinTurn.inMilliseconds;
    await Future<void>.delayed(
      Duration(milliseconds: _spinTurn.inMilliseconds - remainder),
    );

    if (!mounted) return;
    setState(() => _markingAll = false);
    final locale = localeNotifier.value;
    showAppBanner(
      context,
      tr(
        locale,
        ok ? 'notifications.all_read_done' : 'notifications.all_read_failed',
      ),
      isError: !ok,
    );
  }

  Future<void> _openItem(AppNotification item) async {
    if (item.unread) {
      markNotificationRead(item.id);
      notificationUnreadNotifier.value = unreadNotificationCount();
      _api.markRead(item.id); // fire-and-forget
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationDetailScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return ValueListenableBuilder<List<AppNotification>>(
          valueListenable: notificationsNotifier,
          builder: (context, items, _) {
            final hasUnread = items.any((n) => n.unread);
            return Scaffold(
              backgroundColor: ColorTokens.scaffoldBg(context),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const AppGlowBackground(),
                  SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: AppHeaderBack(
                            title: _S.title(locale),
                            trailing: _MarkAllCircle(
                              active: hasUnread,
                              pending: _markingAll,
                              onTap: (hasUnread && !_markingAll)
                                  ? _markAll
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: RefreshIndicator(
                            color: AppColors.brandGreen,
                            onRefresh: refreshNotifications,
                            child: _buildBody(items, locale),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(List<AppNotification> items, Locale locale) {
    if (_loading && items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: 80),
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.brandGreen,
          ),
        ),
      );
    }
    if (items.isEmpty) {
      // ListView (scroll) — RefreshIndicator bo'sh holatda ham ishlasin.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.16),
          _EmptyState(
            title: _S.emptyTitle(locale),
            message: _S.emptyMessage(locale),
          ),
        ],
      );
    }
    // Ro'yxat kunlar bo'yicha guruhlanadi, shuning uchun satrlar oldindan
    // yoyiladi: sarlavha ham, satr ham bitta ListView elementi.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final newDay =
            i == 0 || !sameNotificationDay(items[i - 1].at, item.at);
        final row = NotificationRow(
          item: item,
          onTap: () => _openItem(item),
        );
        if (!newDay) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_Hairline(), row],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NotificationDayHeader(at: item.at, locale: locale, first: i == 0),
            row,
          ],
        );
      },
    );
  }
}

/// Satrlar orasidagi ingichka chiziq — belgidan keyin boshlanadi, shuning
/// uchun ro'yxatda bitta tik o'q hosil bo'ladi.
class _Hairline extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 59),
    child: Divider(
      height: 1,
      thickness: 1,
      color: ColorTokens.divider(context),
    ),
  );
}

/// "Hammasini o'qilgan deb belgilash".
///
/// Backendga so'rov ketadi, shuning uchun bosilgach DARHOL aylanadi va qayta
/// bosilmaydi. Tugma bir marta aylanib to'xtasa — hammasi tez bo'ldi; uzoq
/// aylansa — server hali javob bermayapti. Aylanish o'rtasida to'xtamaydi:
/// ekran uni butun qadamlarda tugatadi.
class _MarkAllCircle extends StatefulWidget {
  const _MarkAllCircle({
    required this.active,
    required this.pending,
    required this.onTap,
  });

  final bool active;
  final bool pending;
  final VoidCallback? onTap;

  @override
  State<_MarkAllCircle> createState() => _MarkAllCircleState();
}

class _MarkAllCircleState extends State<_MarkAllCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _NotificationsScreenState._spinTurn,
  );

  @override
  void initState() {
    super.initState();
    if (widget.pending) _spin.repeat();
  }

  @override
  void didUpdateWidget(_MarkAllCircle old) {
    super.didUpdateWidget(old);
    if (widget.pending && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.pending && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // To'ldirilgan neon doira ro'yxatdagi hamma narsadan baland ovozli edi —
    // u yordamchi amal, sarlavha emas.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.splashGreen : AppColors.brandGreen;
    final lit = widget.active || widget.pending;
    final icon = Icon(
      widget.pending ? Icons.sync_rounded : Icons.done_all_rounded,
      size: 20,
      color: lit ? accent : ColorTokens.tertiaryText(context),
    );
    return Material(
      color: lit
          ? accent.withValues(alpha: 0.15)
          : ColorTokens.cardBg(context),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: hapticTap(widget.onTap),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: widget.pending
              ? RotationTransition(turns: _spin, child: icon)
              : icon,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: ColorTokens.cardBg(context),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: ColorTokens.shadow(context),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.notifications_off_outlined,
              size: 28,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
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
  const _S._();

  static String title(Locale l) => tr(l, 'notifications.title');
  static String emptyTitle(Locale l) => tr(l, 'notifications.empty_title');
  static String emptyMessage(Locale l) => tr(l, 'notifications.empty_message');
}
