/// Kadastr raqamini kiritish + avtomatik qidirish (lookup) maydoni.
///
/// AI baholashning birinchi qadamidagi kabi: to'liq kadastr raqami kiritilsa,
/// davreestr orqali manzil/maydon topiladi va `onResult` chaqiriladi.
/// Wizardning step 2 sida oddiy matn maydoni o'rniga ishlatiladi.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../api_cadastre_service.dart';

class CadastreLookupField extends StatefulWidget {
  const CadastreLookupField({
    super.key,
    required this.controller,
    required this.onResult,
    this.label,
  });

  final TextEditingController controller;
  final ValueChanged<CadastreLookupResult> onResult;

  /// Maydon yorlig'i; `null` bo'lsa joriy tilda 'Kadastr raqami' ishlatiladi.
  final String? label;

  @override
  State<CadastreLookupField> createState() => _CadastreLookupFieldState();
}

enum _Status { idle, loading, loaded, error }

class _CadastreLookupFieldState extends State<CadastreLookupField> {
  // To'liq yoki kengaytirilgan kadastr format: 10:09:01:01:02:5942[:0001…]
  static final _fullRe =
      RegExp(r'^\d{2}:\d{2}:\d{2}:\d{2}:\d{2}:\d{4}(:\d{1,4})*$');

  Timer? _debounce;
  int _reqId = 0;
  _Status _status = _Status.idle;
  String _message = '';
  CadastreLookupResult? _info;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (_fullRe.hasMatch(widget.controller.text.trim())) {
      _runLookup();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final text = widget.controller.text.trim();
    if (!_fullRe.hasMatch(text)) {
      if (_status != _Status.idle) setState(() => _status = _Status.idle);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _runLookup);
  }

  Future<void> _runLookup() async {
    final number = widget.controller.text.trim();
    if (!_fullRe.hasMatch(number)) return;
    final id = ++_reqId;
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) {
      // Token yo'q — jimgina qoldiramiz, raqamni qo'lda yozish mumkin.
      return;
    }
    if (!mounted || id != _reqId) return;
    setState(() {
      _status = _Status.loading;
      _info = null;
    });
    try {
      final result =
          await CadastreApiService().lookup(cadastreNumber: number, token: token);
      if (!mounted || id != _reqId) return;
      // Natijada hech qanday foydali ma'lumot bo'lmasa — xato deb hisoblaymiz.
      final hasData = (result.address ?? '').isNotEmpty ||
          result.totalArea != null ||
          result.livingArea != null ||
          (result.objectTypeHint ?? '').isNotEmpty;
      if (!hasData) {
        setState(() {
          _status = _Status.error;
          _message = _CadastreStrings.noData(Localizations.localeOf(context));
        });
        return;
      }
      setState(() {
        _status = _Status.loaded;
        _info = result;
      });
      widget.onResult(result);
    } on CadastreLookupException catch (e) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _status = _Status.error;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _status = _Status.error;
        _message = _CadastreStrings.searchError(Localizations.localeOf(context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label ?? _CadastreStrings.label(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.25,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 14.5,
            color: textColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            hintText: '10:09:01:01:02:5942',
            hintStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14.5,
              color: hintColor,
            ),
            suffixIcon: _status == _Status.loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.splashGreen,
                      ),
                    ),
                  )
                : (_status == _Status.loaded
                    ? const Icon(Icons.check_circle,
                        color: AppColors.splashGreen, size: 22)
                    : null),
            filled: true,
            fillColor: fill,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.splashGreen, width: 1.4),
            ),
          ),
        ),
        if (_status == _Status.loaded && _info != null) ...[
          const SizedBox(height: 6),
          _ResultSummary(info: _info!),
        ],
        if (_status == _Status.error) ...[
          const SizedBox(height: 5),
          Text(
            _message,
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

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.info});
  final CadastreLookupResult info;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF6B7280);
    final parts = <String>[
      if ((info.address ?? '').isNotEmpty) info.address!.trim(),
      if (info.totalArea != null) '${info.totalArea} m²',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    final text = parts.join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12,
              height: 1.3,
              color: sub,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Manzil/maydonni nusxalash — kichik, bilinar-bilinmas tugma.
        InkWell(
          onTap: () async {
            HapticFeedback.lightImpact();
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    _CadastreStrings.copied(Localizations.localeOf(context)),
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 1200),
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.copy_rounded, size: 15, color: sub),
          ),
        ),
      ],
    );
  }
}

class _CadastreStrings {
  const _CadastreStrings._();

  static String label(Locale l) => tr(l, 'services.widget.cadastre.label');

  static String noData(Locale l) => tr(l, 'services.widget.cadastre.no_data');

  static String searchError(Locale l) =>
      tr(l, 'services.widget.cadastre.search_error');

  static String copied(Locale l) => tr(l, 'services.widget.cadastre.copied');
}
