import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class OnboardingBackground extends StatelessWidget {
  const OnboardingBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.greenBlack,
      child: Stack(
        fit: StackFit.expand,
        children: [const _BottomBloom(), const _TopGlow(), ?child],
      ),
    );
  }
}

class _BottomBloom extends StatelessWidget {
  const _BottomBloom();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, 0.75),
            radius: 1.1,
            colors: [
              Color(0xFF78B890),
              Color(0xFF4FA06E),
              Color(0xFF2B7C45),
              Color(0xFF0F4A22),
              Color(0x00086D20),
            ],
            stops: [0.0, 0.22, 0.48, 0.72, 1.0],
          ),
        ),
      ),
    );
  }
}

class _TopGlow extends StatelessWidget {
  const _TopGlow();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -1.05),
            radius: 0.75,
            colors: [Color(0x33086D20), Color(0x00000702)],
            stops: [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}
