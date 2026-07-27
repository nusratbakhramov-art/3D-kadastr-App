/// Step 1 of 3D Kadastr — client info form (buyurtmachi).
///
/// Mirrors the AI Baholash client form (`ai_client_form_screen.dart`).
/// Validators match server-side `ClientInput`:
///   - name: non-empty
///   - stir: exactly 9 OR exactly 14 digits
///   - phone: UZ 12-digit `998XXXXXXXXX`
///   - email: optional, pragmatic regex
///
/// On continue it opens the map location picker (step 2), reverse-geocodes the
/// confirmed point for `address_text`, then proceeds to the object-type step.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../home/user_profile.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../models/ai_baholash_bundle.dart' show AiClientInfo;
import '../../models/kadastr_3d_bundle.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import 'k3d_location_screen.dart';

class K3dClientFormScreen extends StatefulWidget {
  const K3dClientFormScreen({super.key, required this.bundle});

  final Kadastr3dBundle bundle;

  @override
  State<K3dClientFormScreen> createState() => _K3dClientFormScreenState();
}

class _K3dClientFormScreenState extends State<K3dClientFormScreen> {
  final _nameCtrl = TextEditingController();
  final _stirCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _nameErr;
  String? _stirErr;
  String? _phoneErr;
  String? _emailErr;

  bool _attemptedSubmit = false;

  @override
  void initState() {
    super.initState();
    final c = widget.bundle.client;
    if (c != null) {
      // Coming back from a later step — restore what was entered.
      _nameCtrl.text = c.name;
      _stirCtrl.text = c.stir;
      _phoneCtrl.text =
          c.phone.isEmpty ? '' : _formatPhoneForDisplay(c.phone);
      _emailCtrl.text = c.email;
    } else {
      // First visit — prefill from the logged-in user's account (editable).
      final p = userProfileNotifier.value;
      if (p != null) {
        if (p.name.trim().isNotEmpty) _nameCtrl.text = p.name.trim();
        final phoneDigits = (p.phone ?? '').replaceAll(RegExp(r'\D'), '');
        if (phoneDigits.isNotEmpty) {
          _phoneCtrl.text = _formatPhoneForDisplay(p.phone!);
        }
      }
    }
    for (final c in [_nameCtrl, _stirCtrl, _phoneCtrl, _emailCtrl]) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stirCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_attemptedSubmit) return;
    setState(_revalidate);
  }

  bool _revalidate() {
    final l = Localizations.localeOf(context);
    _nameErr = _validateName(_nameCtrl.text, l);
    _stirErr = _validateStir(_stirCtrl.text, l);
    _phoneErr = _validatePhone(_phoneCtrl.text, l);
    _emailErr = _validateEmail(_emailCtrl.text, l);
    return _nameErr == null &&
        _stirErr == null &&
        _phoneErr == null &&
        _emailErr == null;
  }

  void _continue() {
    setState(() {
      _attemptedSubmit = true;
      _revalidate();
    });
    if (_nameErr != null ||
        _stirErr != null ||
        _phoneErr != null ||
        _emailErr != null) {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.lightImpact();
    widget.bundle.client = AiClientInfo(
      name: _nameCtrl.text.trim(),
      stir: _stirCtrl.text.trim(),
      phone: _normalizePhone(_phoneCtrl.text),
      email: _emailCtrl.text.trim().toLowerCase(),
    );
    // Step 2 — location (AI Baholash-style center-pin map). Forward push so
    // the transition animates like every other step.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => K3dLocationScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxContent = c.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: tr(l, 'services.k3d.client.appbar'),
                        subtitle: tr(l, 'services.k3d.client.subtitle'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(count: 6, activeIndex: 1),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _FieldLabel(tr(l, 'services.k3d.client.name_label'),
                              isDark: isDark),
                          const SizedBox(height: 8),
                          _AppTextField(
                            controller: _nameCtrl,
                            isDark: isDark,
                            placeholder:
                                tr(l, 'services.k3d.client.name_placeholder'),
                            keyboardType: TextInputType.name,
                            textCapitalization: TextCapitalization.words,
                            errorText: _nameErr,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(tr(l, 'services.k3d.client.stir_label'),
                              isDark: isDark),
                          const SizedBox(height: 4),
                          Text(
                            tr(l, 'services.k3d.client.stir_hint'),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.55)
                                  : const Color(0xFF8A9097),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _AppTextField(
                            controller: _stirCtrl,
                            isDark: isDark,
                            placeholder: '000000000',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(14),
                            ],
                            errorText: _stirErr,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(tr(l, 'services.k3d.phone'),
                              isDark: isDark),
                          const SizedBox(height: 8),
                          _AppTextField(
                            controller: _phoneCtrl,
                            isDark: isDark,
                            placeholder: '+998 90 123-45-67',
                            keyboardType: TextInputType.phone,
                            inputFormatters: [_PhoneMaskFormatter()],
                            errorText: _phoneErr,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(tr(l, 'services.k3d.client.email_label'),
                              isDark: isDark),
                          const SizedBox(height: 8),
                          _AppTextField(
                            controller: _emailCtrl,
                            isDark: isDark,
                            placeholder: 'name@example.uz',
                            keyboardType: TextInputType.emailAddress,
                            errorText: _emailErr,
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: tr(l, 'services.k3d.continue'),
                        enabled: true,
                        onTap: _continue,
                      ),

                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Validators ──────────────────────────────────────────────────────────

String? _validateName(String raw, Locale l) {
  final v = raw.trim();
  if (v.isEmpty) return tr(l, 'services.k3d.client.err_name_required');
  if (v.length < 2) return tr(l, 'services.k3d.client.err_too_short');
  return null;
}

String? _validateStir(String raw, Locale l) {
  final v = raw.trim();
  if (v.isEmpty) return tr(l, 'services.k3d.client.err_stir_required');
  if (!RegExp(r'^\d+$').hasMatch(v)) {
    return tr(l, 'services.k3d.client.err_digits_only');
  }
  if (v.length != 9 && v.length != 14) {
    return tr(l, 'services.k3d.client.err_stir_length');
  }
  return null;
}

String? _validatePhone(String raw, Locale l) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return tr(l, 'services.k3d.client.err_phone_required');
  final normalized = digits.length == 9 ? '998$digits' : digits;
  if (normalized.length != 12 || !normalized.startsWith('998')) {
    return tr(l, 'services.k3d.client.err_phone_format');
  }
  return null;
}

String? _validateEmail(String raw, Locale l) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
    return tr(l, 'services.k3d.client.err_email_invalid');
  }
  return null;
}

String _normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length == 9 ? '998$digits' : digits;
}

String _formatPhoneForDisplay(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('998')) digits = digits.substring(3);
  if (digits.length > 9) digits = digits.substring(0, 9);
  final buf = StringBuffer('+998 ');
  for (var i = 0; i < digits.length; i++) {
    if (i == 2) buf.write(' ');
    if (i == 5 || i == 7) buf.write('-');
    buf.write(digits[i]);
  }
  return buf.toString();
}

// ── UI bits ─────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.isDark});
  final String text;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: isDark ? Colors.white : AppColors.textBlack,
      ),
    );
  }
}

class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.isDark,
    this.placeholder,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
  });

  final TextEditingController controller;
  final bool isDark;
  final String? placeholder;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = errorText != null
        ? const Color(0xFFE0492A)
        : (isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8));
    final text = isDark ? Colors.white : AppColors.textBlack;
    final hint = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 15,
            color: text,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            hintText: placeholder,
            hintStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 15,
              color: hint,
            ),
            filled: true,
            fillColor: fill,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: errorText != null
                    ? const Color(0xFFE0492A)
                    : AppColors.splashGreen,
                width: 1.4,
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12,
              color: Color(0xFFE0492A),
            ),
          ),
        ],
      ],
    );
  }
}

/// `+998 XX XXX-XX-XX` mask formatter with proper caret mapping.
class _PhoneMaskFormatter extends TextInputFormatter {
  static const _maxOpDigits = 9;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawCursor =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBeforeCursor = newValue.text
        .substring(0, rawCursor)
        .replaceAll(RegExp(r'\D'), '')
        .length;

    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('998')) digits = digits.substring(3);
    if (digits.length > _maxOpDigits) digits = digits.substring(0, _maxOpDigits);

    final buf = StringBuffer('+998 ');
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) buf.write(' ');
      if (i == 5 || i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();

    final preCount = digitsBeforeCursor > 3 ? digitsBeforeCursor - 3 : 0;
    var seen = 0;
    var pos = '+998 '.length;
    while (pos < formatted.length && seen < preCount) {
      if (RegExp(r'\d').hasMatch(formatted[pos])) seen++;
      pos++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: pos),
      composing: TextRange.empty,
    );
  }
}

