import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular user avatar with white ring. Falls back to a colored initial when
/// no image is available, and to a generic person icon when the name is empty.
///
/// [path] may be either an asset path (e.g. `assets/images/auth/user.png`) or
/// an absolute filesystem path (from image_picker). The renderer picks the
/// right loader by sniffing the prefix.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.path,
    required this.name,
    this.size = 96,
    this.ringWidth = 3,
    this.ringColor = Colors.white,
  });

  final String? path;
  final String name;
  final double size;
  final double ringWidth;
  final Color ringColor;

  bool get _isAsset => path != null && path!.startsWith('assets/');

  @override
  Widget build(BuildContext context) {
    final p = path;
    final hasName = name.isNotEmpty;
    final initial = hasName ? name.characters.first.toUpperCase() : null;
    final ring = Border.all(color: ringColor, width: ringWidth);

    if (p != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: ring),
        child: ClipOval(
          child: _isAsset
              ? Image.asset(p, fit: BoxFit.cover)
              : Image.file(File(p), fit: BoxFit.cover),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: initial == null ? const Color(0xFF2A2F31) : AppColors.brandGreen,
        shape: BoxShape.circle,
        border: ring,
      ),
      alignment: Alignment.center,
      child: initial == null
          ? Icon(
              Icons.person_outline_rounded,
              size: size * 0.46,
              color: Colors.white70,
            )
          : Text(
              initial,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38,
                color: Colors.white,
              ),
            ),
    );
  }
}
