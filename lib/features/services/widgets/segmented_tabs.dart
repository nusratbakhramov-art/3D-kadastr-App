import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';

class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
  });

  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackBg = isDark ? const Color(0xFF1F2426) : const Color(0xFFEDEFF2);
    final activeBg = isDark ? const Color(0xFF2C3133) : Colors.white;
    final activeFg = isDark ? Colors.white : AppColors.textBlack;
    final idleFg = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final selectedIndex = values.indexOf(selected).clamp(0, values.length - 1);
    final widthFactor = 1 / values.length;
    // Maps i in [0, N-1] to [-1, +1] for Alignment.x
    final alignX = values.length == 1
        ? 0.0
        : (selectedIndex * 2 / (values.length - 1)) - 1.0;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(alignX, 0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: activeBg,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i == selectedIndex) return;
                      HapticFeedback.selectionClick();
                      onChanged(values[i]);
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: i == selectedIndex
                              ? FontWeight.w700
                              : FontWeight.w600,
                          fontSize: 14,
                          color: i == selectedIndex ? activeFg : idleFg,
                        ),
                        child: Text(labelOf(values[i])),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
