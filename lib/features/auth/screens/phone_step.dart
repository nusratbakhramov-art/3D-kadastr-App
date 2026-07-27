import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/phone_input_field.dart';
import '../widgets/primary_cta.dart';

class PhoneStep extends StatefulWidget {
  const PhoneStep({
    super.key,
    required this.onSubmit,
    required this.onSkip,
    this.initialDigits = '',
    this.loading = false,
  });

  final ValueChanged<String> onSubmit;
  final VoidCallback onSkip;
  final String initialDigits;
  final bool loading;

  @override
  State<PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<PhoneStep> {
  final PhoneInputController _phone = PhoneInputController();

  @override
  void initState() {
    super.initState();
    _phone.addListener(_rebuild);
    if (widget.initialDigits.isNotEmpty) {
      _phone.setDigits(widget.initialDigits);
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _phone.removeListener(_rebuild);
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_phone.isValid) return;
    widget.onSubmit('998${_phone.digits}');
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? Colors.white70
        : AppColors.textBlack.withValues(alpha: 0.65);

    return AuthScaffold(
      title: tr(locale, 'auth.phone.title'),
      iconAsset: 'assets/images/auth/login.png',
      onSkip: widget.onSkip,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(locale, 'auth.phone.number_label'),
              style: TextStyle(color: labelColor, fontSize: 14),
            ),
            const SizedBox(height: 12),
            PhoneInputField(controller: _phone),
          ],
        ),
      ),
      bottom: PrimaryCta(
        label: tr(locale, 'auth.continue'),
        enabled: _phone.isValid,
        loading: widget.loading,
        onPressed: _submit,
      ),
    );
  }
}
