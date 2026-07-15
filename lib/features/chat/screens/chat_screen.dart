import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';
import '../../home/user_profile.dart';
import '../api_chat_service.dart';
import '../models/chat_message.dart';

/// 3D Kadastr yordamchi bot ekrani — streaming FAQ chat.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.locale = const Locale('uz')});

  final Locale locale;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ChatApiService _api = ChatApiService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];

  int? _conversationId;
  bool _sending = false;
  double _lastInset = 0;

  String get _lang => widget.locale.languageCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Klaviatura ochilganda kontentni tepaga suramiz (iMessage uslubi):
  /// oxirgi xabar har doim klaviatura ustida ko'rinib turadi.
  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final inset = MediaQuery.of(context).viewInsets.bottom;
      final opening = inset > _lastInset;
      _lastInset = inset;
      if (opening) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Top→bottom oqim: yangi kontent kelganda eng pastga ergashamiz, lekin
  /// foydalanuvchi yuqoriga scroll qilib tarixni o'qiyotgan bo'lsa, majburlamaymiz.
  void _followBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final atBottom = pos.maxScrollExtent - pos.pixels < 160;
      if (atBottom) pos.jumpTo(pos.maxScrollExtent);
    });
  }

  /// Xabar yuborilganda har doim pastga o'tamiz (yangi savol + javob).
  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;

    final assistant =
        ChatMessage(role: ChatRole.assistant, content: '', isStreaming: true);
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, content: text));
      _messages.add(assistant);
      _sending = true;
    });
    _input.clear();
    _jumpToBottom();

    try {
      await for (final ev in _api.streamReply(
        message: text,
        conversationId: _conversationId,
        lang: _lang,
      )) {
        if (!mounted) return;
        switch (ev.type) {
          case 'meta':
            _conversationId = ev.conversationId ?? _conversationId;
          case 'delta':
            setState(() => assistant.content += ev.content ?? '');
            _followBottom();
          case 'error':
            setState(() {
              final sep = assistant.content.isEmpty ? '' : '\n\n';
              assistant.content += sep + (ev.content ?? _S.errorGeneric(_lang));
            });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (assistant.content.isEmpty) {
            assistant.content = _S.errorConnect(_lang);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          assistant.isStreaming = false;
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    final fg = isDark ? Colors.white : AppColors.textBlack;

    final media = MediaQuery.of(context);
    // Capsule (8 + 36 row + 8 + 2 border = 54) + its 6/10 padding, plus
    // whatever the home indicator takes. Measured, not guessed — this drives
    // the list's bottom padding, so an under-estimate parks messages under the
    // capsule.
    final inputH = 70.0 + media.padding.bottom;
    final hairline = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        // Solid bar with a hairline. A fade can't do this job at the top: it
        // has to dissolve saturated green user bubbles into the canvas, and any
        // gradient across a solid colour block reads as a rendering fault. The
        // bottom fade works precisely because it only ever dissolves near-white
        // assistant bubbles into a near-white canvas.
        backgroundColor: bg,
        shape: Border(bottom: BorderSide(color: hairline)),
        foregroundColor: fg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        // Must be explicit: AppBar infers the status-bar style from its own
        // background, and a transparent bar infers "dark", which paints white
        // clock/icons onto the light canvas. `dark` here means dark icons.
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        // Explicit: AppBarTheme.titleTextStyle hardcodes white, and it wins
        // over foregroundColor — which rendered a white title on the old white
        // bar in light mode.
        titleTextStyle: TextStyle(
          fontFamily: 'MTSCompact',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
        title: Row(
          children: [
            Text(_S.title(_lang)),
            const SizedBox(width: 8),
            // Live dot — the assistant is reachable.
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.splashGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.splashGreen, blurRadius: 7),
                ],
              ),
            ),
          ],
        ),
      ),
      // The input floats *over* the list rather than sitting beside it in a
      // Column — that's what lets messages dissolve behind it instead of being
      // guillotined at the list's edge.
      body: Stack(
        children: [
          Positioned.fill(child: _AmbientWash(isDark: isDark)),
          Positioned.fill(
            child: _messages.isEmpty
                ? _EmptyState(
                    lang: _lang,
                    isDark: isDark,
                    onPick: _send,
                    topInset: 12,
                    bottomInset: inputH,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(12, 16, 12, inputH + 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) =>
                        _Bubble(message: _messages[i], isDark: isDark),
                  ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: inputH + 36,
            // Solid up to the capsule's top edge (inputH - 6), then a 42px tail.
            child: _EdgeFade(
              color: bg,
              solidUntil: (inputH - 6) / (inputH + 36),
              fromBottom: true,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _InputBar(
              controller: _input,
              isDark: isDark,
              enabled: !_sending,
              hint: _S.hint(_lang),
              onSend: _send,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dissolves the list into the canvas at an edge: opaque where the title or the
/// input sits, fading to nothing over a short tail.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({
    required this.color,
    required this.solidUntil,
    this.fromBottom = false,
  });

  final Color color;

  /// Fraction of the height (measured from the opaque edge) that stays solid.
  final double solidUntil;
  final bool fromBottom;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromBottom ? Alignment.bottomCenter : Alignment.topCenter,
            end: fromBottom ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [color, color, color.withValues(alpha: 0)],
            stops: [0, solidUntil.clamp(0.0, 1.0), 1],
          ),
        ),
      ),
    );
  }
}

/// Barely-there green blooms behind the content.
///
/// Deliberately at the edge of perception — flat black reads as a void, and a
/// couple of soft washes give the page depth without adding anything the eye
/// can name. Plain radial gradients, no blur, so it costs nothing to draw.
class _AmbientWash extends StatelessWidget {
  const _AmbientWash({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Light mode needs less: the wash is fighting a bright scaffold, and any
    // more than a whisper turns into a visible green smudge.
    final strong = isDark ? 0.11 : 0.07;
    final soft = isDark ? 0.07 : 0.045;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -150,
            right: -120,
            width: 400,
            height: 400,
            child: _Bloom(alpha: strong),
          ),
          Positioned(
            bottom: -110,
            left: -140,
            width: 380,
            height: 380,
            child: _Bloom(alpha: soft),
          ),
          // Floor glow — sits under the input capsule so it reads as lit.
          Positioned(
            bottom: -200,
            left: -40,
            right: -40,
            height: 380,
            child: _Bloom(alpha: soft),
          ),
        ],
      ),
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom({required this.alpha});

  final double alpha;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.splashGreen.withValues(alpha: alpha),
            AppColors.splashGreen.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isDark});
  final ChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubbleColor = isUser
        ? AppColors.splashGreen
        : (isDark ? AppColors.darkSurface : Colors.white);
    final textColor = isUser
        ? AppColors.greenBlack
        : (isDark ? Colors.white : AppColors.textBlack);
    final showDots = message.isStreaming && message.content.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: showDots
              ? Text('•••',
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.5), fontSize: 16))
              : SelectableText(
                  message.content,
                  style:
                      TextStyle(color: textColor, fontSize: 15, height: 1.35),
                ),
        ),
      ),
    );
  }
}

/// Floating glass capsule. Detached from the edge and blurred so it lifts off
/// the page: on a deliberately quiet screen it should be the one object that
/// clearly invites a tap. Focus lights the ring green.
class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.isDark,
    required this.enabled,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isDark;
  final bool enabled;
  final String hint;
  final ValueChanged<String> onSend;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final FocusNode _focus = FocusNode();
  bool _hasText = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _onFocus() => setState(() => _focused = _focus.hasFocus);

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final controller = widget.controller;
    final enabled = widget.enabled;
    final onSend = widget.onSend;

    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final glass = isDark
        ? const Color(0xFF121A15).withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.78);
    final idleBorder = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.black.withValues(alpha: 0.09);
    // Send only lights up when there's something to send.
    final canSend = enabled && _hasText;
    final radius = BorderRadius.circular(26);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: DecoratedBox(
          // Outside the clip — the ClipRRect would eat these shadows.
          // Kept tight and low: a wide, soft drop plus a wide focus glow read
          // as a halo around the capsule rather than as depth under it.
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.07),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              // Focus is carried by the green border; this is only a hint of
              // bloom behind it, not a light source.
              if (_focused)
                BoxShadow(
                  color: AppColors.splashGreen.withValues(alpha: 0.10),
                  blurRadius: 10,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  color: glass,
                  borderRadius: radius,
                  border: Border.all(
                    color: _focused
                        ? AppColors.splashGreen.withValues(alpha: 0.45)
                        : idleBorder,
                  ),
                ),
                child: Row(
                  // Bottom-aligned so the button stays put as the field grows.
                  // Only works out because a single-line field is padded to the
                  // button's own height (see contentPadding below) — otherwise
                  // "bottom" reads as "a few px below centre" on one line.
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: _focus,
                        enabled: enabled,
                        minLines: 1,
                        maxLines: 4,
                        // Return inserts a newline; sending is the button's job.
                        // With TextInputAction.send the return key submitted
                        // instead, so maxLines: 4 was unreachable by typing.
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                // iOS'da bo'sh maydonni uzun bosganda faqat "Scan Text"
                // chiqadi — "Paste"ni menyuga majburan qo'shamiz.
                contextMenuBuilder: (context, editableTextState) {
                  final items = List<ContextMenuButtonItem>.from(
                    editableTextState.contextMenuButtonItems,
                  );
                  final hasPaste = items.any(
                    (b) => b.type == ContextMenuButtonType.paste,
                  );
                  if (!hasPaste) {
                    items.insert(
                      0,
                      ContextMenuButtonItem(
                        type: ContextMenuButtonType.paste,
                        onPressed: () => editableTextState
                            .pasteText(SelectionChangedCause.toolbar),
                      ),
                    );
                  }
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: items,
                  );
                },
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          color: textColor,
                          fontSize: 14.5,
                          height: 1.3,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          hintStyle: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 14.5,
                            color: textColor.withValues(alpha: 0.38),
                          ),
                          isDense: true,
                          filled: false,
                          // Tuned so a one-line field measures the same 36dp as
                          // the send button, which is what keeps the button
                          // optically centred. Verified by measurement, not eye.
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8.5,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: hapticTap(
                        canSend ? () => onSend(controller.text) : null,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: canSend
                              ? AppColors.splashGreen
                              : textColor.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 19,
                          color: canSend
                              ? AppColors.greenBlack
                              : textColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Typographic empty state: no avatar, no illustration. The greeting is the
/// hero and the suggestions are plain rows — nothing to render, nothing to
/// load, and it stays legible whatever the theme.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.lang,
    required this.isDark,
    required this.onPick,
    required this.topInset,
    required this.bottomInset,
  });

  final String lang;
  final bool isDark;
  final ValueChanged<String> onPick;

  /// The header and the floating input overlay this list, so it pads itself
  /// clear of both.
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final strong = isDark ? Colors.white : AppColors.textBlack;
    final muted = strong.withValues(alpha: 0.32);
    final divider = strong.withValues(alpha: 0.08);
    final suggestions = _S.suggestions(lang);

    return ValueListenableBuilder<UserProfile?>(
      valueListenable: userProfileNotifier,
      builder: (context, profile, _) {
        final name = profile?.name.trim();
        return ListView(
          padding: EdgeInsets.fromLTRB(20, topInset + 20, 20, bottomInset + 16),
          children: [
            Text(
              _S.kicker(lang),
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.splashGreen,
              ),
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${_S.greetLead(lang, name)}\n',
                    style: TextStyle(color: strong),
                  ),
                  TextSpan(
                    text: _S.greetAsk(lang),
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.12,
                letterSpacing: -1,
              ),
            ),
            // Align, not a bare Container: ListView hands children tight
            // horizontal constraints, so width: 34 alone stretches full-bleed.
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 34,
                height: 2,
                margin: const EdgeInsets.only(top: 22, bottom: 6),
                color: AppColors.splashGreen,
              ),
            ),
            for (var i = 0; i < suggestions.length; i++)
              InkWell(
                onTap: hapticTap(() => onPick(suggestions[i])),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    border: i == suggestions.length - 1
                        ? null
                        : Border(bottom: BorderSide(color: divider)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          suggestions[i],
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: strong.withValues(alpha: 0.82),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: AppColors.splashGreen.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// uz / ru / en matnlar.
class _S {
  const _S._();

  static String _p(String l, String uz, String ru, String en) =>
      switch (l) { 'ru' => ru, 'en' => en, _ => uz };

  static String title(String l) => _p(l, 'Yordamchi', 'Помощник', 'Assistant');

  static String hint(String l) => _p(l, 'Savolingizni yozing...',
      'Введите вопрос...', 'Type your question...');

  static String kicker(String l) => '3D KADASTR AI';

  /// "Salom, Ilxomjon." — falls back to a plain greeting for guests, and for
  /// anyone whose profile hasn't loaded yet.
  static String greetLead(String l, String? name) {
    if (name == null || name.isEmpty) {
      return _p(l, 'Salom!', 'Здравствуйте!', 'Hello!');
    }
    return _p(l, 'Salom, $name.', 'Здравствуйте, $name.', 'Hello, $name.');
  }

  static String greetAsk(String l) => _p(
        l,
        'Nima bilan yordam beray?',
        'Чем могу помочь?',
        'How can I help?',
      );

  static String errorConnect(String l) => _p(
        l,
        "Serverga ulanib bo'lmadi. WiFi va server ishlayotganini tekshiring.",
        'Не удалось подключиться к серверу. Проверьте WiFi и сервер.',
        'Could not connect to the server. Check WiFi and the server.',
      );

  static String errorGeneric(String l) =>
      _p(l, 'Xatolik yuz berdi.', 'Произошла ошибка.', 'An error occurred.');

  static List<String> suggestions(String l) => switch (l) {
        'ru' => const [
            'Сколько стоит дизайн-проект?',
            'За сколько дней готов кадастровый паспорт?',
            'Какие у вас услуги?',
          ],
        'en' => const [
            'How much is a design project?',
            'How long does a cadastre passport take?',
            'What services do you offer?',
          ],
        _ => const [
            'Dizayn loyiha narxi qancha?',
            'Kadastr pasporti necha kunda tayyor?',
            'Qanday xizmatlar bor?',
          ],
      };
}
