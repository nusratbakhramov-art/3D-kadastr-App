import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/i18n.dart';
import '../../../theme/app_colors.dart';

class MarketSearchBar extends StatefulWidget {
  const MarketSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<MarketSearchBar> createState() => _MarketSearchBarState();
}

class _MarketSearchBarState extends State<MarketSearchBar> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final hint = fg.withValues(alpha: 0.4);
    final focused = _focus.hasFocus;
    final borderColor = focused
        ? AppColors.splashGreen
        : (isDark ? Colors.transparent : const Color(0xFFE1E1E1));
    final borderWidth = focused ? 1.5 : 1.0;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(1000),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            children: [
              const SizedBox(width: 6),
              SvgPicture.asset(
                'assets/icons/search.svg',
                width: 18,
                height: 18,
                colorFilter: ColorFilter.mode(
                  focused ? AppColors.splashGreen : hint,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  onChanged: widget.onChanged,
                  cursorColor: AppColors.splashGreen,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    height: 1.2,
                    color: fg,
                  ),
                  decoration: InputDecoration(
                    hintText: L.search(locale),
                    hintStyle: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      height: 1.2,
                      color: hint,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
              if (value.text.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                )
              else
                const SizedBox(width: 6),
            ],
          ),
        );
      },
    );
  }
}
