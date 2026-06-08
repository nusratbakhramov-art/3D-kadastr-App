import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.placeholderLogoScale = 0.42,
  });

  final String url;
  final BoxFit fit;
  final int? memCacheWidth;
  final double placeholderLogoScale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (url.isEmpty) {
      return _LogoPlaceholder(dark: isDark, scale: placeholderLogoScale);
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 220),
      placeholder: (_, _) => _Shimmer(dark: isDark),
      errorWidget: (_, _, _) =>
          _LogoPlaceholder(dark: isDark, scale: placeholderLogoScale),
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder({required this.dark, required this.scale});

  final bool dark;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF1E2324) : const Color(0xFFF3F4F6);
    final logoOpacity = dark ? 0.16 : 0.22;

    return ColoredBox(
      color: bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side =
              (constraints.biggest.shortestSide * scale).clamp(28.0, 96.0);
          return Center(
            child: Opacity(
              opacity: logoOpacity,
              child: SvgPicture.asset(
                'assets/branding/splash-logo.svg',
                width: side,
                height: side,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.dark});
  final bool dark;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.dark ? const Color(0xFF1E2324) : const Color(0xFFEEF1F4);
    final highlight =
        widget.dark ? const Color(0xFF2A3032) : const Color(0xFFF7F8FA);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t - 0.3, -0.3),
              end: Alignment(-1 + 2 * t + 0.3, 0.3),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
