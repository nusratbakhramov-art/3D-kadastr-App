import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneInputController extends ChangeNotifier {
  String _digits = '';

  String get digits => _digits;
  bool get isValid => _digits.length == 9;

  void setDigits(String value) {
    if (_digits == value) return;
    _digits = value;
    notifyListeners();
  }
}

class PhoneInputField extends StatefulWidget {
  const PhoneInputField({super.key, this.controller, this.onChanged});

  final PhoneInputController? controller;
  final ValueChanged<String>? onChanged;

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  late final TextEditingController _text;
  late final PhoneInputController _ctrl;
  final FocusNode _focus = FocusNode();
  bool _ownsCtrl = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? PhoneInputController();
    _ownsCtrl = widget.controller == null;
    _text = TextEditingController();
    _ctrl.addListener(_syncFromController);
    _focus.addListener(_rebuild);
    // Seed with any initial digits.
    _syncFromController();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _syncFromController() {
    final formatted = _format(_ctrl.digits);
    if (_text.text != formatted) {
      _text.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    _rebuild();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncFromController);
    _focus.removeListener(_rebuild);
    _text.dispose();
    _focus.dispose();
    if (_ownsCtrl) _ctrl.dispose();
    super.dispose();
  }

  static String _format(String digits) {
    // 9 digits -> XX XXX-XX-XX
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) {
        buf.write(' ');
      } else if (i == 5 || i == 7) {
        buf.write('-');
      }
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  void _handleChange(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > 9 ? digits.substring(0, 9) : digits;
    final wasIncomplete = _ctrl.digits.length < 9;
    final formatted = _format(clipped);
    if (_text.text != formatted) {
      _text.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    _ctrl.setDigits(clipped);
    if (wasIncomplete && clipped.length == 9) {
      HapticFeedback.selectionClick();
    }
    widget.onChanged?.call(clipped);
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'MTSCompact',
      fontWeight: FontWeight.w700,
      fontSize: 28,
      color: Colors.white,
    );
    return GestureDetector(
      onTap: _focus.requestFocus,
      behavior: HitTestBehavior.opaque,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 360,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('+998', style: style, maxLines: 1, softWrap: false),
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  children: [
                    if (_ctrl.digits.isEmpty)
                      const IgnorePointer(
                        child: Text(
                          '00 000-00-00',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 28,
                            color: Color(0x66FFFFFF),
                          ),
                        ),
                      ),
                    TextField(
                      controller: _text,
                      focusNode: _focus,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      maxLines: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      cursorColor: const Color(0xFF00E135),
                      style: style,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: _handleChange,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
