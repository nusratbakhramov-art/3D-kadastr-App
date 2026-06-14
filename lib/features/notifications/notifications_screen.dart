import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../home/user_profile.dart';
import '../settings/settings_state.dart';
import 'notification_date.dart';
import 'notification_detail_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await refreshNotifications();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _markAll() async {
    markAllNotificationsRead();
    notificationUnreadNotifier.value = 0;
    await _api.markAllRead();
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
                              onTap: hasUnread ? _markAll : null,
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
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _NotificationCard(
        item: items[i],
        locale: locale,
        onTap: () => _openItem(items[i]),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.locale,
    required this.onTap,
  });

  final AppNotification item;
  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.unread
                  ? AppColors.brandGreen
                  : ColorTokens.divider(context),
              width: item.unread ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NotificationDateChip(at: item.at, locale: locale),
              const SizedBox(height: 12),
              if (item.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    width: double.infinity,
                    height: 160,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      height: 160,
                      color: ColorTokens.iconBg(context),
                    ),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                item.title,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 16.5,
                  height: 1.25,
                  color: ColorTokens.primaryText(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontWeight: FontWeight.w400,
                  fontSize: 13.5,
                  height: 1.35,
                  color: ColorTokens.secondaryText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkAllCircle extends StatelessWidget {
  const _MarkAllCircle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.brandGreen : ColorTokens.cardBg(context),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.done_all_rounded,
            size: 20,
            color: active ? Colors.white : ColorTokens.tertiaryText(context),
          ),
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

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Уведомления',
    'en' => 'Notifications',
    _ => 'Bildirishnomalar',
  };
  static String emptyTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Уведомлений пока нет',
    'en' => 'No notifications yet',
    _ => 'Hozircha bildirishnomalar yo‘q',
  };
  static String emptyMessage(Locale l) => switch (l.languageCode) {
    'ru' => 'Здесь появятся обновления о ваших сканах, оценках и платежах.',
    'en' => 'Updates about scans, valuations and payments will show up here.',
    _ =>
      'Skanlar, baholashlar va to‘lovlar bo‘yicha yangiliklar shu yerda ko‘rinadi.',
  };
}
