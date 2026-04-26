import 'package:flutter/material.dart';

/// Fade + slide-up reveal driven by an [AnimationController]. Slot it in front
/// of any child and pass the same [controller] used by the screen.
class AppReveal extends StatelessWidget {
  const AppReveal({
    super.key,
    required this.controller,
    required this.interval,
    required this.child,
    this.slideY = 14,
    this.slideX = 0,
  });

  final AnimationController controller;
  final Interval interval;
  final Widget child;
  final double slideY;
  final double slideX;

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: controller, curve: interval);
    return AnimatedBuilder(
      animation: t,
      builder: (context, c) {
        return Opacity(
          opacity: t.value,
          child: Transform.translate(
            offset: Offset((1 - t.value) * slideX, (1 - t.value) * slideY),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

/// Mixin for screens that play a one-shot entry animation the first time they
/// become visible (driven by [animateToken] from a parent shell). Combine with
/// [AutomaticKeepAliveClientMixin] (returned `wantKeepAlive: true`) so State
/// survives tab swaps and the animation does not replay.
///
/// Usage:
/// ```
/// class _MyScreenState extends State<MyScreen>
///     with SingleTickerProviderStateMixin,
///         AutomaticKeepAliveClientMixin,
///         RevealEntryMixin<MyScreen> {
///   @override
///   bool get wantKeepAlive => true;
///   @override
///   int get currentToken => widget.animateToken;
/// }
/// ```
mixin RevealEntryMixin<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController entryController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: currentToken > 0 ? 0.0 : 1.0,
  );
  bool _hasPlayed = false;

  /// Override to return the parent-supplied token. When this transitions from
  /// 0 to >0 the first time, the controller plays once.
  int get currentToken;

  @override
  void initState() {
    super.initState();
    if (currentToken > 0) {
      _hasPlayed = true;
      entryController.forward();
    }
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasPlayed && currentToken > 0) {
      _hasPlayed = true;
      entryController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    entryController.dispose();
    super.dispose();
  }
}
