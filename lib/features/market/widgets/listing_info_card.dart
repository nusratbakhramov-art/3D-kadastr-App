import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class ListingInfoCard extends StatelessWidget {
  const ListingInfoCard({
    super.key,
    required this.priceUzs,
    required this.title,
    this.description,
  });

  final int priceUzs;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final muted = fg.withValues(alpha: 0.65);
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
            '${_formatPrice(priceUzs)} UZS',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.3,
              color: fg,
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: fg.withValues(alpha: 0.08)),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              height: 1.25,
              color: fg,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.4,
                color: muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatPrice(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final remaining = s.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }
}
