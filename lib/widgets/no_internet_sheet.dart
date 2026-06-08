import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../theme/app_colors.dart';

/// Animated bottom sheet shown when an API call fails because there's no
/// internet connection. Use [NetworkErrorHandler.maybeShow] to drive it from
/// catch blocks instead of calling this directly.
class NoInternetSheet extends StatefulWidget {
  const NoInternetSheet({super.key, this.onRetry});

  final VoidCallback? onRetry;

  static Future<bool> show(
    BuildContext context, {
    VoidCallback? onRetry,
  }) async {
    HapticFeedback.mediumImpact();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (_) => NoInternetSheet(onRetry: onRetry),
    );
    return result ?? false;
  }

  @override
  State<NoInternetSheet> createState() => _NoInternetSheetState();
}

class _NoInternetSheetState extends State<NoInternetSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : Colors.white;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF8A9097);
    final iconBg = isDark
        ? AppColors.splashGreen.withValues(alpha: 0.14)
        : AppColors.splashGreen.withValues(alpha: 0.10);
    final grabberColor =
        isDark ? Colors.white24 : const Color(0xFFE3E5E8);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: grabberColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    return SizedBox(
                      width: 144,
                      height: 144,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _Ring(progress: t, baseSize: 96),
                          _Ring(progress: (t + 0.5) % 1.0, baseSize: 96),
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: iconBg,
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              size: 44,
                              color: AppColors.splashGreen,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  'Internet aloqasi yo\'q',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: headingColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ulanishingizni tekshirib, qayta urinib ko\'ring',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 14,
                    height: 1.4,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop(true);
                      widget.onRetry?.call();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.splashGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    child: Text(L.retry(Localizations.localeOf(context))),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(
                    'Yopish',
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: subColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress, required this.baseSize});

  final double progress;
  final double baseSize;

  @override
  Widget build(BuildContext context) {
    final size = baseSize + 48 * progress;
    final opacity = (1 - progress).clamp(0.0, 1.0) * 0.22;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.splashGreen.withValues(alpha: opacity),
            width: 2,
          ),
        ),
      ),
    );
  }
}
