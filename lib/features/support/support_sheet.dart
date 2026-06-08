import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
      ).showSnackBar(SnackBar(content: Text(_S.launchFailed(locale))));
    }
  }

  Uri? _telegramUri() {
    final raw = info.telegram?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.tryParse(raw);
    }
    final handle = raw.replaceFirst(RegExp(r'^@'), '');
    return Uri.parse('https://t.me/$handle');
  }

  @override
  Widget build(BuildContext context) {
    final bg = ColorTokens.cardBg(context);
    final titleColor = ColorTokens.primaryText(context);
    final handleColor = ColorTokens.divider(context);

    final telegramUri = _telegramUri();
    final email = info.email?.trim();
    final hours = info.workingHours?.trim();

    final rows = <Widget>[
      _SupportRow(
        icon: Icons.call_rounded,
        label: _S.call(locale),
        value: info.phone,
        onTap: () => _launch(context, Uri(scheme: 'tel', path: info.phone)),
      ),
      if (telegramUri != null)
        _SupportRow(
          icon: Icons.send_rounded,
          label: 'Telegram',
          value: info.telegram!.trim(),
          onTap: () => _launch(context, telegramUri),
        ),
      if (email != null && email.isNotEmpty)
        _SupportRow(
          icon: Icons.mail_outline_rounded,
          label: _S.email(locale),
          value: email,
          onTap: () => _launch(context, Uri(scheme: 'mailto', path: email)),
        ),
      if (hours != null && hours.isNotEmpty)
        _SupportRow(
          icon: Icons.schedule_rounded,
          label: _S.hours(locale),
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
              _S.title(locale),
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

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Центр поддержки',
    'en' => 'Support center',
    _ => 'Yordam markazi',
  };

  static String call(Locale l) => switch (l.languageCode) {
    'ru' => 'Позвонить',
    'en' => 'Call',
    _ => 'Qo\'ng\'iroq qilish',
  };

  static String email(Locale l) => switch (l.languageCode) {
    'ru' => 'Эл. почта',
    'en' => 'Email',
    _ => 'Email',
  };

  static String hours(Locale l) => switch (l.languageCode) {
    'ru' => 'Часы работы',
    'en' => 'Working hours',
    _ => 'Ish vaqti',
  };

  static String launchFailed(Locale l) => switch (l.languageCode) {
    'ru' => 'Не удалось открыть',
    'en' => 'Could not open',
    _ => 'Ochib bo\'lmadi',
  };
}
