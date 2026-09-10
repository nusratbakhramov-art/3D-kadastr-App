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

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../home/user_profile.dart';
import '../ai_draft_saver.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/wizard_nav_bar.dart';
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
    final c = widget.bundle.client;
    if (c != null) {
      // Coming back from a later step — restore what was entered.
      _nameCtrl.text = c.name;
      _stirCtrl.text = c.stir;
      _phoneCtrl.text = c.phone.isEmpty ? '' : _formatPhoneForDisplay(c.phone);
      _emailCtrl.text = c.email;
    } else {
      // First visit — prefill from the logged-in user's account (editable).
      // davreestr only exposes the property OWNER's name, not the orderer's
      // contact details, so Ism/Telefon come from the user's profile instead.
      // Email isn't collected anywhere in the app, so it stays blank.
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
    // Orqaga qaytishда ham saqlash (fon rejimida) — kiritilgan narsa yo'qolmasin.
    if (_hasInput) {
      _captureToBundle();
      saveAiDraftStepInBackground(widget.bundle, 'client');
    }
    _nameCtrl.dispose();
    _stirCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_attemptedSubmit) return;
    // Live-revalidate once the user has hit Continue at least once.
    setState(() => _revalidate(Localizations.localeOf(context)));
  }

  bool _revalidate(Locale l) {
    _nameErr = _validateName(_nameCtrl.text, l);
    _stirErr = _validateStir(_stirCtrl.text, l);
    _phoneErr = _validatePhone(_phoneCtrl.text, l);
    _emailErr = _validateEmail(_emailCtrl.text, l);
    return _nameErr == null &&
        _stirErr == null &&
        _phoneErr == null &&
        _emailErr == null;
  }

  Future<void> _continue() async {
    final l = Localizations.localeOf(context);
    setState(() {
      _attemptedSubmit = true;
      _revalidate(l);
    });
    if (_nameErr != null ||
        _stirErr != null ||
        _phoneErr != null ||
        _emailErr != null) {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.lightImpact();
    _captureToBundle();
    // Fon rejimida saqlash — sekin backend navigatsiyani muzlatmasin.
    saveAiDraftStepInBackground(widget.bundle, 'location');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/location'),
        builder: (_) => AiLocationScreen(bundle: widget.bundle),
      ),
    );
  }

  /// Joriy maydonlarni bundle'ga yozadi (oldinga ham, Orqaga ketishda ham).
  void _captureToBundle() {
    widget.bundle.client = AiClientInfo(
      name: _nameCtrl.text.trim(),
      stir: _stirCtrl.text.trim(),
      phone: _normalizePhone(_phoneCtrl.text),
      email: _emailCtrl.text.trim().toLowerCase(),
    );
  }

  /// Foydalanuvchi biror narsa kiritganmi — bo'sh formani draftga yozib,
  /// profildan avto-to'ldirishni buzmaslik uchun.
  bool get _hasInput =>
      _nameCtrl.text.trim().isNotEmpty ||
      _stirCtrl.text.trim().isNotEmpty ||
      _phoneCtrl.text.trim().isNotEmpty ||
      _emailCtrl.text.trim().isNotEmpty;

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
                        title: _ClientFormStrings.title(l),
                        subtitle: _ClientFormStrings.subtitle(l),
                        // Bu tugma butun oqimni yopadi — bitta qadam
                        // orqaga EMAS. Qadamma-qadam qaytish pastda.
                        onBack: () => closeAiWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(count: 8, activeIndex: 2),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _FieldLabel(
                            _ClientFormStrings.nameLabel(l),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),
                          _AppTextField(
                            controller: _nameCtrl,
                            isDark: isDark,
                            placeholder: _ClientFormStrings.namePlaceholder(l),
                            keyboardType: TextInputType.name,
                            textCapitalization: TextCapitalization.words,
                            errorText: _nameErr,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(
                            _ClientFormStrings.stirLabel(l),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _ClientFormStrings.stirHint(l),
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
                          _FieldLabel(
                            _ClientFormStrings.phoneLabel(l),
                            isDark: isDark,
                          ),
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
                          _FieldLabel(
                            _ClientFormStrings.emailLabel(l),
                            isDark: isDark,
                          ),
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
                      child: WizardNavBar(
                        onBack: () => Navigator.of(context).maybePop(),
                        onContinue: _continue,
                        continueLabel: _ClientFormStrings.continueLabel(l),
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
  if (v.isEmpty) return _ClientFormStrings.nameRequired(l);
  if (v.length < 2) return _ClientFormStrings.tooShort(l);
  return null;
}

String? _validateStir(String raw, Locale l) {
  final v = raw.trim();
  if (v.isEmpty) return _ClientFormStrings.stirRequired(l);
  if (!RegExp(r'^\d+$').hasMatch(v)) return _ClientFormStrings.digitsOnly(l);
  if (v.length != 9 && v.length != 14) {
    return _ClientFormStrings.stirLength(l);
  }
  return null;
}

String? _validatePhone(String raw, Locale l) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return _ClientFormStrings.phoneRequired(l);
  // Accept either bare 9-digit operator portion or full 12-digit form.
  final normalized = digits.length == 9 ? '998$digits' : digits;
  if (normalized.length != 12 || !normalized.startsWith('998')) {
    return _ClientFormStrings.phoneFormat(l);
  }
  return null;
}

String? _validateEmail(String raw, Locale l) {
  final v = raw.trim();
  // Email ixtiyoriy — bo'sh bo'lsa ruxsat. Kiritilgan bo'lsa formatni tekshiramiz.
  if (v.isEmpty) return null;
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
    return _ClientFormStrings.emailInvalid(l);
  }
  return null;
}

String _normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length == 9 ? '998$digits' : digits;
}

/// Formats a raw/normalized UZ phone (`998XXXXXXXXX` or 9-digit operator part)
/// into the `+998 XX XXX-XX-XX` display form used by [_PhoneMaskFormatter], so
/// programmatic pre-fill matches what the mask would produce on typing.
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
          style: TextStyle(fontFamily: 'MTSText', fontSize: 15, color: text),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
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
    final rawCursor = newValue.selection.baseOffset.clamp(
      0,
      newValue.text.length,
    );
    final digitsBeforeCursor = newValue.text
        .substring(0, rawCursor)
        .replaceAll(RegExp(r'\D'), '')
        .length;

    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Strip leading 998 so the operator-part is what we count from.
    if (digits.startsWith('998')) digits = digits.substring(3);
    if (digits.length > _maxOpDigits)
      digits = digits.substring(0, _maxOpDigits);

    final buf = StringBuffer('+998 ');
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) buf.write(' ');
      if (i == 5 || i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();

    // Caret: count digits in formatted up to original-cursor's digit count,
    // counting only post-prefix digits (the visible `998` is fixed).
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

class _ClientFormStrings {
  const _ClientFormStrings._();

  static String title(Locale l) => tr(l, 'services.ai.client.title');

  static String subtitle(Locale l) => tr(l, 'services.ai.client.subtitle');

  static String nameLabel(Locale l) => tr(l, 'services.ai.client.name_label');

  static String namePlaceholder(Locale l) =>
      tr(l, 'services.ai.client.name_placeholder');

  static String stirLabel(Locale l) => tr(l, 'services.ai.client.stir_label');

  static String stirHint(Locale l) => tr(l, 'services.ai.client.stir_hint');

  static String phoneLabel(Locale l) => tr(l, 'services.ai.client.phone_label');

  static String emailLabel(Locale l) => tr(l, 'services.ai.client.email_label');

  static String continueLabel(Locale l) => tr(l, 'services.ai.common.continue');

  static String nameRequired(Locale l) =>
      tr(l, 'services.ai.client.name_required');

  static String tooShort(Locale l) => tr(l, 'services.ai.client.too_short');

  static String stirRequired(Locale l) =>
      tr(l, 'services.ai.client.stir_required');

  static String digitsOnly(Locale l) => tr(l, 'services.ai.client.digits_only');

  static String stirLength(Locale l) => tr(l, 'services.ai.client.stir_length');

  static String phoneRequired(Locale l) =>
      tr(l, 'services.ai.client.phone_required');

  static String phoneFormat(Locale l) =>
      tr(l, 'services.ai.client.phone_format');

  static String emailInvalid(Locale l) =>
      tr(l, 'services.ai.client.email_invalid');
}
