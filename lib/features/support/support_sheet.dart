import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/app_translations.dart';
import '../../theme/color_tokens.dart';
import 'support_service.dart';

/// "Yordam markazi" — qo'llab-quvvatlash bilan bog'lanish usullari (qo'ng'iroq,
/// Telegram, email) va ish vaqti. Bosh sahifa sarlavhasidagi yordam tugmasi
/// ochadi.
Future<void> showSupportSheet(
  BuildContext context, {
  required Locale locale,
  required SupportInfo info,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SupportSheet(locale: locale, info: info),
  );
}

class _SupportSheet extends StatelessWidget {
  const _SupportSheet({required this.locale, required this.info});

  final Locale locale;
  final SupportInfo info;

  Future<void> _launch(BuildContext context, Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(tr(locale, 'support.launch_failed'))),
      );
    }
  }

  Uri? _telegramUri() {
    final raw = info.telegramOrNull;
    if (raw == null) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.tryParse(raw);
    }
    final handle = raw.replaceFirst(RegExp(r'^@'), '').trim();
    if (handle.isEmpty) return null;
    return Uri.tryParse('https://t.me/$handle');
  }

  @override
  Widget build(BuildContext context) {
    final bg = ColorTokens.cardBg(context);
    final titleColor = ColorTokens.primaryText(context);
    final handleColor = ColorTokens.divider(context);

    // Qaysi qator ko'rinishi — adminkadagi qiymatlarga qarab. Shart
    // `SupportInfo` da, «Yordam» sahifasi bilan bir xil (izohni o'sha yerda
    // ko'ring). Bu yerda `info.phone` EMAS, `callNumberOrNull` ishlatiladi:
    // qo'ng'iroq qiladigan raqam aloqa markazi bo'lsa, ko'rsatiladigani ham
    // o'sha bo'lishi kerak — ilgari qator `phone` ni chizib, bosilganda
    // BOSHQA raqamga qo'ng'iroq qilardi.
    final telegramUri = _telegramUri();
    final telegram = info.telegramOrNull;
    final email = info.emailOrNull;
    final hours = info.workingHoursOrNull;
    final phone = info.callNumberOrNull;

    final rows = <Widget>[
      if (phone != null)
        _SupportRow(
          icon: Icons.call_rounded,
          label: tr(locale, 'support.call'),
          value: phone,
          onTap: () => _launch(context, Uri(scheme: 'tel', path: phone)),
        ),
      if (telegramUri != null && telegram != null)
        _SupportRow(
          icon: Icons.send_rounded,
          label: 'Telegram',
          value: telegram,
          onTap: () => _launch(context, telegramUri),
        ),
      if (email != null)
        _SupportRow(
          icon: Icons.mail_outline_rounded,
          label: tr(locale, 'support.email'),
          value: email,
          onTap: () => _launch(context, Uri(scheme: 'mailto', path: email)),
        ),
      if (hours != null)
        _SupportRow(
          icon: Icons.schedule_rounded,
          label: tr(locale, 'support.hours'),
          value: hours,
        ),
    ];

    // Pastki xavfsiz zona (home indicator) balandligini paddingga qo'shamiz —
    // shunda oq fon ekran tubigacha to'ladi, lekin matn indikator ustida qoladi.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              tr(locale, 'support.title'),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: titleColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = ColorTokens.secondaryText(context);
    final valueColor = ColorTokens.primaryText(context);
    final iconBg = ColorTokens.iconBg(context);
    final brand = ColorTokens.brandPrimary(context);

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontSize: 12.5,
                    height: 1.2,
                    color: labelColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    height: 1.25,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: ColorTokens.tertiaryText(context),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: content,
      ),
    );
  }
}

