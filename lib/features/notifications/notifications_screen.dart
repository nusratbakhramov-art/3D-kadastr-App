import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../home/user_profile.dart';
import '../settings/settings_state.dart';
import 'notification_model.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<NotificationsScreen> {
  @override
  int get currentToken => 1;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return ValueListenableBuilder<List<AppNotification>>(
          valueListenable: notificationsNotifier,
          builder: (context, items, _) {
            final groups = _group(items);
            final hasUnread = items.any((n) => n.unread);

            return Scaffold(
              backgroundColor: ColorTokens.scaffoldBg(context),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const AppGlowBackground(),
                  SafeArea(
                    child: SingleChildScrollView(
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
                            child: AppHeaderBack(
                              title: _S.title(locale),
                              trailing: hasUnread
                                  ? _MarkAllButton(
                                      label: _S.markAll(locale),
                                      onTap: () {
                                        markAllNotificationsRead();
                                        notificationUnreadNotifier.value = 0;
                                      },
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (items.isEmpty)
                            _EmptyState(
                              title: _S.emptyTitle(locale),
                              message: _S.emptyMessage(locale),
                            )
                          else
                            ..._renderGroups(groups, locale),
                        ],
                      ),
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

  List<Widget> _renderGroups(
    List<({String label, List<AppNotification> items})> groups,
    Locale locale,
  ) {
    final out = <Widget>[];
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      out.add(
        AppReveal(
          controller: entryController,
          interval: Interval(
            (0.1 + gi * 0.1).clamp(0.0, 0.9),
            (0.6 + gi * 0.1).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
            child: Text(
              _S.groupLabel(locale, g.label),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: ColorTokens.secondaryText(context),
              ),
            ),
          ),
        ),
      );
      out.add(
        AppReveal(
          controller: entryController,
          interval: Interval(
            (0.15 + gi * 0.1).clamp(0.0, 0.9),
            (0.7 + gi * 0.1).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
          child: _NotificationGroupCard(items: g.items, locale: locale),
        ),
      );
      out.add(const SizedBox(height: 16));
    }
    return out;
  }

  List<({String label, List<AppNotification> items})> _group(
    List<AppNotification> items,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayItems = <AppNotification>[];
    final yesterdayItems = <AppNotification>[];
    final earlierItems = <AppNotification>[];

    for (final n in items) {
      final d = DateTime(n.at.year, n.at.month, n.at.day);
      if (d == today) {
        todayItems.add(n);
      } else if (d == yesterday) {
        yesterdayItems.add(n);
      } else {
        earlierItems.add(n);
      }
    }

    return [
      if (todayItems.isNotEmpty) (label: 'today', items: todayItems),
      if (yesterdayItems.isNotEmpty)
        (label: 'yesterday', items: yesterdayItems),
      if (earlierItems.isNotEmpty) (label: 'earlier', items: earlierItems),
    ];
  }
}

class _NotificationGroupCard extends StatelessWidget {
  const _NotificationGroupCard({required this.items, required this.locale});

  final List<AppNotification> items;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(_NotificationTile(item: items[i]));
      if (i != items.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Divider(
              height: 1,
              thickness: 1,
              color: ColorTokens.divider(context),
            ),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final (iconData, accent) = iconForType(item.type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (item.unread) {
            markNotificationRead(item.id);
            notificationUnreadNotifier.value = unreadNotificationCount();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(iconData, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: item.unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 15,
                              color: ColorTokens.primaryText(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(item.at),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: ColorTokens.tertiaryText(context),
                          ),
                        ),
                        if (item.unread) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF3B30),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                        height: 1.3,
                        color: ColorTokens.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _MarkAllButton extends StatelessWidget {
  const _MarkAllButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.cardBg(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.brandGreen,
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
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
  static String markAll(Locale l) => switch (l.languageCode) {
    'ru' => 'Прочитать всё',
    'en' => 'Mark all read',
    _ => 'Hammasini o‘qish',
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
  static String groupLabel(Locale l, String key) => switch (key) {
    'today' => switch (l.languageCode) {
      'ru' => 'Сегодня',
      'en' => 'Today',
      _ => 'Bugun',
    },
    'yesterday' => switch (l.languageCode) {
      'ru' => 'Вчера',
      'en' => 'Yesterday',
      _ => 'Kecha',
    },
    _ => switch (l.languageCode) {
      'ru' => 'Ранее',
      'en' => 'Earlier',
      _ => 'Oldin',
    },
  };
}
