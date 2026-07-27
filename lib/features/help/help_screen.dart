import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
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
        final faqs = <({String q, String a})>[
          for (var i = 1; i <= 5; i++)
            (q: tr(locale, 'help.faq.q$i'), a: tr(locale, 'help.faq.a$i')),
        ];
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
                          rows: [
                            AppMenuRow(
                              icon: Icons.send_rounded,
                              label: tr(locale, 'help.telegram'),
                              trailing: const _ContactValue(
                                text: '@kadastr_bot',
                              ),
                              onTap: () {},
                            ),
                            AppMenuRow(
                              icon: Icons.mail_outline_rounded,
                              label: tr(locale, 'help.email'),
                              trailing: const _ContactValue(
                                text: 'support@example.uz',
                              ),
                              onTap: () {},
                            ),
                            AppMenuRow(
                              icon: Icons.call_outlined,
                              label: tr(locale, 'help.phone'),
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

