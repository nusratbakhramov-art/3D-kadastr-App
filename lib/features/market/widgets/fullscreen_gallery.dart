import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

Future<void> openFullscreenGallery(
  BuildContext context, {
  required List<String> images,
  required int initialIndex,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0),
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) =>
          _FullscreenGallery(images: images, initialIndex: initialIndex),
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery>
    with SingleTickerProviderStateMixin {
  late final PageController _pager;
  late final AnimationController _snapBack;
  late int _index;

  /// Rasm kattalashtirilgan — bunda vertikal surish rasmni SURADI (pan),
  /// oynani yopmaydi.
  bool _zoomed = false;

  /// Barmoq bilan surilgan masofa (piksel). Musbat — pastga.
  double _dy = 0;

  /// Qaytish animatsiyasi boshlangan nuqta.
  double _dragFrom = 0;

  int _pointers = 0;
  Offset _dragStart = Offset.zero;

  /// Ishora yo'nalishi qulflandi: vertikal — yopish, gorizontal — sahifalash.
  /// `null` — hali aniqlanmagan (slop ichida).
  Axis? _axis;

  /// Shundan oshsa yopiladi; kami bo'lsa rasm joyiga qaytadi.
  static const double _dismissAt = 110;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pager = PageController(initialPage: _index);
    _snapBack =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final t = Curves.easeOutCubic.transform(_snapBack.value);
          setState(() => _dy = _dragFrom * (1 - t));
        });
  }

  @override
  void dispose() {
    _snapBack.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _close() {
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  /// 0..1 — surish qanchalik uzoqqa ketgani. Fon shaffofligi, boshqaruv
  /// elementlarining so'nishi va rasmning kichrayishi shunga bog'lanadi.
  double get _progress =>
      (_dy.abs() / (MediaQuery.sizeOf(context).height * 0.42)).clamp(0.0, 1.0);

  // photo_view o'z ishorasini gesture arenasida darhol egallaydi, shuning uchun
  // GestureDetector ham, Dismissible ham bu yerda ishlamaydi — surish ularga
  // yetib bormaydi. `Listener` esa xom pointer hodisalarini oladi va arenada
  // umuman qatnashmaydi, shuning uchun ikkalasi yonma-yon yashay oladi.
  void _onDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _snapBack.stop();
      _dragStart = e.position;
      _axis = null;
    }
  }

  void _onMove(PointerMoveEvent e) {
    // Kattalashtirilgan yoki ikki barmoq (masshtab) — aralashmaymiz.
    if (_zoomed || _pointers != 1) return;
    final d = e.position - _dragStart;
    if (_axis == null) {
      if (d.distance < kTouchSlop) return;
      // Gorizontalga moyil harakat — sahifalash, unga tegmaymiz.
      _axis = d.dy.abs() > d.dx.abs() * 1.4 ? Axis.vertical : Axis.horizontal;
    }
    if (_axis != Axis.vertical) return;
    setState(() => _dy = d.dy);
  }

  void _onUp(PointerEvent e) {
    if (_pointers > 0) _pointers--;
    if (_pointers > 0 || _axis != Axis.vertical) return;
    _axis = null;
    if (_dy.abs() >= _dismissAt) {
      HapticFeedback.selectionClick();
      Navigator.of(context).maybePop();
      return;
    }
    if (_dy != 0) {
      _dragFrom = _dy;
      _snapBack.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          child: Stack(
            children: [
              // Fon alohida qatlam — surilgan sari so'nadi va ortidagi e'lon
              // sahifasi ko'rina boshlaydi.
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 1 - p * 0.9),
                ),
              ),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, _dy),
                  // Qo'ldan qo'yib yuborilayotgandek biroz kichrayadi.
                  child: Transform.scale(
                    scale: 1 - p * 0.12,
                    child: _gallery(),
                  ),
                ),
              ),
              IgnorePointer(
                ignoring: p > 0,
                child: Opacity(
                  opacity: (1 - p * 2.5).clamp(0.0, 1.0),
                  child: _chrome(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gallery() {
    return PhotoViewGallery.builder(
      pageController: _pager,
      itemCount: widget.images.length,
      scrollPhysics: const BouncingScrollPhysics(),
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      onPageChanged: (i) => setState(() => _index = i),
      scaleStateChangedCallback: (state) {
        final zoomed = state != PhotoViewScaleState.initial;
        if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
      },
      loadingBuilder: (context, event) => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white,
          ),
        ),
      ),
      builder: (context, i) {
        return PhotoViewGalleryPageOptions(
          imageProvider: NetworkImage(widget.images[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.contained * 4,
          initialScale: PhotoViewComputedScale.contained,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.image_outlined, color: Colors.white54, size: 60),
          ),
        );
      },
    );
  }

  Widget _chrome() {
    return Stack(
      children: [
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.white.withValues(alpha: 0.18),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _close,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _Counter(index: _index, total: widget.images.length),
            ),
          ),
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${index + 1} / $total',
        style: const TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Colors.white,
        ),
      ),
    );
  }
}
