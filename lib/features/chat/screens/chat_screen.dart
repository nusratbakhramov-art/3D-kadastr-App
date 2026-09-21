import 'dart:async' show Completer, StreamSubscription, Timer, unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../core/network_error_handler.dart';
import '../../../theme/app_colors.dart';
import '../../home/user_profile.dart';
import '../api_chat_service.dart';
import '../data/chat_suggestions_store.dart';
import '../models/chat_message.dart';

/// 3D kadastr yordamchi bot ekrani — streaming FAQ chat.
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

  /// Keshli backend takliflari (joriy til). Bo'sh bo'lsa (hali yuklanmagan yoki
  /// xato) `_defaultSuggestions` zaxira ro'yxati ishlatiladi. Manba —
  /// [chatSuggestionsNotifier] (app startida prefetch qilinadi, versiya bo'yicha
  /// keshlanadi).
  List<String>? _remoteSuggestions;

  /// Held so the reply can actually be cancelled. An `await for` loop can only
  /// break when the *next* event arrives, which is useless for a stop button —
  /// a stalled stream would ignore it.
  StreamSubscription<ChatStreamEvent>? _sub;
  Completer<void>? _done;
  bool _stopped = false;

  String get _lang => widget.locale.languageCode;

  /// Zaxira boshlang'ich takliflar — backend ro'yxati bo'sh/yuklanmagan holatda.
  List<String> get _defaultSuggestions => [
        tr(widget.locale, 'chat.suggestion_1'),
        tr(widget.locale, 'chat.suggestion_2'),
        tr(widget.locale, 'chat.suggestion_3'),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keshli takliflardan darhol o'qiymiz; app-start prefetch odatda allaqachon
    // to'ldirgan bo'ladi. Notifier'ni tinglaymiz, fonda yangilanish kelsa
    // ro'yxat o'zi yangilanadi.
    _remoteSuggestions = chatSuggestionsNotifier.value.forLocale(_lang);
    chatSuggestionsNotifier.addListener(_onSuggestionsChanged);
    // Chat ochilganda ham versiyani tekshiramiz (arzon — o'zgargan bo'lsagina
    // to'liq ro'yxat yuklanadi). Fire-and-forget.
    unawaited(ChatSuggestionsStore.instance.refresh());
  }

  void _onSuggestionsChanged() {
    if (!mounted) return;
    setState(
      () => _remoteSuggestions = chatSuggestionsNotifier.value.forLocale(_lang),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chatSuggestionsNotifier.removeListener(_onSuggestionsChanged);
    _sub?.cancel();
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

    final done = Completer<void>();
    _done = done;
    _stopped = false;

    // Xato — bot javobi EMAS. Shuning uchun u assistant matniga qo'shilmaydi,
    // alohida qator bo'lib chiqadi. Oqim yarim yo'lda uzilgan bo'lsa, kelgan
    // matn saqlanadi: u haqiqiy javobning bo'lagi, uni o'chirish ma'nosiz.
    void showError(String message, {bool retryable = true}) {
      if (!mounted) return;
      setState(() {
        if (assistant.content.isEmpty) {
          _messages.remove(assistant);
        } else {
          assistant.isStreaming = false;
        }
        _messages.add(
          ChatMessage.error(message, retryPrompt: retryable ? text : null),
        );
      });
      _followBottom();
    }

    _sub = _api
        .streamReply(
          message: text,
          conversationId: _conversationId,
          lang: _lang,
        )
        .listen(
          (ev) {
            if (!mounted) return;
            switch (ev.type) {
              case 'meta':
                _conversationId = ev.conversationId ?? _conversationId;
              case 'delta':
                setState(() => assistant.content += ev.content ?? '');
                _followBottom();
              case 'error':
                showError(
                  ev.content ?? tr(widget.locale, 'chat.error_generic'),
                  retryable: ev.retryable,
                );
            }
          },
          onError: (Object e) {
            // Oqim yarim yo'lda uzilsa ham xabar beramiz. Avval bu holat
            // jim yutilardi (faqat matn bo'sh bo'lsagina ko'rsatilardi) —
            // natijada yarim javob TUGAGAN javobga o'xshab qolardi.
            if (!_stopped) {
              showError(
                NetworkErrorHandler.isNetworkError(e)
                    ? tr(widget.locale, 'chat.error_connect')
                    : tr(widget.locale, 'chat.error_generic'),
              );
            }
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );

    await done.future;
    await _sub?.cancel();
    _sub = null;
    _done = null;

    if (mounted) {
      setState(() {
        assistant.isStreaming = false;
        // Stopped before a single token landed — drop the turn rather than
        // leave an empty bubble sitting there.
        if (_stopped && assistant.content.isEmpty) _messages.remove(assistant);
        _sending = false;
      });
    }
    _stopped = false;
  }

  /// Xato qatoridagi "Qayta urinish": xato qatorini ham, unga tegishli savolni
  /// ham olib tashlab, savolni qaytadan yuboradi — shunda tarixda takrorlangan
  /// savol ham, o'lik xato qatori ham qolmaydi.
  void _retry(ChatMessage errorMessage) {
    final prompt = errorMessage.retryPrompt;
    if (prompt == null || _sending) return;
    setState(() {
      _messages.remove(errorMessage);
      // Faqat savol oxirgi qatorda turgan bo'lsa olib tashlaymiz. Yarim
      // kelgan javob bo'lsa — savol o'sha javobning tepasida turibdi, uni
      // olib tashlash javobni ega'siz qoldiradi; u holda yangi tur ochamiz.
      final last = _messages.isEmpty ? null : _messages.last;
      if (last != null && last.isUser && last.content == prompt) {
        _messages.removeLast();
      }
    });
    _send(prompt);
  }

  /// Cancels an in-flight reply. Keeps whatever already streamed in.
  void _stop() {
    if (!_sending) return;
    _stopped = true;
    _sub?.cancel();
    _sub = null;
    // Releases the awaiting _send, which does the cleanup in one place.
    if (_done?.isCompleted == false) _done!.complete();
  }

  /// Clears the thread and forgets the server-side conversation, so the next
  /// question starts fresh instead of inheriting the whole history.
  void _newChat() {
    _stop();
    setState(() {
      _messages.clear();
      _conversationId = null;
    });
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
        // Smaller than the app's 20dp bars — this header is meant to recede.
        // The colour has to be repeated: naming titleTextStyle at all blocks
        // foregroundColor from reaching the title (AppBar only applies it to
        // the *defaults*), so omitting it here leaves the title colourless.
        titleTextStyle: TextStyle(
          fontFamily: 'MTSCompact',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
        title: Row(
          children: [
            Text(tr(widget.locale, 'chat.title')),
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
        actions: [
          // Only offered once there's a thread to clear.
          if (_messages.isNotEmpty)
            IconButton(
              onPressed: hapticTap(_newChat),
              tooltip: tr(widget.locale, 'chat.new_chat'),
              icon: const Icon(Icons.edit_square, size: 20),
            ),
        ],
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
                    suggestions:
                        (_remoteSuggestions != null &&
                            _remoteSuggestions!.isNotEmpty)
                        ? _remoteSuggestions!
                        : _defaultSuggestions,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(12, 16, 12, inputH + 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _Bubble(
                      message: _messages[i],
                      isDark: isDark,
                      lang: _lang,
                      locale: widget.locale,
                      onRetry: _retry,
                    ),
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
              sending: _sending,
              hint: tr(widget.locale, 'chat.hint'),
              onSend: _send,
              onStop: _stop,
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
  const _Bubble({
    required this.message,
    required this.isDark,
    required this.lang,
    required this.locale,
    required this.onRetry,
  });
  final ChatMessage message;
  final bool isDark;
  final String lang;
  final Locale locale;
  final void Function(ChatMessage) onRetry;

  @override
  Widget build(BuildContext context) {
    if (message.isError) {
      return _ErrorRow(
        message: message,
        isDark: isDark,
        locale: locale,
        onRetry: onRetry,
      );
    }

    // Waiting on the first token: show the working indicator bare, not wrapped
    // in a bubble — there's no message yet, so a bubble would be a lie.
    if (message.isStreaming && message.content.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _ThinkingRow(isDark: isDark, lang: lang),
        ),
      );
    }

    final isUser = message.isUser;
    final bubbleColor = isUser
        ? AppColors.splashGreen
        : (isDark ? AppColors.darkSurface : Colors.white);
    final textColor = isUser
        ? AppColors.greenBlack
        : (isDark ? Colors.white : AppColors.textBlack);

    // The assistant writes paragraphs, so its reply is set as a document, not
    // a text message: full width, no bubble, the mark alongside. A 78%-wide
    // bubble is what made long answers feel cramped. Only the user — who sends
    // short lines — keeps a bubble.
    if (!isUser) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: _BotMark(size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              // The model replies in markdown (bold labels, numbered steps).
              // Render it so `**...**` and lists format instead of showing raw
              // asterisks. SelectionArea keeps the text copyable like the old
              // SelectableText did. gpt_markdown tolerates half-typed markdown
              // mid-stream, so it stays clean while the answer streams in.
              child: SelectionArea(
                child: GptMarkdown(
                  message.content,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

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
          child: SelectableText(
            message.content,
            style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
          ),
        ),
      ),
    );
  }
}

/// Bot javobining yonidagi belgi — ILOVANING LOGOSI.
///
/// ⚠️ Ilgari bu yerda `assets/icons/tab-home.svg` yashil rangga bo'yalib
/// turardi: u pastki menyudagi "Bosh sahifa" ikonkasi, ya'ni suhbatda u
/// yordamchini emas, boshqa tugmani bildirardi. Endi mavjud brend assetidan
/// (`splash-logo.svg` — splash va «Ilova haqi» dagi bilan bir xil)
/// foydalanamiz; YANGI asset qo'shilmadi.
///
/// Logo KO'P RANGLI — `colorFilter` ATAYLAB YO'Q, aks holda gradient bir
/// tekis dog'ga aylanardi.
class _BotMark extends StatelessWidget {
  const _BotMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/branding/splash-logo.svg',
    width: size,
    height: size,
  );
}

/// Xato qatori — ataylab bot javobiga o'xshamaydi: brend belgisi yo'q, fon
/// qizg'ish, matn chapdan to'liq kenglikda emas. Foydalanuvchi buni "bot shuni
/// aytdi" deb emas, "yubormadi" deb o'qishi kerak.
class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    required this.message,
    required this.isDark,
    required this.locale,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool isDark;
  final Locale locale;
  final void Function(ChatMessage) onRetry;

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.declineRed;
    final bg = accent.withValues(alpha: isDark ? 0.14 : 0.07);
    final border = accent.withValues(alpha: isDark ? 0.30 : 0.20);
    final textColor = isDark ? const Color(0xFFFFB4AE) : const Color(0xFFA32D2D);
    final canRetry = message.retryPrompt != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 17, color: textColor),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (canRetry) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: hapticTap(() => onRetry(message)),
                  icon: Icon(Icons.refresh_rounded, size: 16, color: textColor),
                  label: Text(
                    tr(locale, 'chat.retry'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                      side: BorderSide(color: border, width: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Working indicator: the brand mark sits still, the label shimmers, and the
/// elapsed seconds tick alongside.
///
/// The seconds are the point. Before this, a slow reply looked identical to a
/// hang — the UI just froze behind a "•••" with nothing to say it was alive.
/// The shimmer carries the motion, so the mark never has to rotate (it's a
/// house — it has an "up", and spinning it reads wrong).
class _ThinkingRow extends StatefulWidget {
  const _ThinkingRow({required this.isDark, required this.lang});

  final bool isDark;
  final String lang;

  @override
  State<_ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<_ThinkingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  Timer? _tick;

  /// Counted from the timer's own ticks rather than a Stopwatch: a Stopwatch
  /// reads wall-clock time, which no widget test can advance, so the label
  /// would be untestable. Drift across one answer is not worth caring about.
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    // Only rebuilds the counter; the shimmer rides its own controller.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark
        ? Colors.white.withValues(alpha: 0.42)
        : Colors.black.withValues(alpha: 0.38);
    final highlight = widget.isDark
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.black.withValues(alpha: 0.88);
    final seconds = _seconds;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BotMark(size: 20),
          const SizedBox(width: 9),
          AnimatedBuilder(
            animation: _shimmer,
            builder: (context, child) {
              // Highlight band slides from just off the left edge to just off
              // the right, so the sweep enters and leaves cleanly.
              final v = -0.3 + 1.6 * _shimmer.value;
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [base, highlight, base],
                  stops: [
                    (v - 0.28).clamp(0.0, 1.0),
                    v.clamp(0.0, 1.0),
                    (v + 0.28).clamp(0.0, 1.0),
                  ],
                ).createShader(bounds),
                child: child,
              );
            },
            // srcIn paints the gradient through the glyphs, so the child's own
            // colour just has to be opaque.
            child: Text(
              tr(Locale(widget.lang), 'chat.thinking'),
              style: const TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          // Only once it's worth mentioning — a "0s" that flashes and vanishes
          // is noise.
          if (seconds >= 1) ...[
            const SizedBox(width: 7),
            Text(
              '${seconds}s',
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 12,
                color: base,
              ),
            ),
          ],
        ],
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
    required this.sending,
    required this.hint,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isDark;
  final bool sending;
  final String hint;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

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
    final sending = widget.sending;
    final onSend = widget.onSend;

    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final glass = isDark
        ? const Color(0xFF121A15).withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.78);
    final idleBorder = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.black.withValues(alpha: 0.09);
    // Send only lights up when there's something to send.
    final canSend = !sending && _hasText;
    // While a reply streams the button becomes stop — always live, because a
    // stalled answer is exactly when you need it.
    final active = sending || canSend;
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
                        // Stays live while a reply streams — you can draft the
                        // next question; only sending is gated.
                        controller: controller,
                        focusNode: _focus,
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
                        sending
                            ? widget.onStop
                            : (canSend ? () => onSend(controller.text) : null),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.splashGreen
                              : textColor.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          sending
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          size: sending ? 20 : 19,
                          color: active
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
    required this.suggestions,
  });

  final String lang;
  final bool isDark;
  final ValueChanged<String> onPick;

  /// Ko'rsatiladigan taklif matnlari (backend'dan yoki zaxira ro'yxat).
  final List<String> suggestions;

  /// The header and the floating input overlay this list, so it pads itself
  /// clear of both.
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final strong = isDark ? Colors.white : AppColors.textBlack;
    final muted = strong.withValues(alpha: 0.32);
    final divider = strong.withValues(alpha: 0.08);

    return ValueListenableBuilder<UserProfile?>(
      valueListenable: userProfileNotifier,
      builder: (context, profile, _) {
        final name = profile?.name.trim();
        return ListView(
          padding: EdgeInsets.fromLTRB(20, topInset + 20, 20, bottomInset + 16),
          children: [
            Text(
              tr(Locale(lang), 'chat.kicker'),
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
                    text: '${_greetLead(lang, name)}\n',
                    style: TextStyle(color: strong),
                  ),
                  TextSpan(
                    text: tr(Locale(lang), 'chat.greet_ask'),
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

/// "Salom, Ilxomjon." — falls back to a plain greeting for guests, and for
/// anyone whose profile hasn't loaded yet. The `$name` placeholder is kept in
/// the backend value and substituted here.
String _greetLead(String lang, String? name) {
  final locale = Locale(lang);
  if (name == null || name.isEmpty) {
    return tr(locale, 'chat.greeting_guest');
  }
  return tr(locale, 'chat.greeting').replaceFirst(r'$name', name);
}
