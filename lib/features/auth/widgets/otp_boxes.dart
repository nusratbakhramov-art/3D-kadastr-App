import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';

enum OtpBoxState { neutral, error, success }

class OtpController extends ChangeNotifier {
  OtpController({required this.length});

  final int length;
  String _value = '';
  TextEditingController? _text;

  String get value => _value;

  void _attach(TextEditingController text) {
    _text = text;
  }

  void _update(String v) {
    if (_value == v) return;
    _value = v;
    notifyListeners();
  }

  void clear() {
    _value = '';
    _text?.clear();
    notifyListeners();
  }
}

class OtpBoxes extends StatefulWidget {
  const OtpBoxes({
    super.key,
    required this.length,
    required this.onChanged,
    this.onCompleted,
    this.controller,
    this.state = OtpBoxState.neutral,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final OtpController? controller;
  final OtpBoxState state;
  final bool autofocus;

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
  late final OtpController _ctrl;
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  bool _ownsCtrl = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? OtpController(length: widget.length);
    _ownsCtrl = widget.controller == null;
    _text = TextEditingController();
    _ctrl._attach(_text);
    _ctrl.addListener(_onCtrl);
    _focus.addListener(_onCtrl);
  }

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrl);
    _focus.removeListener(_onCtrl);
    _text.dispose();
    _focus.dispose();
    if (_ownsCtrl) _ctrl.dispose();
    super.dispose();
  }

  void _handleChange(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > widget.length
        ? digits.substring(0, widget.length)
        : digits;
    if (clipped != v) {
      _text.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
    }
    _ctrl._update(clipped);
    widget.onChanged(clipped);
    if (clipped.length == widget.length) {
      widget.onCompleted?.call(clipped);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final available = constraints.maxWidth;
        final boxSize = (available - gap * (widget.length - 1)) / widget.length;
        final size = boxSize.clamp(32.0, 64.0);
        return SizedBox(
          height: size,
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(widget.length, (i) {
                  return SizedBox(
                    width: size,
                    height: size,
                    child: _OtpBox(
                      key: ValueKey('otp.box.$i'),
                      digit: i < _ctrl.value.length ? _ctrl.value[i] : '',
                      focused: i == _ctrl.value.length && _focus.hasFocus,
                      state: widget.state,
                    ),
                  );
                }),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    maxLength: widget.length,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: _handleChange,
                    decoration: const InputDecoration(counterText: ''),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    super.key,
    required this.digit,
    required this.focused,
    required this.state,
  });

  final String digit;
  final bool focused;
  final OtpBoxState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutralBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.88);
    final neutralBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFD9DDE2);
    final neutralFg = isDark ? Colors.white : AppColors.textBlack;

    final (bg, border, fg) = switch (state) {
      OtpBoxState.success => (
        const Color(0xFF0B3B19),
        AppColors.splashGreen,
        AppColors.splashGreen,
      ),
      OtpBoxState.error => (
        Colors.transparent,
        const Color(0xFFEB5757),
        neutralFg,
      ),
      OtpBoxState.neutral => (
        neutralBg,
        focused ? AppColors.splashGreen : neutralBorder,
        neutralFg,
      ),
    };
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.5),
      ),
      alignment: Alignment.center,
      child: digit.isEmpty
          ? (focused
                ? Container(width: 2, height: 28, color: AppColors.splashGreen)
                : const SizedBox())
          : Text(
              digit,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 28,
                color: fg,
              ),
            ),
    );
  }
}
