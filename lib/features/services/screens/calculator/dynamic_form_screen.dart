/// Backend sxemasi bo'yicha generik renderlanadigan wizard.
///
/// `GET /forms/{key}` dan olingan [FormSchema] ni bo'limlarni qadam qilib
/// ko'rsatadi, maydonlarni turi bo'yicha renderlaydi, javoblarni `mapsTo`
/// orqali mavjud submit payload shakliga moslab [submitPath] ga yuboradi.
/// Shu sbabli forma maydon/variant/bo'limlarini o'zgartirish uchun ilova relizi
/// shart emas — admin builder'dan tahrirlanadi.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../../core/api_config.dart';
import '../../../../core/input_validators.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/app_toast.dart';
import '../../../auth/auth_storage.dart';
import '../../../home/user_profile.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/last_customer_store.dart';
import '../../models/dynamic_form_schema.dart';
import '../../models/dynamic_form_payload.dart';
import '../../api_forms_service.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';

class DynamicFormScreen extends StatefulWidget {
  const DynamicFormScreen({
    super.key,
    required this.formKey,
    required this.submitPath,
    this.onSubmitted,
    this.initialAnswers,
    this.extraPayloadPaths,
    this.prefillCustomer = true,
  });

  /// Backend forma kaliti, masalan "arxitektura_tz".
  final String formKey;

  /// Submit POST yo'li (baseUrl ga nisbatan), masalan "/services/architecture/orders".
  final String submitPath;

  /// Muvaffaqiyatli yuborilgach ko'rsatiladigan ekran (orderId bilan).
  final Widget Function(BuildContext context, int orderId)? onSubmitted;

  /// Oldindan to'ldiriladigan javoblar (field.key → qiymat). Masalan kalkulyator
  /// natijasidan kelgan object_type / total_area_sqm / construction_type.
  final Map<String, dynamic>? initialAnswers;

  /// Submit payload'iga qo'shiladigan hisoblangan qiymatlar (nuqtali yo'l →
  /// qiymat). Masalan {'details.estimated_price_uzs': 12000000}.
  final Map<String, dynamic>? extraPayloadPaths;

  /// Buyurtmachi rekvizitlarini oxirgi arizadan oldindan to'ldirish.
  final bool prefillCustomer;

  @override
  State<DynamicFormScreen> createState() => _DynamicFormScreenState();
}

class _DynamicFormScreenState extends State<DynamicFormScreen> {
  final _service = FormsApiService();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _answers = {};

  FormSchema? _schema;
  String? _loadError;
  int _step = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final schema = await _service.getForm(widget.formKey);
      // Default qiymatlar (toggle → false, default berilgan bo'lsa o'sha).
      for (final f in schema.allFields) {
        if (f.type == FormFieldType.toggle) {
          _answers[f.key] = f.defaultValue == true;
        } else if (f.defaultValue != null) {
          _answers[f.key] = f.defaultValue;
        }
      }
      // Buyurtmachi rekvizitlari: avval tizimga kirgan foydalanuvchi
      // ma'lumotlari (ism + telefon), so'ng oxirgi arizadan (mavjud bo'lsa).
      if (widget.prefillCustomer) {
        final me = userProfileNotifier.value;
        if (me != null) {
          if (me.name.trim().isNotEmpty) {
            _answers.putIfAbsent('customer_name', () => me.name.trim());
          }
          final myPhone = (me.phone ?? '').trim();
          if (myPhone.isNotEmpty) {
            _answers.putIfAbsent('phone', () => myPhone);
          }
        }
        final last = await const LastCustomerStore().load();
        if (last != null) {
          _answers.putIfAbsent('customer_name', () => last.name);
          if (last.tin.isNotEmpty) _answers.putIfAbsent('tin', () => last.tin);
          if (last.phone.isNotEmpty) {
            _answers.putIfAbsent('phone', () => last.phone);
          }
          if (last.email.isNotEmpty) {
            _answers.putIfAbsent('email', () => last.email);
          }
        }
      }
      // Kalkulyatordan kelgan boshlang'ich javoblar (eng ustun).
      if (widget.initialAnswers != null) {
        _answers.addAll(widget.initialAnswers!);
      }
      if (!mounted) return;
      setState(() => _schema = schema);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e is FormsApiException ? e.message : '$e');
    }
  }

  TextEditingController _ctrl(FormFieldDef f) => _controllers.putIfAbsent(
        f.key,
        () => TextEditingController(text: (_answers[f.key] ?? '').toString()),
      );

  /// Maydonning effektiv formati — backend bersa o'sha, aks holda kalitdan
  /// taxmin qilamiz (telefon/email/STIR har doim shu kalitlar bilan keladi).
  String? _formatOf(FormFieldDef f) {
    if (f.format != null && f.format!.isNotEmpty) return f.format;
    return switch (f.key) {
      'phone' => 'phone',
      'email' => 'email',
      'tin' => 'tin',
      _ => null,
    };
  }

  // ── Validatsiya ────────────────────────────────────────────────────────
  String? _validateSection(FormSectionDef s, Locale l) {
    for (final f in s.fields) {
      final v = _answers[f.key];
      final empty = v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is List && v.isEmpty);
      if (f.required && empty && f.type != FormFieldType.toggle) {
        return '${trMap(f.label, l)} — ${_req(l)}';
      }
      // Format validatsiyasi (telefon / email / STIR). Bo'sh + ixtiyoriy bo'lsa
      // o'tkazib yuboramiz (majburiylik yuqorida tekshirilgan).
      if (!empty && v is String) {
        switch (_formatOf(f)) {
          case 'phone':
            if (!isValidUzPhone(v)) return _phoneErr(l);
          case 'email':
            if (!isValidEmail(v)) return _emailErr(l);
          case 'tin':
            if (!isValidTin(v)) return _tinErr(l);
        }
      }
      if ((f.type == FormFieldType.number || f.type == FormFieldType.integer) &&
          v is num) {
        if (f.min != null && v < f.min!) {
          return '${trMap(f.label, l)} ≥ ${f.min}';
        }
        if (f.max != null && v > f.max!) {
          return '${trMap(f.label, l)} ≤ ${f.max}';
        }
      }
    }
    return null;
  }

  Future<void> _next() async {
    final schema = _schema!;
    final l = Localizations.localeOf(context);
    final err = _validateSection(schema.sections[_step], l);
    if (err != null) {
      HapticFeedback.heavyImpact();
      AppToast.error(context, err);
      return;
    }
    if (_step < schema.sections.length - 1) {
      HapticFeedback.lightImpact();
      setState(() => _step++);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final schema = _schema!;
    final l = Localizations.localeOf(context);
    // Yuborishdan oldin barcha bo'limlarni tekshiramiz.
    for (var i = 0; i < schema.sections.length; i++) {
      final err = _validateSection(schema.sections[i], l);
      if (err != null) {
        setState(() => _step = i);
        HapticFeedback.heavyImpact();
        AppToast.error(context, err);
        return;
      }
    }

    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (mounted) AppToast.error(context, _loginFirst(l));
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = buildPayload(schema, _answers);
      // Hisoblangan qiymatlarni (masalan estimated_price_uzs) payload'ga qo'shamiz.
      widget.extraPayloadPaths?.forEach((path, value) {
        if (value != null) setByPath(payload, path, value);
      });
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}${widget.submitPath}'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw _msgFor(res);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final orderId = (body['id'] as num?)?.toInt() ?? 0;
      // Keyingi ariza uchun buyurtmachi rekvizitlarini eslab qolamiz.
      if (widget.prefillCustomer && (_answers['customer_name'] != null)) {
        await const LastCustomerStore().save(LastCustomer(
          name: (_answers['customer_name'] ?? '').toString(),
          tin: (_answers['tin'] ?? '').toString(),
          phone: (_answers['phone'] ?? '').toString(),
          email: (_answers['email'] ?? '').toString(),
        ));
      }
      if (!mounted) return;
      if (widget.onSubmitted != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (ctx) => widget.onSubmitted!(ctx, orderId),
          ),
        );
      } else {
        AppToast.success(context, _sent(l));
        Navigator.of(context).pop(orderId);
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e is String ? e : '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _msgFor(http.Response res) {
    try {
      final b = jsonDecode(res.body);
      if (b is Map && b['detail'] != null) {
        final d = b['detail'];
        if (d is String) return d;
        if (d is List && d.isNotEmpty && d.first is Map) {
          return '${(d.first as Map)['msg']}';
        }
      }
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final l = Localizations.localeOf(context);
    final schema = _schema;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: schema == null
            ? _loadError != null
                ? _ErrorView(message: _loadError!, onRetry: _load)
                : const Center(child: CircularProgressIndicator())
            : _buildWizard(schema, l),
      ),
    );
  }

  Widget _buildWizard(FormSchema schema, Locale l) {
    final section = schema.sections[_step];
    final isLast = _step == schema.sections.length - 1;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: ServiceAppBar(
                title: trMap(schema.title, l),
                subtitle:
                    '${_step + 1}/${schema.sections.length} — ${trMap(section.title, l)}',
                onBack: () {
                  if (_step > 0) {
                    setState(() => _step--);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StepProgressBar(
                count: schema.sections.length,
                activeIndex: _step,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Text(
                    trMap(section.title, l),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: _txt(context),
                    ),
                  ),
                  if ((section.help?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 4),
                    Text(
                      trMap(section.help, l),
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontSize: 13,
                        color: _muted(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  for (final f in section.fields) ...[
                    _buildField(f, l),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ListingCtaButton(
                label: _submitting
                    ? '…'
                    : isLast
                        ? _submitLabel(l)
                        : _continueLabel(l),
                enabled: !_submitting,
                onTap: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Maydon renderi ───────────────────────────────────────────────────────
  Widget _buildField(FormFieldDef f, Locale l) {
    switch (f.type) {
      case FormFieldType.note:
        return Text(
          trMap(f.label, l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 14,
            height: 1.4,
            color: _muted(context),
          ),
        );
      case FormFieldType.toggle:
        return _ToggleRow(
          label: trMap(f.label, l),
          value: _answers[f.key] == true,
          onChanged: (v) => setState(() => _answers[f.key] = v),
        );
      case FormFieldType.singleChoice:
        return _choiceGroup(f, l, multi: false);
      case FormFieldType.multiChoice:
        return _choiceGroup(f, l, multi: true);
      case FormFieldType.text:
      case FormFieldType.textarea:
        // Telefon — login'dagi kabi +998 prefiks + XX XXX-XX-XX maska (faqat UZ).
        if (_formatOf(f) == 'phone') return _phoneField(f, l);
        return _textField(f, l, multiline: f.type == FormFieldType.textarea);
      case FormFieldType.number:
      case FormFieldType.integer:
        return _textField(f, l, numeric: true,
            integer: f.type == FormFieldType.integer);
      case FormFieldType.date:
        return _dateField(f, l);
      case FormFieldType.rooms:
        return _RoomsField(
          label: trMap(f.label, l),
          locale: l,
          value: (_answers[f.key] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
          onChanged: (rooms) => setState(() => _answers[f.key] = rooms),
        );
      case FormFieldType.unknown:
        return const SizedBox.shrink();
    }
  }

  Widget _label(FormFieldDef f, Locale l) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          f.required ? '${trMap(f.label, l)} *' : trMap(f.label, l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _muted(context),
          ),
        ),
      );

  Widget _choiceGroup(FormFieldDef f, Locale l, {required bool multi}) {
    final selected = multi
        ? ((_answers[f.key] as List?)?.cast<String>() ?? const <String>[])
        : <String>[if (_answers[f.key] != null) _answers[f.key].toString()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f, l),
        for (final o in f.options) ...[
          ChoiceTile(
            label: trMap(o.label, l),
            selected: selected.contains(o.value),
            onTap: () => setState(() {
              if (multi) {
                final list = List<String>.from(selected);
                list.contains(o.value)
                    ? list.remove(o.value)
                    : list.add(o.value);
                _answers[f.key] = list;
              } else {
                _answers[f.key] = o.value;
              }
            }),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// Telefon maydoni — login bilan bir xil: o'zgarmas `+998` prefiks +
  /// `XX XXX-XX-XX` maska (faqat O'zbekiston raqamlari). Tashqariga
  /// normallashtirilgan `998XXXXXXXXX` (yoki bo'sh) yoziladi.
  Widget _phoneField(FormFieldDef f, Locale l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f, l),
        _PhoneField(
          initial: (_answers[f.key] ?? '').toString(),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 14,
            height: 1.35,
            color: _txt(context),
          ),
          decoration: _decoration(f, l).copyWith(
            prefixText: '+998 ',
            prefixStyle: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 14,
              color: _txt(context),
            ),
            hintText: '90 123 45 67',
          ),
          onNormalized: (v) => _answers[f.key] = v,
        ),
      ],
    );
  }

  Widget _textField(FormFieldDef f, Locale l,
      {bool multiline = false, bool numeric = false, bool integer = false}) {
    final fmt = _formatOf(f);
    // Kiritishni cheklash: STIR faqat raqam (telefon alohida _phoneField'da).
    final formatters = <TextInputFormatter>[];
    if (fmt == 'tin') {
      formatters
        ..add(FilteringTextInputFormatter.digitsOnly)
        ..add(LengthLimitingTextInputFormatter(14));
    } else if (numeric) {
      formatters.add(FilteringTextInputFormatter.allow(
          RegExp(integer ? r'[0-9]' : r'[0-9.,]')));
    }
    final keyboard = switch (fmt) {
      'email' => TextInputType.emailAddress,
      'tin' => TextInputType.number,
      _ => numeric
          ? TextInputType.numberWithOptions(decimal: !integer)
          : (multiline ? TextInputType.multiline : TextInputType.text),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f, l),
        TextField(
          controller: _ctrl(f),
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 5 : 1,
          keyboardType: keyboard,
          inputFormatters: formatters.isEmpty ? null : formatters,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 14,
            height: 1.35,
            color: _txt(context),
          ),
          onChanged: (raw) {
            // STIR `text` turida — raqam string sifatida saqlanadi.
            if (numeric && fmt != 'tin') {
              final t = raw.trim().replaceAll(',', '.');
              _answers[f.key] =
                  integer ? int.tryParse(t) : double.tryParse(t);
            } else {
              _answers[f.key] = raw;
            }
          },
          decoration: _decoration(f, l),
        ),
      ],
    );
  }

  Widget _dateField(FormFieldDef f, Locale l) {
    final v = _answers[f.key] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f, l),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() => _answers[f.key] =
                  picked.toIso8601String().split('T').first);
            }
          },
          child: InputDecorator(
            decoration: _decoration(f, l),
            child: Text(
              v ?? trMap(f.placeholder, l),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 14,
                color: v == null ? _muted(context) : _txt(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Placeholder — backend bersa o'sha, aks holda format/kalit bo'yicha namuna.
  String _hint(FormFieldDef f, Locale l) {
    final p = trMap(f.placeholder, l);
    if (p.isNotEmpty) return p;
    // Backend placeholder bermagan paytdagi namuna (prod re-seed qilinmaguncha).
    switch (_formatOf(f)) {
      case 'phone':
        return '+998 90 123 45 67';
      case 'email':
        return 'sample@mail.com';
      case 'tin':
        return '300000000';
    }
    if (f.key == 'customer_name') {
      return switch (l.languageCode) {
        'ru' => 'Иван Иванов',
        'en' => 'John Smith',
        _ => 'Asliddin Hamrayev',
      };
    }
    return '';
  }

  InputDecoration _decoration(FormFieldDef f, Locale l) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    return InputDecoration(
      hintText: _hint(f, l),
      hintStyle: TextStyle(
        fontFamily: 'MTSCompact',
        fontSize: 13,
        color: _muted(context),
      ),
      suffixText: f.unit,
      suffixStyle: TextStyle(
        fontFamily: 'MTSCompact',
        fontSize: 13,
        color: _muted(context),
      ),
      filled: true,
      fillColor: fieldBg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.4),
      ),
    );
  }

  Color _txt(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? Colors.white : AppColors.textBlack;
  Color _muted(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFF9BA1A6)
      : const Color(0xFF6C7278);

  // ── i18n ──────────────────────────────────────────────────────────────
  String _continueLabel(Locale l) => switch (l.languageCode) {
        'ru' => 'Продолжить',
        'en' => 'Continue',
        _ => 'Davom etish',
      };
  String _submitLabel(Locale l) => switch (l.languageCode) {
        'ru' => 'Отправить',
        'en' => 'Submit',
        _ => 'Yuborish',
      };
  String _req(Locale l) => switch (l.languageCode) {
        'ru' => 'обязательно',
        'en' => 'required',
        _ => 'majburiy',
      };
  String _phoneErr(Locale l) => switch (l.languageCode) {
        'ru' => 'Телефон — введите корректный номер, напр. +998 90 123 45 67',
        'en' => 'Phone — enter a valid number, e.g. +998 90 123 45 67',
        _ => 'Telefon — to\'g\'ri raqam kiriting, masalan +998 90 123 45 67',
      };
  String _emailErr(Locale l) => switch (l.languageCode) {
        'ru' => 'Email — введите корректный адрес',
        'en' => 'Email — enter a valid address',
        _ => 'Email — to\'g\'ri manzil kiriting',
      };
  String _tinErr(Locale l) => switch (l.languageCode) {
        'ru' => 'СТИР/ИНН — 9 или 14 цифр',
        'en' => 'TIN — 9 or 14 digits',
        _ => 'STIR/INN — 9 yoki 14 raqam',
      };
  String _sent(Locale l) => switch (l.languageCode) {
        'ru' => 'Заявка отправлена',
        'en' => 'Order submitted',
        _ => 'Ariza yuborildi',
      };
  String _loginFirst(Locale l) => switch (l.languageCode) {
        'ru' => 'Сначала войдите в систему',
        'en' => 'Please sign in first',
        _ => 'Avval tizimga kiring',
      };
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: textColor,
              ),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.splashGreen,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Qayta urinish')),
          ],
        ),
      ),
    );
  }
}

/// Minimal xonalar muharriri — har bir qator {name, count, area_sqm}.
class _RoomsField extends StatelessWidget {
  const _RoomsField({
    required this.label,
    required this.locale,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final Locale locale;
  final List<Map<String, dynamic>> value;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: muted)),
        ),
        for (var i = 0; i < value.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: value[i]['name']?.toString() ?? '',
                    style: const TextStyle(
                        fontFamily: 'MTSCompact', fontSize: 14),
                    decoration: _miniDec(context, _nameHint(locale)),
                    onChanged: (v) => _update(i, 'name', v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: value[i]['count']?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontFamily: 'MTSCompact', fontSize: 14),
                    decoration: _miniDec(context, '×'),
                    onChanged: (v) => _update(i, 'count', int.tryParse(v)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    final list =
                        List<Map<String, dynamic>>.from(value)..removeAt(i);
                    onChanged(list);
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => onChanged(
              List<Map<String, dynamic>>.from(value)
                ..add({'name': '', 'count': 1}),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(_addRoom(locale)),
          ),
        ),
      ],
    );
  }

  void _update(int i, String key, dynamic v) {
    final list = List<Map<String, dynamic>>.from(value);
    list[i] = {...list[i], key: v};
    onChanged(list);
  }

  InputDecoration _miniDec(BuildContext context, String hint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    return InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.3),
      ),
    );
  }

  String _nameHint(Locale l) => switch (l.languageCode) {
        'ru' => 'Помещение',
        'en' => 'Room',
        _ => 'Xona',
      };
  String _addRoom(Locale l) => switch (l.languageCode) {
        'ru' => 'Добавить помещение',
        'en' => 'Add room',
        _ => 'Xona qo\'shish',
      };
}

/// Login'dagi telefon formatini (faqat O'zbekiston: `+998` prefiks +
/// `XX XXX-XX-XX` maska) dinamik forma ichida qayta ishlatadi. Tashqariga
/// normallashtirilgan `998XXXXXXXXX` (yoki bo'sh satr) qiymatni qaytaradi.
class _PhoneField extends StatefulWidget {
  const _PhoneField({
    required this.initial,
    required this.style,
    required this.decoration,
    required this.onNormalized,
  });

  final String initial;
  final TextStyle style;
  final InputDecoration decoration;
  final ValueChanged<String> onNormalized;

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  late final TextEditingController _c;

  /// Har qanday formatdan 9 xonali milliy qismni ajratadi (998 prefiks olib
  /// tashlanadi, 9 tagacha kesiladi).
  static String _national(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('998')) d = d.substring(3);
    if (d.length > 9) d = d.substring(0, 9);
    return d;
  }

  static String _mask(String d) {
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2) {
        b.write(' ');
      } else if (i == 5 || i == 7) {
        b.write('-');
      }
      b.write(d[i]);
    }
    return b.toString();
  }

  @override
  void initState() {
    super.initState();
    final nat = _national(widget.initial);
    _c = TextEditingController(text: _mask(nat));
    // Oldindan to'ldirilgan qiymatni normallashtirib answerга yozib qo'yamiz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onNormalized(nat.isEmpty ? '' : '998$nat');
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: TextInputType.number,
      inputFormatters: [_UzPhoneMask()],
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      style: widget.style,
      decoration: widget.decoration,
      onChanged: (raw) {
        final d = _national(raw);
        widget.onNormalized(d.isEmpty ? '' : '998$d');
      },
    );
  }
}

/// 9 xonali milliy raqamni `XX XXX-XX-XX` ko'rinishiga keltiradi va kursorni
/// to'g'ri joylaydi (o'rta tahrirda sakramaydi). Login maskasining nusxasi.
class _UzPhoneMask extends TextInputFormatter {
  static const _max = 9;

  static bool _isDigit(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

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

    final allDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped =
        allDigits.length > _max ? allDigits.substring(0, _max) : allDigits;

    final buf = StringBuffer();
    for (var i = 0; i < clipped.length; i++) {
      if (i == 2) {
        buf.write(' ');
      } else if (i == 5 || i == 7) {
        buf.write('-');
      }
      buf.write(clipped[i]);
    }
    final formatted = buf.toString();

    final targetDigits = digitsBeforeCursor.clamp(0, clipped.length);
    var seen = 0;
    var pos = 0;
    while (pos < formatted.length && seen < targetDigits) {
      if (_isDigit(formatted[pos])) seen++;
      pos++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: pos),
      composing: TextRange.empty,
    );
  }
}
