import 'package:flutter/widgets.dart';

/// Wraps [child] with a subtle press-down scale so taps feel responsive.
///
/// Uses a [Listener] (raw pointer events) rather than a gesture recognizer, so
/// it never competes in the gesture arena with an inner [InkWell] or
/// [GestureDetector] — the child keeps handling the actual tap (and ripple),
/// while this widget only drives the scale animation. Flutter caches the
/// hit-test result on pointer-down, so the matching up/cancel still reaches
/// this listener even if the finger drifts off the child or a scroll steals
/// the gesture, guaranteeing the scale always restores.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 110),
    this.enabled = true,
  });

  final Widget child;

  /// Scale applied while pressed (1.0 = no shrink).
  final double pressedScale;
  final Duration duration;

  /// When false, the child renders without any press animation.
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
