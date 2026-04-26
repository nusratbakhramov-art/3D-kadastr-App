import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class ServicePlaceholderScreen extends StatelessWidget {
  const ServicePlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppColors.greenBlack
          : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: isDark ? Colors.white : AppColors.textBlack,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppColors.textBlack,
        ),
      ),
      body: Center(
        child: Text(
          'Tez orada',
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 15,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );
  }
}
