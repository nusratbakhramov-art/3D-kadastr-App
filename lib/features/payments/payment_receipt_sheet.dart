import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/color_tokens.dart';
import '../../widgets/app_toast.dart';
import 'payment_model.dart';
import 'payment_status_chip.dart';

/// Shows the in-app receipt ("chek") for a single [payment].
///
/// The app does not store a fiscal OFD cheque server-side, so this renders a
/// clean digital receipt from the transaction record the backend already
/// returns (status, amount, provider, date, transaction id).
Future<void> showPaymentReceiptSheet(BuildContext context, Payment payment) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaymentReceiptSheet(payment: payment),
  );
}

class _PaymentReceiptSheet extends StatelessWidget {
  const _PaymentReceiptSheet({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final bg = ColorTokens.sheetBg(context);
    final primary = ColorTokens.primaryText(context);
    final secondary = ColorTokens.secondaryText(context);
    final status = payment.status;

    // Note: bottom:false too — the sheet's own padding clears the home
    // indicator, so the coloured background reaches the screen edge with no
    // black gap below the "Yopish" button.
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: secondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Title + close.
            Row(
              children: [
                const SizedBox(width: 32),
                Expanded(
                  child: Text(
                    _R.title(l),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: primary,
                    ),
                  ),
                ),
                _CircleIconButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Status seal.
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(status.icon, size: 34, color: status.color),
              ),
            ),
            const SizedBox(height: 14),

            // Amount.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    groupDigits(payment.amount),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      height: 1.0,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      soumLabel(l),
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 14,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(child: PaymentStatusChip(status: status, locale: l)),
            const SizedBox(height: 20),

            _DashedDivider(color: ColorTokens.divider(context)),
            const SizedBox(height: 4),

            // Details card.
            Container(
              decoration: BoxDecoration(
                color: ColorTokens.cardBg(context),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _DetailRow(
                    label: _R.service(l),
                    child: _ValueText(payment.title(l)),
                  ),
                  _rowDivider(context),
                  _DetailRow(
                    label: _R.method(l),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: payment.method.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        _ValueText(payment.method.displayName),
                      ],
                    ),
                  ),
                  _rowDivider(context),
                  _DetailRow(
                    label: _R.date(l),
                    child: _ValueText(_dateTime(payment.at)),
                  ),
                  if (payment.externalId != null) ...[
                    _rowDivider(context),
                    _DetailRow(
                      label: _R.txnId(l),
                      child: _CopyableValue(
                        value: payment.externalId!,
                        onCopied: () {
                          Clipboard.setData(
                            ClipboardData(text: payment.externalId!),
                          );
                          HapticFeedback.selectionClick();
                          AppToast.success(context, _R.copied(l));
                        },
                      ),
                    ),
                  ],
                  _rowDivider(context),
                  _DetailRow(
                    label: _R.receiptNo(l),
                    child: _ValueText('#${payment.id}'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Close.
            SizedBox(
              height: 52,
              child: Material(
                color: ColorTokens.iconBg(context),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Center(
                    child: Text(
                      _R.close(l),
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _rowDivider(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: ColorTokens.divider(context));

  static String _dateTime(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}, $hh:$min';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
        ],
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: ColorTokens.primaryText(context),
      ),
    );
  }
}

class _CopyableValue extends StatelessWidget {
  const _CopyableValue({required this.value, required this.onCopied});

  final String value;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onCopied,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: ColorTokens.primaryText(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.copy_rounded,
              size: 15,
              color: ColorTokens.brandPrimary(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.iconBg(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: ColorTokens.primaryText(context)),
        ),
      ),
    );
  }
}

/// Thin dashed rule that gives the receipt its "torn cheque" feel.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter(color)),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

class _R {
  const _R._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Чек об оплате',
    'en' => 'Payment receipt',
    _ => 'To‘lov cheki',
  };
  static String service(Locale l) => switch (l.languageCode) {
    'ru' => 'Услуга',
    'en' => 'Service',
    _ => 'Xizmat',
  };
  static String method(Locale l) => switch (l.languageCode) {
    'ru' => 'Способ оплаты',
    'en' => 'Payment method',
    _ => 'To‘lov usuli',
  };
  static String date(Locale l) => switch (l.languageCode) {
    'ru' => 'Дата и время',
    'en' => 'Date & time',
    _ => 'Sana va vaqt',
  };
  static String txnId(Locale l) => switch (l.languageCode) {
    'ru' => 'Номер транзакции',
    'en' => 'Transaction ID',
    _ => 'Tranzaksiya raqami',
  };
  static String receiptNo(Locale l) => switch (l.languageCode) {
    'ru' => 'Номер чека',
    'en' => 'Receipt no.',
    _ => 'Chek raqami',
  };
  static String copied(Locale l) => switch (l.languageCode) {
    'ru' => 'Скопировано',
    'en' => 'Copied',
    _ => 'Nusxa olindi',
  };
  static String close(Locale l) => switch (l.languageCode) {
    'ru' => 'Закрыть',
    'en' => 'Close',
    _ => 'Yopish',
  };
}
