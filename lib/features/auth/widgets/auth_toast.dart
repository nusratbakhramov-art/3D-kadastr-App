import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

enum AuthToastVariant { error, success }

/// Shows a floating, auto-dismissing toast at the top of the screen via Overlay.
/// Safe to call multiple times — previous toast is replaced.
class AuthToasts {
  const AuthToasts._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static final GlobalKey<_AuthToastOverlayState> _overlayKey =
      GlobalKey<_AuthToastOverlayState>();

  static void show(
    BuildContext context, {
    required String message,
    AuthToastVariant variant = AuthToastVariant.error,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // If a toast is already visible, just update it.
    final existing = _overlayKey.currentState;
    if (_entry != null && existing != null && existing.mounted) {
      existing.update(message: message, variant: variant);
      _timer?.cancel();
      _timer = Timer(duration, dismiss);
      return;
    }

    final entry = OverlayEntry(
      builder: (_) => _AuthToastOverlay(
        key: _overlayKey,
        initialMessage: message,
        initialVariant: variant,
        onDismissed: _removeEntry,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer?.cancel();
    _timer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _overlayKey.currentState?.dismiss();
  }

  static void _removeEntry() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _AuthToastOverlay extends StatefulWidget {
  const _AuthToastOverlay({
    super.key,
    required this.initialMessage,
    required this.initialVariant,
    required this.onDismissed,
  });

  final String initialMessage;
  final AuthToastVariant initialVariant;
  final VoidCallback onDismissed;

  @override
  State<_AuthToastOverlay> createState() => _AuthToastOverlayState();
}

class _AuthToastOverlayState extends State<_AuthToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late String _message = widget.initialMessage;
  late AuthToastVariant _variant = widget.initialVariant;

  @override
  void initState() {
    super.initState();
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void update({required String message, required AuthToastVariant variant}) {
    setState(() {
      _message = message;
      _variant = variant;
    });
  }

  Future<void> dismiss() async {
    if (!mounted) return;
    await _anim.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 0),
            child: Material(
              color: Colors.transparent,
              child: _SwipeToDismiss(
                onDismiss: dismiss,
                child: _ToastBody(
                  message: _message,
                  variant: _variant,
                  onDismiss: dismiss,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS → swipe up dismisses. Android → swipe right dismisses.
/// Other platforms → no drag dismiss (only tap-X works).
class _SwipeToDismiss extends StatefulWidget {
  const _SwipeToDismiss({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<_SwipeToDismiss> createState() => _SwipeToDismissState();
}

enum _SwipeAxis { vertical, horizontal, none }

class _SwipeToDismissState extends State<_SwipeToDismiss> {
  static const double _threshold = 40;
  static const double _velocity = 500;

  Offset _offset = Offset.zero;
  bool _dismissing = false;

  _SwipeAxis get _axis {
    if (kIsWeb) return _SwipeAxis.none;
    if (Platform.isIOS) return _SwipeAxis.vertical;
    if (Platform.isAndroid) return _SwipeAxis.horizontal;
    return _SwipeAxis.none;
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    if (_dismissing) return;
    setState(() {
      final dy = (_offset.dy + d.delta.dy).clamp(-200.0, 0.0);
      _offset = Offset(0, dy);
    });
  }

  void _onVerticalEnd(DragEndDetails d) {
    if (_dismissing) return;
    final v = d.velocity.pixelsPerSecond.dy;
    if (_offset.dy <= -_threshold || v <= -_velocity) {
      _dismissing = true;
      widget.onDismiss();
    } else {
      setState(() => _offset = Offset.zero);
    }
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    if (_dismissing) return;
    setState(() {
      final dx = (_offset.dx + d.delta.dx).clamp(0.0, 400.0);
      _offset = Offset(dx, 0);
    });
  }

  void _onHorizontalEnd(DragEndDetails d) {
    if (_dismissing) return;
    final v = d.velocity.pixelsPerSecond.dx;
    if (_offset.dx >= _threshold || v >= _velocity) {
      _dismissing = true;
      widget.onDismiss();
    } else {
      setState(() => _offset = Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final axis = _axis;
    Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0),
      child: widget.child,
    );
    switch (axis) {
      case _SwipeAxis.vertical:
        child = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _onVerticalUpdate,
          onVerticalDragEnd: _onVerticalEnd,
          child: child,
        );
      case _SwipeAxis.horizontal:
        child = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _onHorizontalUpdate,
          onHorizontalDragEnd: _onHorizontalEnd,
          child: child,
        );
      case _SwipeAxis.none:
        break;
    }
    return child;
  }
}

class _ToastBody extends StatelessWidget {
  const _ToastBody({
    required this.message,
    required this.variant,
    required this.onDismiss,
  });

  final String message;
  final AuthToastVariant variant;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isError = variant == AuthToastVariant.error;
    final bg = isError ? const Color(0xFFE74C4C) : AppColors.splashGreen;
    final fg = isError ? Colors.white : Colors.black;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.info_outline : Icons.check_circle,
            color: fg,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.close, color: fg, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight inline version — still available for tests or custom layouts.
class AuthToast extends StatelessWidget {
  const AuthToast({
    super.key,
    required this.message,
    required this.variant,
    this.onDismiss,
  });

  final String message;
  final AuthToastVariant variant;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return _ToastBody(
      message: message,
      variant: variant,
      onDismiss: onDismiss ?? () {},
    );
  }
}
