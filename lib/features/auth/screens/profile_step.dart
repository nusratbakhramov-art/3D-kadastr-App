import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/user_profile.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/dob_field.dart';
import '../widgets/gender_toggle.dart';
import '../widgets/primary_cta.dart';

class ProfileStep extends StatefulWidget {
  const ProfileStep({
    super.key,
    required this.onSubmit,
    required this.onSkip,
    required this.onBack,
    this.initial,
    this.loading = false,
  });

  final ValueChanged<UserProfile> onSubmit;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final UserProfile? initial;
  final bool loading;

  @override
  State<ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<ProfileStep> {
  late final TextEditingController _name;
  DateTime? _dob;
  Gender? _gender;
  bool _nameTouched = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.fullName ?? '');
    _dob = widget.initial?.dateOfBirth;
    _gender = widget.initial?.gender;
    _name.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_rebuild);
    _name.dispose();
    super.dispose();
  }

  bool get _nameValid => _name.text.trim().isNotEmpty;
  bool get _formValid => _nameValid && _dob != null && _gender != null;

  void _submit() {
    if (!_formValid) {
      setState(() => _nameTouched = true);
      return;
    }
    widget.onSubmit(
      UserProfile(
        fullName: _name.text.trim(),
        dateOfBirth: _dob!,
        gender: _gender!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? Colors.white70
        : AppColors.textBlack.withValues(alpha: 0.65);
    final fieldBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.88);
    final fieldBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFD9DDE2);
    final inputTextColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.35)
        : AppColors.textBlack.withValues(alpha: 0.4);
    final showNameError = _nameTouched && !_nameValid;

    return AuthScaffold(
      title: "O'zingiz haqingizda",
      iconAsset: 'assets/images/auth/user.png',
      onBack: widget.onBack,
      onSkip: widget.onSkip,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "To'liq ism",
              style: TextStyle(color: labelColor, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: fieldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showNameError ? const Color(0xFFE74C4C) : fieldBorder,
                ),
              ),
              child: TextField(
                controller: _name,
                style: TextStyle(color: inputTextColor, fontSize: 16),
                decoration: InputDecoration(
                  hintText: "To'liq ismingizni kiriting",
                  hintStyle: TextStyle(color: hintColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
                onSubmitted: (_) => setState(() => _nameTouched = true),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Tug'ilgan sana",
              style: TextStyle(color: labelColor, fontSize: 14),
            ),
            const SizedBox(height: 8),
            DobField(value: _dob, onChanged: (d) => setState(() => _dob = d)),
            const SizedBox(height: 16),
            Text('Jins', style: TextStyle(color: labelColor, fontSize: 14)),
            const SizedBox(height: 8),
            GenderToggle(
              value: _gender,
              onChanged: (g) => setState(() => _gender = g),
            ),
          ],
        ),
      ),
      bottom: PrimaryCta(
        label: 'Kirish',
        enabled: _formValid,
        loading: widget.loading,
        onPressed: _submit,
      ),
    );
  }
}
