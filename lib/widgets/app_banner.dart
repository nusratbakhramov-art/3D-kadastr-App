// Yuqoridan tushadigan qisqa xabar — SnackBar o'rniga.
//
// SnackBar ekranning PASTIDA, tizim navigatsiya paneli ustida chiqadi: u yerda
// barmoq turadi, orqa fon bilan qo'shilib ketadi va amal bajarilgan joydan
// (yuqoridagi tugmadan) uzoq. Bu banner amal joyiga yaqin tushadi va
// qurilmaning O'Z xabarlari kabi tutadi:
//
//   * o'zi yo'qoladi (3.2 s),
//   * YUQORIGA surilsa — iOS'dagidek,
//   * CHAPGA surilsa — Android'dagidek.
//
// Overlay'da yashaydi, shuning uchun Scaffold ham, ScaffoldMessenger ham
// kerak emas va u sahifa almashsa ham to'g'ri joyda qoladi.
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/color_tokens.dart';

/// Xabarni ekran tepasida ko'rsatadi. Xato bo'lsa `isError: true`.
void showAppBanner(BuildContext context, String message, {bool isError = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Banner(
      message: message,
      isError: isError,
      onGone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _Banner extends StatefulWidget {
  const _Banner({
    required this.message,
    required this.isError,
    required this.onGone,
  });

  final String message;
  final bool isError;
  final VoidCallback onGone;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  static const Duration _visible = Duration(milliseconds: 3200);
  static const Color _red = Color(0xFFD64545);

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  )..forward();

  Timer? _timer;

  /// Barmoq bilan surilgan masofa. Yuqoriga — manfiy dy, chapga — manfiy dx.
  Offset _drag = Offset.zero;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_visible, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enter.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted) await _enter.reverse();
    widget.onGone();
  }

  // Pan EMAS, alohida vertikal va gorizontal taniqchilar: pan ro'yxatning
  // vertikal scroll taniqchisi bilan bitta "arena"da raqobatlashadi va yutqazadi
  // — barmoq tegadi, lekin banner joyida qoladi. Yo'nalishlar ajratilganda
  // yuqoriga surish ham, chapga surish ham o'z taniqchisiga tushadi.
  void _onDragUpdate(Offset delta) {
    // Qo'l tekkan zahoti avtomatik yopilish bekor bo'ladi — o'qiyotgan
    // odamning tagidan xabarni tortib olmaymiz.
    _timer?.cancel();
    setState(() {
      _drag += delta;
      // Pastga cho'zilmasin: bu banner tepada turadi.
      if (_drag.dy > 0) _drag = Offset(_drag.dx, _drag.dy * 0.15);
      // O'ngga ham sudralmasin — yopish imkoni chapda.
      if (_drag.dx > 0) _drag = Offset(_drag.dx * 0.15, _drag.dy);
    });
  }

  void _settle({required bool gone}) {
    if (gone) {
      _dismiss();
      return;
    }
    setState(() => _drag = Offset.zero);
    _timer = Timer(_visible, _dismiss);
  }

  void _onVerticalEnd(DragEndDetails d) => _settle(
    gone: _drag.dy < -34 || d.velocity.pixelsPerSecond.dy < -420,
  );

  void _onHorizontalEnd(DragEndDetails d) => _settle(
    gone: _drag.dx < -84 || d.velocity.pixelsPerSecond.dx < -520,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.isError
        ? _red
        : (isDark ? AppColors.splashGreen : AppColors.brandGreen);
    final top = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _enter,
          child: Transform.translate(
            offset: _drag,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => _onDragUpdate(d.delta),
              onVerticalDragEnd: _onVerticalEnd,
              onHorizontalDragUpdate: (d) => _onDragUpdate(d.delta),
              onHorizontalDragEnd: _onHorizontalEnd,
              onTap: _dismiss,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceHigh
                        : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.45 : 0.14,
                        ),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isError
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_rounded,
                        size: 21,
                        color: accent,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 14.5,
                            height: 1.35,
                            color: ColorTokens.primaryText(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
