import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import '../settings/settings_state.dart';
import '../support/support_service.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<HelpScreen> {
  @override
  int get currentToken => 1;

  /// Aloqa ma'lumotlari adminkadan keladi (Sozlamalar -> support_info), xuddi
  /// asosiy ekran va AI holati ekranidagidek. Oldin bu yerda uchta qator
  /// KODGA YOZILGAN edi va uchalasi ham NOTO'G'RI ko'rsatilardi:
  /// "@kadastr_bot", "support@example.uz" (RFC 2606 namuna domeni) va
  /// "+998 71 200 00 00". Admin ularni o'zgartira olmasdi — yangi reliz kerak
  /// edi. Endi manba bitta: `SupportService`.
  final SupportService _support = SupportService();
  SupportInfo _info = const SupportInfo(phone: SupportService.fallbackPhone);

  @override
  void initState() {
    super.initState();
    _loadSupportInfo();
  }

  Future<void> _loadSupportInfo() async {
    // Xato bo'lsa jim qaytadi va zaxira raqam qoladi — yordam sahifasi
    // tarmoqsiz ham ochilishi kerak.
    final info = await _support.fetchInfo();
    if (mounted) setState(() => _info = info);
  }

  /// Adminka "@nick" ham, to'liq havola ham kiritishi mumkin.
  ///
  /// Buzuq qiymat (bo'sh, probel, `Uri.parse` hazm qilmaydigan matn) `null`
  /// qaytaradi — qator umuman bosilmaydigan bo'ladi, `Uri.parse` esa
  /// `FormatException` bilan yiqilmaydi.
  Uri? _telegramUri(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http://') || v.startsWith('https://')) {
      return Uri.tryParse(v);
    }
    final handle = v.replaceFirst(RegExp(r'^@'), '').trim();
    if (handle.isEmpty) return null;
    return Uri.tryParse('https://t.me/$handle');
  }

  /// Havolani ochadi va OCHILMASA aytadi.
  ///
  /// ⚠️ Ilgari natija ham, istisno ham JIM YUTILARDI: qurilmada Telegram
  /// bo'lmasa yoki adminka buzuq qiymat kiritsa, qator bosilardi-yu hech
  /// narsa bo'lmasdi va foydalanuvchi ilovani "qotib qolgan" deb o'ylardi.
  /// `launchUrl` ko'p holda xato TASHLAMAYDI — `false` qaytaradi, shuning
  /// uchun natijani ham tekshirish shart.
  Future<void> _open(Uri? uri) async {
    final locale = localeNotifier.value;
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (ok || !mounted) return;
    AppToast.error(context, tr(locale, 'support.launch_failed'));
  }

  /// Savollar soni KODDA emas, tarjimalar to'plamida hal bo'ladi.
  ///
  /// Oldin `for (var i = 1; i <= 5; i++)` turardi: admin Tarjimalar sahifasida
  /// matnni o'zgartira olardi, lekin oltinchi savolni QO'SHA olmasdi va
  /// beshtadan kamini ham qila olmasdi — buning uchun yangi reliz kerak edi.
  /// `tr` topilmagan kalitni kalitning o'zi qilib qaytargani uchun mavjudligini
  /// shundan bilamiz.
  static const int _faqLimit = 30; // cheksiz aylanmaslik uchun xavfsizlik chegarasi
  List<({String q, String a})> _faqs(Locale locale) {
    final out = <({String q, String a})>[];
    for (var i = 1; i <= _faqLimit; i++) {
      final qKey = 'help.faq.q$i';
      final aKey = 'help.faq.a$i';
      final q = tr(locale, qKey);
      final a = tr(locale, aKey);
      if (q == qKey) break; // savol tugadi
      out.add((q: q, a: a == aKey ? '' : a));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        final faqs = _faqs(locale);
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
                        child: AppHeaderBack(title: tr(locale, 'help.title')),
                      ),
                      const SizedBox(height: 16),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.1,
                          0.6,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _SectionLabel(text: tr(locale, 'help.faq_label')),
                      ),
                      const SizedBox(height: 8),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.15,
                          0.7,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _FaqCard(items: faqs),
                      ),
                      const SizedBox(height: 16),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.25,
                          0.8,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _SectionLabel(
                          text: tr(locale, 'help.contact_label'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.3,
                          0.9,
                          curve: Curves.easeOutCubic,
                        ),
                        child: AppMenuCard(
                          // Bo'sh maydon ko'rsatilmaydi: adminka telegramni
                          // tozalasa, qator yo'qoladi — "—" yoki eski qiymat
                          // qolib ketmaydi.
                          rows: [
                            if ((_info.telegram ?? '').isNotEmpty)
                              AppMenuRow(
                                icon: Icons.send_rounded,
                                label: tr(locale, 'help.telegram'),
                                trailing: _ContactValue(text: _info.telegram!),
                                onTap: hapticTap(
                                  () => _open(_telegramUri(_info.telegram!)),
                                ),
                              ),
                            if ((_info.email ?? '').isNotEmpty)
                              AppMenuRow(
                                icon: Icons.mail_outline_rounded,
                                label: tr(locale, 'help.email'),
                                trailing: _ContactValue(text: _info.email!),
                                onTap: hapticTap(
                                  () => _open(Uri(scheme: 'mailto', path: _info.email!)),
                                ),
                              ),
                            AppMenuRow(
                              icon: Icons.call_outlined,
                              label: tr(locale, 'help.phone'),
                              trailing: _ContactValue(text: _info.callNumber),
                              onTap: hapticTap(
                                () => _open(Uri(scheme: 'tel', path: _info.callNumber)),
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
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.items});

  final List<({String q, String a})> items;

  @override
  Widget build(BuildContext context) {
    final dividerColor = ColorTokens.divider(context);
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(_FaqItem(question: items[i].q, answer: items[i].a));
      if (i != items.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
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

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _open = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hapticSelect(_toggle),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        height: 1.3,
                        color: ColorTokens.primaryText(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  RotationTransition(
                    turns: Tween<double>(begin: 0, end: 0.5).animate(_ctrl),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: ColorTokens.secondaryText(context),
                      size: 22,
                    ),
                  ),
                ],
              ),
              SizeTransition(
                sizeFactor: _ctrl,
                axisAlignment: -1,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 24),
                  child: Text(
                    widget.answer,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      height: 1.45,
                      color: ColorTokens.secondaryText(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: ColorTokens.secondaryText(context),
        ),
      ),
    );
  }
}

class _ContactValue extends StatelessWidget {
  const _ContactValue({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: ColorTokens.secondaryText(context),
      ),
    );
  }
}

