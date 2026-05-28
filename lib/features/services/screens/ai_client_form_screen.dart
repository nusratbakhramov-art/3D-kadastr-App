/// Step 2 of AI Baholash — client info form.
///
/// Validators mirror server-side `ClientInput`:
///   - name: non-empty
///   - stir: exactly 9 OR exactly 14 digits (nothing else accepted)
///   - phone: UZ 12-digit `998XXXXXXXXX`
///   - email: pragmatic regex (no email-validator package on the wire)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_location_screen.dart';

class AiClientFormScreen extends StatefulWidget {
  const AiClientFormScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

  @override
  State<AiClientFormScreen> createState() => _AiClientFormScreenState();
}

class _AiClientFormScreenState extends State<AiClientFormScreen> {
  final _nameCtrl = TextEditingController();
  final _stirCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Per-field error messages — null when the field is currently valid (or
  // hasn't been touched and the user hasn't tapped Continue yet).
  String? _nameErr;
  String? _stirErr;
  String? _phoneErr;
  String? _emailErr;

  bool _attemptedSubmit = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill if user is coming back from a later step.
    final c = widget.bundle.client;
    if (c != null) {
      _nameCtrl.text = c.name;
      _stirCtrl.text = c.stir;
      _phoneCtrl.text = c.phone;
      _emailCtrl.text = c.email;
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
    // Live-revalidate once the user has hit Continue at least once.
    setState(_revalidate);
  }

  bool _revalidate() {
    _nameErr = _validateName(_nameCtrl.text);
    _stirErr = _validateStir(_stirCtrl.text);
    _phoneErr = _validatePhone(_phoneCtrl.text);
    _emailErr = _validateEmail(_emailCtrl.text);
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiLocationScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: 'Buyurtmachi',
                        subtitle: 'Ma\'lumotlaringizni kiriting',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(count: 4, activeIndex: 1),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _FieldLabel('Ism / Kompaniya', isDark: isDark),
                          const SizedBox(height: 8),
                          _AppTextField(
                            controller: _nameCtrl,
                            isDark: isDark,
                            placeholder: 'Toshpo\'lat Toshpo\'latov yoki "ABC" MChJ',
                            keyboardType: TextInputType.name,
                            textCapitalization: TextCapitalization.words,
                            errorText: _nameErr,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel('STIR yoki JSHSHIR', isDark: isDark),
                          const SizedBox(height: 4),
                          Text(
                            'Yuridik shaxs: 9 raqam. Jismoniy shaxs: 14 raqam.',
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
                          _FieldLabel('Telefon', isDark: isDark),
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
                          _FieldLabel('Email', isDark: isDark),
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
                        label: 'Davom etish',
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

String? _validateName(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'Ism kerak';
  if (v.length < 2) return 'Juda qisqa';
  return null;
}

String? _validateStir(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'STIR yoki JSHSHIR kerak';
  if (!RegExp(r'^\d+$').hasMatch(v)) return 'Faqat raqamlar';
  if (v.length != 9 && v.length != 14) return 'Aniq 9 yoki 14 raqam bo\'lishi kerak';
  return null;
}

String? _validatePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return 'Telefon kerak';
  // Accept either bare 9-digit operator portion or full 12-digit form.
  final normalized = digits.length == 9 ? '998$digits' : digits;
  if (normalized.length != 12 || !normalized.startsWith('998')) {
    return 'UZ formati: +998 XX XXX-XX-XX';
  }
  return null;
}

String? _validateEmail(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'Email kerak';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
    return 'Email noto\'g\'ri';
  }
  return null;
}

String _normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length == 9 ? '998$digits' : digits;
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

/// `+998 XX XXX-XX-XX` mask formatter with proper caret mapping — mirrors
/// the pattern used in `phone_input_field.dart` but inline so this screen
/// stays self-contained.
class _PhoneMaskFormatter extends TextInputFormatter {
  static const _maxOpDigits = 9; // 9 digits after the `998` prefix

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
    // Strip leading 998 so the operator-part is what we count from.
    if (digits.startsWith('998')) digits = digits.substring(3);
    if (digits.length > _maxOpDigits) digits = digits.substring(0, _maxOpDigits);

    final buf = StringBuffer('+998 ');
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) buf.write(' ');
      if (i == 5 || i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();

    // Caret: count digits in formatted up to original-cursor's digit count,
    // counting only post-prefix digits (the visible `998` is fixed).
    final preCount =
        digitsBeforeCursor > 3 ? digitsBeforeCursor - 3 : 0;
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
