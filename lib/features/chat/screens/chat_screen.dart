import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../api_chat_service.dart';
import '../models/chat_message.dart';

/// 3D Kadastr yordamchi bot ekrani — streaming FAQ chat.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.locale = const Locale('uz')});

  final Locale locale;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatApiService _api = ChatApiService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];

  int? _conversationId;
  bool _sending = false;

  String get _lang => widget.locale.languageCode;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 220),
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
    _scrollToBottom();

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
            _scrollToBottom();
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
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.greenBlack : Colors.white,
        foregroundColor: isDark ? Colors.white : AppColors.textBlack,
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.splashGreen,
              child: Icon(Icons.support_agent_rounded,
                  size: 19, color: AppColors.greenBlack),
            ),
            const SizedBox(width: 10),
            Text(
              _S.title(_lang),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(lang: _lang, isDark: isDark, onPick: _send)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) =>
                        _Bubble(message: _messages[i], isDark: isDark),
                  ),
          ),
          _InputBar(
            controller: _input,
            isDark: isDark,
            enabled: !_sending,
            hint: _S.hint(_lang),
            onSend: _send,
          ),
        ],
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
                      color: textColor.withOpacity(0.5), fontSize: 16))
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

class _InputBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final fieldBg = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: enabled ? onSend : null,
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
                style: TextStyle(color: textColor, fontSize: 15),
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: enabled ? () => onSend(controller.text) : null,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: enabled
                      ? AppColors.splashGreen
                      : AppColors.splashGreen.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: AppColors.greenBlack),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.lang,
    required this.isDark,
    required this.onPick,
  });

  final String lang;
  final bool isDark;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark ? AppColors.darkTextSecondary : Colors.black54;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.splashGreen,
            child: const Icon(Icons.support_agent_rounded,
                size: 36, color: AppColors.greenBlack),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _S.greetingTitle(lang),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: textColor, fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _S.greetingBody(lang),
          textAlign: TextAlign.center,
          style: TextStyle(color: subColor, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 24),
        ..._S.suggestions(lang).map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => onPick(q),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            isDark ? AppColors.darkOutline : AppColors.outline,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt_rounded,
                            size: 18, color: AppColors.splashGreen),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(q,
                              style: TextStyle(
                                  color: textColor, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
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

  static String greetingTitle(String l) =>
      _p(l, 'Salom! 👋', 'Здравствуйте! 👋', 'Hello! 👋');

  static String greetingBody(String l) => _p(
        l,
        "3D Kadastr yordamchisiman. Xizmatlar, narxlar, kadastr va dizayn loyihalari bo'yicha savol bering.",
        'Я помощник 3D Kadastr. Спросите об услугах, ценах, кадастре и дизайн-проектах.',
        'I am the 3D Kadastr assistant. Ask about services, prices, cadastre and design projects.',
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
