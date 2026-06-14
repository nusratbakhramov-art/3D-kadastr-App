import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../settings/settings_state.dart';
import 'notification_model.dart';
import 'notification_date.dart';

/// Bitta bildirishnoma — to'liq matn + rasm (bo'lsa).
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({super.key, required this.item});

  final AppNotification item;

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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppHeaderBack(title: _title(locale)),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: ColorTokens.cardBg(context),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NotificationDateChip(at: item.at, locale: locale),
                            const SizedBox(height: 14),
                            if (item.imageUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: CachedNetworkImage(
                                  imageUrl: item.imageUrl!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Container(
                                    height: 180,
                                    color: ColorTokens.divider(context),
                                  ),
                                  errorWidget: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            Text(
                              item.title,
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 19,
                                height: 1.25,
                                color: ColorTokens.primaryText(context),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              item.message,
                              style: TextStyle(
                                fontFamily: 'MTSText',
                                fontWeight: FontWeight.w400,
                                fontSize: 15,
                                height: 1.4,
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
            ],
          ),
        );
      },
    );
  }

  String _title(Locale l) => switch (l.languageCode) {
    'ru' => 'Уведомление',
    'en' => 'Notification',
    _ => 'Bildirishnoma',
  };
}
