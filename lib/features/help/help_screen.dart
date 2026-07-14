import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import '../settings/settings_state.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<HelpScreen> {
  @override
  int get currentToken => 1;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        final faqs = _S.faqs(locale);
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
                        child: AppHeaderBack(title: _S.title(locale)),
                      ),
                      const SizedBox(height: 16),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.1,
                          0.6,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _SectionLabel(text: _S.faqLabel(locale)),
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
                        child: _SectionLabel(text: _S.contactLabel(locale)),
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
                          rows: [
                            AppMenuRow(
                              icon: Icons.send_rounded,
                              label: _S.telegram(locale),
                              trailing: const _ContactValue(
                                text: '@kadastr_bot',
                              ),
                              onTap: () {},
                            ),
                            AppMenuRow(
                              icon: Icons.mail_outline_rounded,
                              label: _S.email(locale),
                              trailing: const _ContactValue(
                                text: 'support@example.uz',
                              ),
                              onTap: () {},
                            ),
                            AppMenuRow(
                              icon: Icons.call_outlined,
                              label: _S.phone(locale),
                              trailing: const _ContactValue(
                                text: '+998 71 200 00 00',
                              ),
                              onTap: () {},
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

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Помощь',
    'en' => 'Help',
    _ => 'Yordam',
  };
  static String faqLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Часто задаваемые вопросы',
    'en' => 'Frequently asked questions',
    _ => 'Tez-tez beriladigan savollar',
  };
  static String contactLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Связаться с нами',
    'en' => 'Contact us',
    _ => 'Biz bilan bog‘lanish',
  };
  static String telegram(Locale l) => switch (l.languageCode) {
    'ru' => 'Telegram',
    'en' => 'Telegram',
    _ => 'Telegram',
  };
  static String email(Locale l) => switch (l.languageCode) {
    'ru' => 'Электронная почта',
    'en' => 'Email',
    _ => 'Elektron pochta',
  };
  static String phone(Locale l) => switch (l.languageCode) {
    'ru' => 'Телефон',
    'en' => 'Phone',
    _ => 'Telefon',
  };

  static List<({String q, String a})> faqs(
    Locale l,
  ) => switch (l.languageCode) {
    'ru' => const [
      (
        q: 'Как сделать 3D-сканирование объекта?',
        a: 'Откройте раздел «Услуги» → «3D Кадастр», введите кадастровый номер и следуйте инструкциям. Сканирование работает с камерой LiDAR (iOS) и эквивалентом на Android.',
      ),
      (
        q: 'Сколько стоит AI-оценка?',
        a: 'Стоимость зависит от типа объекта и тарифа. Точную сумму вы увидите в карточке объекта перед оплатой.',
      ),
      (
        q: 'Какие методы оплаты поддерживаются?',
        a: 'Мы принимаем оплату через Click, Payme и Uzum.',
      ),
      (
        q: 'Сохраняется ли мой 3D-скан приватным?',
        a: 'Да. Все ваши сканы доступны только в вашем личном кабинете и не показываются другим пользователям.',
      ),
      (
        q: 'Можно ли войти с нескольких устройств?',
        a: 'Активная сессия может быть только на одном устройстве. Вход с нового устройства автоматически завершит предыдущую сессию.',
      ),
    ],
    'en' => const [
      (
        q: 'How do I 3D-scan an object?',
        a: 'Open Services → 3D Kadastr, enter the cadastre number and follow the instructions. Scanning uses the LiDAR camera on iOS and an equivalent technology on Android.',
      ),
      (
        q: 'How much does an AI valuation cost?',
        a: 'Pricing depends on the object type and tariff. The exact amount appears in the object card before payment.',
      ),
      (
        q: 'Which payment methods are supported?',
        a: 'We accept Click, Payme and Uzum.',
      ),
      (
        q: 'Are my 3D scans kept private?',
        a: 'Yes. All your scans live in your personal cabinet and are never visible to other users.',
      ),
      (
        q: 'Can I sign in on multiple devices?',
        a: 'Only one active session is allowed. Signing in from a new device automatically ends the previous session.',
      ),
    ],
    _ => const [
      (
        q: 'Obyektni 3D skan qilish qanday amalga oshiriladi?',
        a: '«Xizmatlar» → «3D Kadastr» bo‘limini oching, kadastr raqamini kiriting va ko‘rsatmalarga amal qiling. Skan iOS qurilmalarda LiDAR kamerasi, Android qurilmalarda esa ekvivalent texnologiya bilan ishlaydi.',
      ),
      (
        q: 'AI baholash narxi qancha?',
        a: 'Narx obyekt turi va tarifga bog‘liq. Aniq summani to‘lovdan oldin obyekt kartochkasida ko‘rasiz.',
      ),
      (
        q: 'Qanday to‘lov usullari qo‘llab-quvvatlanadi?',
        a: 'Click, Payme va Uzum orqali to‘lov qabul qilamiz.',
      ),
      (
        q: '3D skanlarim maxfiy saqlanadimi?',
        a: 'Ha. Barcha skanlaringiz faqat shaxsiy kabinetingizda saqlanadi va boshqa foydalanuvchilarga ochilmaydi.',
      ),
      (
        q: 'Bir nechta qurilmadan kirish mumkinmi?',
        a: 'Faqat bitta faol sessiyaga ruxsat beriladi. Yangi qurilmadan kirilganda avvalgi sessiya avtomatik yakunlanadi.',
      ),
    ],
  };
}
