/// "Bozor AI" sehrgarining kontaktlar qadami — `Контакты`.
///
/// Dizaynda oltita variantda ham AYNAN bir xil — tarmoqlanish yo'q.
///
/// ⚠️ SMS TASDIQLASH — BACKEND YO'Q.
/// Dizaynda karta ichida "Отправить" tugmasi bor, lekin KOD KIRITISH EKRANI
/// butun to'plamda yo'q. Ilovada esa faqat `/auth/send-otp` va
/// `/auth/verify-otp` bor — ular LOGIN endpointlari: e'lon kontakt raqamini
/// ular bilan tekshirish foydalanuvchini o'sha raqam bilan tizimga kiritib
/// yuborardi. Shu sababli bu yerda kod bloki UI sifatida (mavjud [OtpBoxes]
/// va [ResendTimer] bilan) chizilgan, lekin HECH QANDAY so'rov yubormaydi.
/// "Далее" ham tasdiqlashni TALAB QILMAYDI — aks holda oqim boshi berk
/// ko'chaga kirardi. Endpoint paydo bo'lganda faqat [_sendCode] va
/// [_verifyCode] to'ldiriladi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/widgets/otp_boxes.dart';
import '../../auth/widgets/resend_timer.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_field.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../bozor_routes.dart';
import '../models/bozor_draft.dart';
import '../widgets/bozor_phone_field.dart';
import 'bozor_terms_step_screen.dart';

/// Nechta telefon qo'shish mumkin. Dizaynda chegara ko'rsatilmagan.
const int _maxPhones = 3;

/// SMS kodning uzunligi — ilovadagi login kodi bilan bir xil.
const int _codeLength = 5;

class BozorContactsStepScreen extends StatefulWidget {
  const BozorContactsStepScreen({super.key, required this.draft});

  final BozorDraft draft;

  @override
  State<BozorContactsStepScreen> createState() =>
      _BozorContactsStepScreenState();
}

class _BozorContactsStepScreenState extends State<BozorContactsStepScreen> {
  late final TextEditingController _name =
      TextEditingController(text: _c.name);
  late final TextEditingController _email =
      TextEditingController(text: _c.email);
  late final List<TextEditingController> _phones = [
    for (final p in _c.phones) TextEditingController(text: p),
  ];

  /// Kod bloki ochilganmi ("Yuborish" bosilgandan keyin).
  bool _codeSent = false;

  ContactsDraft get _c => widget.draft.contacts;

  @override
  void initState() {
    super.initState();
    _name.addListener(_sync);
    _email.addListener(_sync);
    for (final c in _phones) {
      c.addListener(_sync);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    for (final c in _phones) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    setState(() {
      _c.name = _name.text.trim();
      _c.email = _email.text.trim();
      _c.phones
        ..clear()
        ..addAll(_phones.map((c) => _digits(c.text)));
    });
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _firstPhoneValid =>
      _phones.isNotEmpty && _digits(_phones.first.text).length == 9;

  void _addPhone() {
    if (_phones.length >= _maxPhones) return;
    final c = TextEditingController()..addListener(_sync);
    setState(() => _phones.add(c));
    _sync();
  }

  void _removePhone(int index) {
    final c = _phones.removeAt(index);
    c.removeListener(_sync);
    c.dispose();
    setState(() {});
    _sync();
  }

  /// TODO(backend): e'lon kontaktini tasdiqlash uchun endpoint kerak.
  /// `/auth/send-otp` MAQBUL EMAS — u login oqimi.
  void _sendCode() {
    final l = Localizations.localeOf(context);
    if (!_firstPhoneValid) {
      AppToast.error(context, _S.phoneInvalid(l));
      return;
    }
    setState(() => _codeSent = true);
    AppToast.success(context, _S.codeStub(l));
  }

  /// TODO(backend): kodni tekshirish. Hozircha faqat UI holati.
  void _verifyCode(String code) {
    if (code.length < _codeLength) return;
    setState(() => _c.phoneVerified = true);
    AppToast.success(context, _S.codeStub(Localizations.localeOf(context)));
  }

  Future<void> _openTerms() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('terms'),
        builder: (_) => BozorTermsStepScreen(draft: widget.draft),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Tasdiqlash TALAB QILINMAYDI — yuqoridagi izohga qarang.
  bool get _isComplete => _c.name.isNotEmpty && _firstPhoneValid;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final subColor = isDark ? Colors.white70 : const Color(0xFF8A9097);
    final draft = widget.draft;

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
                        title: _S.title(l),
                        subtitle:
                            '${draft.stepNumber(WizardStep.contacts)}'
                            '/${draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: draft.stepCount,
                        activeIndex: draft.stepIndex(WizardStep.contacts),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            _S.hint(l),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.35,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          WizardField(
                            label: _S.name(l),
                            controller: _name,
                            placeholder: _S.nameHint(l),
                            required: true,
                          ),
                          for (var i = 0; i < _phones.length; i++) ...[
                            const SizedBox(height: 12),
                            BozorPhoneField(
                              label: _phones.length == 1
                                  ? _S.phone(l)
                                  : '${_S.phone(l)} ${i + 1}',
                              controller: _phones[i],
                              required: i == 0,
                              onRemove: i == 0 ? null : () => _removePhone(i),
                              removeLabel: _S.remove(l),
                            ),
                          ],
                          const SizedBox(height: 12),
                          WizardField(
                            label: _S.email(l),
                            controller: _email,
                            placeholder: _S.emailHint(l),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          if (_phones.length < _maxPhones) ...[
                            const SizedBox(height: 14),
                            _AddPhoneLink(
                              label: _S.addPhone(l),
                              onTap: _addPhone,
                            ),
                          ],
                          const SizedBox(height: 16),
                          ListingCtaButton(
                            label: _S.send(l),
                            enabled: _firstPhoneValid && !_c.phoneVerified,
                            onTap: _sendCode,
                          ),
                          if (_codeSent && !_c.phoneVerified) ...[
                            const SizedBox(height: 18),
                            OtpBoxes(
                              length: _codeLength,
                              onChanged: (_) {},
                              onCompleted: _verifyCode,
                              autofocus: false,
                            ),
                            const SizedBox(height: 12),
                            Center(child: ResendTimer(onResend: _sendCode)),
                          ],
                          if (_c.phoneVerified) ...[
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: AppColors.splashGreen,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _S.verified(l),
                                  style: const TextStyle(
                                    fontFamily: 'MTSCompact',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.splashGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: WizardNavBar(
                        onBack: () => Navigator.of(context).maybePop(),
                        continueLabel: tr(l, 'bozor.common.next'),
                        continueEnabled: _isComplete,
                        onContinue: _openTerms,
                        onBlockedTap: () => AppToast.error(
                          context,
                          tr(l, 'bozor.common.fill_required'),
                        ),
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

/// "+ Telefon raqam qo'shish" — dizaynda ko'k matn + 20pt qo'shish ikonkasi.
class _AddPhoneLink extends StatelessWidget {
  const _AddPhoneLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          const Icon(
            Icons.add_circle_outline_rounded,
            size: 20,
            color: AppColors.splashGreen,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.splashGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'bozor.contacts.title');
  static String hint(Locale l) => tr(l, 'bozor.contacts.hint');
  static String name(Locale l) => tr(l, 'bozor.contacts.name');
  static String nameHint(Locale l) => tr(l, 'bozor.contacts.name_hint');
  static String phone(Locale l) => tr(l, 'bozor.contacts.phone');
  static String email(Locale l) => tr(l, 'bozor.contacts.email');
  static String emailHint(Locale l) => tr(l, 'bozor.contacts.email_hint');
  static String addPhone(Locale l) => tr(l, 'bozor.contacts.add_phone');
  static String send(Locale l) => tr(l, 'bozor.contacts.send');
  static String remove(Locale l) => tr(l, 'bozor.common.clear');
  static String verified(Locale l) => tr(l, 'bozor.contacts.verified');
  static String phoneInvalid(Locale l) =>
      tr(l, 'bozor.contacts.phone_invalid');
  static String codeStub(Locale l) => tr(l, 'bozor.contacts.code_stub');
}
