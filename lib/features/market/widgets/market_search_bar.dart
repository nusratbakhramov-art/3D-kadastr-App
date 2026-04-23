import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class MarketSearchBar extends StatelessWidget {
  const MarketSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.98);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : AppColors.textBlack.withValues(alpha: 0.45);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w500,
            fontSize: 20,
            color: textColor,
          ),
          decoration: InputDecoration(
            hintText: 'Qidirish',
            hintStyle: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 20,
              color: hintColor,
            ),
            filled: true,
            fillColor: surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 36,
              color: isDark ? Colors.white : AppColors.textBlack,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    onPressed: onClear,
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppColors.textBlack.withValues(alpha: 0.8),
                    ),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
    );
  }
}
