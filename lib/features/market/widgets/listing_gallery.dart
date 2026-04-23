import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import 'fullscreen_gallery.dart';

class ListingGallery extends StatefulWidget {
  const ListingGallery({
    super.key,
    required this.images,
    required this.heroTag,
    required this.onClose,
    required this.onShare,
  });

  final List<String> images;
  final Object heroTag;
  final VoidCallback onClose;
  final VoidCallback onShare;

  @override
  State<ListingGallery> createState() => _ListingGalleryState();
}

class _ListingGalleryState extends State<ListingGallery> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openFullscreen() {
    HapticFeedback.selectionClick();
    openFullscreenGallery(context, images: widget.images, initialIndex: _index);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.hardEdge,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: widget.images.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final image = GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openFullscreen,
                      child: _GalleryImage(url: widget.images[i]),
                    );
                    if (i == 0) {
                      return Hero(tag: widget.heroTag, child: image);
                    }
                    return image;
                  },
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _RoundIconButton(
                    icon: Icons.ios_share_rounded,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onShare();
                    },
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onClose();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Dots(count: widget.images.length, index: _index),
      ],
    );
  }
}

class _GalleryImage extends StatelessWidget {
  const _GalleryImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEEF1F4),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: 1200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.image_outlined, size: 44, color: Color(0xFFB4B9BF)),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: AppColors.textBlack),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? AppColors.splashGreen : const Color(0xFFD1D5D9),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
