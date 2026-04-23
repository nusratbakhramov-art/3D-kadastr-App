import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../models/listing_format.dart';

class ListingFormatsCard extends StatelessWidget {
  const ListingFormatsCard({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ListingFormat selected;
  final ValueChanged<ListingFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? null : Border.all(color: const Color(0xFFE3E5E8));

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: border,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formatlar',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.3,
              color: fg,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in ListingFormat.values)
                _FormatChip(
                  label: f.label,
                  selected: f == selected,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(f);
                  },
                  fg: fg,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.fg,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.splashGreen
        : const Color(0xFFD1D5D9);
    final textColor = selected
        ? AppColors.splashGreen
        : fg.withValues(alpha: 0.8);
    final bg = selected
        ? AppColors.splashGreen.withValues(alpha: 0.12)
        : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.2,
              letterSpacing: 0.2,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
