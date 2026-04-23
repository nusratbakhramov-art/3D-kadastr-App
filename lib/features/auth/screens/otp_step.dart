import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../auth_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_toast.dart';
import '../widgets/otp_boxes.dart';
import '../widgets/primary_cta.dart';
import '../widgets/resend_timer.dart';

class OtpStep extends StatefulWidget {
  const OtpStep({
    super.key,
    required this.phone,
    required this.service,
    required this.onVerified,
    required this.onEdit,
    required this.onSkip,
    this.otpLength = 5,
    this.resend = const Duration(seconds: 90),
  });

  final String phone;
  final AuthService service;
  final ValueChanged<VerifyResult> onVerified;
  final VoidCallback onEdit;
  final VoidCallback onSkip;
  final int otpLength;
  final Duration resend;

  @override
  State<OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends State<OtpStep> {
  final OtpController _otp = OtpController(length: 5);
  OtpBoxState _boxState = OtpBoxState.neutral;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _otp.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AuthToasts.dismiss();
    _otp.removeListener(_rebuild);
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_otp.value.length != widget.otpLength || _loading) return;
    AuthToasts.dismiss();
    setState(() => _loading = true);
    try {
      final result = await widget.service.verifyOtp(widget.phone, _otp.value);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _boxState = OtpBoxState.success;
        _loading = false;
      });
      widget.onVerified(result);
    } on AuthException catch (e) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _boxState = OtpBoxState.error;
        _loading = false;
      });
      AuthToasts.show(
        context,
        message: e.message,
        variant: AuthToastVariant.error,
      );
    }
  }

  Future<void> _resend() async {
    try {
      await widget.service.sendOtp(widget.phone);
      if (!mounted) return;
      _otp.clear();
      setState(() => _boxState = OtpBoxState.neutral);
      AuthToasts.show(
        context,
        message: 'Kod qayta yuborildi',
        variant: AuthToastVariant.success,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      AuthToasts.show(
        context,
        message: e.message,
        variant: AuthToastVariant.error,
      );
    }
  }

  String _prettyPhone() {
    // '998934729335' -> '+998 93 472-93-35'
    if (widget.phone.length != 12) return '+${widget.phone}';
    final p = widget.phone;
    return '+${p.substring(0, 3)} ${p.substring(3, 5)} '
        '${p.substring(5, 8)}-${p.substring(8, 10)}-${p.substring(10, 12)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? Colors.white70
        : AppColors.textBlack.withValues(alpha: 0.65);
    final complete = _otp.value.length == widget.otpLength;
    return AuthScaffold(
      title: 'Tasdiqlash kodi',
      iconAsset: 'assets/images/auth/msg.png',
      onBack: widget.onEdit,
      onSkip: widget.onSkip,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Raqamingizga yuborilgan kodni kiriting',
              style: TextStyle(color: labelColor, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _PhonePill(text: _prettyPhone(), onEdit: widget.onEdit),
            const SizedBox(height: 20),
            OtpBoxes(
              length: widget.otpLength,
              controller: _otp,
              state: _boxState,
              onChanged: (_) {
                if (_boxState == OtpBoxState.error) {
                  setState(() => _boxState = OtpBoxState.neutral);
                }
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: ResendTimer(duration: widget.resend, onResend: _resend),
            ),
          ],
        ),
      ),
      bottom: PrimaryCta(
        label: 'Davom etish',
        enabled: complete,
        loading: _loading,
        onPressed: _verify,
      ),
    );
  }
}

class _PhonePill extends StatelessWidget {
  const _PhonePill({required this.text, required this.onEdit});

  final String text;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.88);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFD9DDE2);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.8)
        : AppColors.textBlack.withValues(alpha: 0.7);

    return GestureDetector(
      key: const ValueKey('otp.edit'),
      onTap: onEdit,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: TextStyle(color: textColor, fontSize: 14)),
            const SizedBox(width: 8),
            Icon(Icons.edit, color: iconColor, size: 14),
          ],
        ),
      ),
    );
  }
}
