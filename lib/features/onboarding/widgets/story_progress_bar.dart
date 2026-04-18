import 'package:flutter/material.dart';

class StoryProgressBar extends StatelessWidget {
  const StoryProgressBar({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.progress,
    this.spacing = 5,
    this.height = 2,
  });

  final int count;
  final int currentIndex;
  final Animation<double> progress;
  final double spacing;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          Expanded(
            child: _Segment(
              height: height,
              fill: i < currentIndex
                  ? const AlwaysStoppedAnimation<double>(1)
                  : i == currentIndex
                  ? progress
                  : const AlwaysStoppedAnimation<double>(0),
            ),
          ),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.height, required this.fill});

  final double height;
  final Animation<double> fill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x1FFFFFFF)),
            AnimatedBuilder(
              animation: fill,
              builder: (context, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill.value.clamp(0.0, 1.0),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
