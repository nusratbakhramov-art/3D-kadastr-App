import 'package:flutter/material.dart';

import 'payment_model.dart';

/// Small status pill (glyph + label) tinted by [PaymentStatus.color].
///
/// Colour is never the only signal — the icon and text carry the meaning too,
/// so the status reads for colour-blind users and in screenshots alike.
class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({
    super.key,
    required this.status,
    required this.locale,
    this.dense = false,
  });

  final PaymentStatus status;
  final Locale locale;

  /// Tighter padding/sizing for use inside list-tile trailing slots.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: dense ? 12 : 14, color: color),
          SizedBox(width: dense ? 4 : 5),
          Text(
            status.label(locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: dense ? 11 : 12,
              height: 1.0,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
