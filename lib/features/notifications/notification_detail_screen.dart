import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/app_update/app_update_store.dart';
import '../../core/app_update/store_launcher.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/sheet_button.dart';
import '../settings/settings_state.dart';
import 'notification_date.dart';
import 'notification_model.dart';

/// Bitta bildirishnoma — to'liq matn + rasm (bo'lsa).
///
/// Avval bu sahifa bo'sh ekran o'rtasidagi KARTA edi: tepasida kulrang sana
/// chipi (ro'yxatdan olib tashlangan o'sha naqsh), ostida 19px sarlavha, so'ng
/// ekranning uchdan ikki qismi qop-qora bo'shliq. Karta hech narsa qo'shmasdi
/// — sahifaning O'ZI shu bildirishnoma.
///
/// Endi: chapda tur belgisi (ro'yxatdagi bilan AYNAN bir xil, shuning uchun
/// ro'yxatdan ochilganda uzilish sezilmaydi), yirik sarlavha, tinch matn va
/// pastga mahkamlangan amal. Sana — eng past ovozli qator, chunki u
/// metama'lumot.
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({super.key, required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final (icon, tint) = iconForType(item.type);
        final accent = (tint == AppColors.splashGreen && !isDark)
            ? AppColors.brandGreen
            : tint;
        final isUpdate = item.type == NotificationType.appUpdate;

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
                      child: AppHeaderBack(title: _title(locale)),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(icon, size: 23, color: accent),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              item.title,
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 26,
                                height: 1.15,
                                letterSpacing: -0.5,
                                color: ColorTokens.primaryText(context),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Sana — eng tinch qator, sarlavhadan KEYIN.
                            Text(
                              formatNotificationDate(item.at, locale),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: ColorTokens.tertiaryText(context),
                              ),
                            ),
                            if (item.imageUrl != null) ...[
                              const SizedBox(height: 20),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
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
                            ],
                            if (item.message.trim().isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(
                                item.message,
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontWeight: FontWeight.w400,
                                  fontSize: 15.5,
                                  height: 1.55,
                                  color: ColorTokens.secondaryText(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // Yangilanish xabari — do'konga olib boradi. Push'ni
                    // bosganda do'kon ochiladi (`PushNotifications._handleTapData`);
                    // ro'yxatdan ochilganda esa hech narsa bo'lmasdi, ya'ni bitta
                    // xabarning ikki yo'li ikki xil ishlardi.
                    //
                    // Pastga mahkamlangan: bo'sh joy endi tasodifiy emas, u
                    // matnni amaldan ajratib turadi.
                    if (isUpdate)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                        child: SheetButton(
                          label: tr(locale, 'update.action_update'),
                          isDark: isDark,
                          filled: true,
                          onTap: () => openStoreOrWarn(
                            context,
                            // Keshlangan reliz havolasi; bo'sh bo'lsa
                            // `openStore` platforma zaxirasiga tushadi,
                            // shuning uchun tugma hech qachon jim qolmaydi.
                            appReleaseNotifier.value.storeUrl,
                            locale,
                          ),
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
  }

  String _title(Locale l) => tr(l, 'notifications.detail_title');
}
