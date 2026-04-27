import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CircleChevronRight extends StatelessWidget {
  const CircleChevronRight({
    super.key,
    this.size = 20,
    this.padding = 2,
    this.iconSize = 16,
    this.backgroundColor = const Color(0xFF18181B),
  });

  final double size;
  final double padding;
  final double iconSize;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(1000),
      ),
      child: SvgPicture.asset(
        'assets/icons/chevron-right.svg',
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
      ),
    );
  }
}
