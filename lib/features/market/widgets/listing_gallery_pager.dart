import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import 'fullscreen_gallery.dart';

class ListingGalleryPager extends StatefulWidget {
  const ListingGalleryPager({
    super.key,
    required this.images,
    this.height = 320,
    this.onClose,
    this.onShare,
  });

  final List<String> images;
  final double height;
  final VoidCallback? onClose;
  final VoidCallback? onShare;

  @override
  State<ListingGalleryPager> createState() => _ListingGalleryPagerState();
}

class _ListingGalleryPagerState extends State<ListingGalleryPager> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04);

    if (widget.images.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: widget.height,
          child: ColoredBox(
            color: bg,
            child: Center(
              child: Icon(
                Icons.image_outlined,
                size: 48,
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      openFullscreenGallery(
                        context,
                        images: widget.images,
                        initialIndex: i,
                      );
                    },
                    child: Image.network(
                    widget.images[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: bg,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 40,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return ColoredBox(
                        color: bg,
                        child: const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      );
                    },
                  ),
                  );
                },
              ),
            ),
            if (widget.onShare != null)
              Positioned(
                top: 12,
                left: 12,
                child: _RoundButton(
                  icon: Icons.ios_share,
                  isDark: isDark,
                  onTap: widget.onShare!,
                ),
              ),
            if (widget.onClose != null)
              Positioned(
                top: 12,
                right: 12,
                child: _RoundButton(
                  icon: Icons.close,
                  isDark: isDark,
                  onTap: widget.onClose!,
                ),
              ),
            if (widget.images.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(
                  child: _PageDots(
                    count: widget.images.length,
                    index: _index,
                    isDark: isDark,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.isDark,
  });

  final int count;
  final int index;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == index ? 7 : 6,
                height: i == index ? 7 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == index
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7);
    final fg = isDark ? Colors.white : AppColors.textBlack;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: fg),
        ),
      ),
    );
  }
}
