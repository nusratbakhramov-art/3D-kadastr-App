import 'package:flutter/material.dart';

class ListingSkeletonCard extends StatefulWidget {
  const ListingSkeletonCard({super.key});

  @override
  State<ListingSkeletonCard> createState() => _ListingSkeletonCardState();
}

class _ListingSkeletonCardState extends State<ListingSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF121617) : Colors.white;
    final baseA = isDark ? const Color(0xFF1A2024) : const Color(0xFFE7EAEE);
    final baseB = isDark ? const Color(0xFF262C31) : const Color(0xFFF2F4F7);
    final border = isDark ? null : Border.all(color: const Color(0xFFE3E5E8));

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final shade = Color.lerp(baseA, baseB, _pulse.value)!;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: border,
          ),
          child: Column(
            // Masonry grid bolalarni cheksiz balandlikda o'lchaydi — skeleton
            // intrinsic balandlikda bo'lishi shart: Expanded/Spacer ishlatmaymiz.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                clipBehavior: Clip.hardEdge,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(color: shade),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(shade, width: 80, height: 12),
                    const SizedBox(height: 6),
                    _bar(shade, width: double.infinity, height: 12),
                    const SizedBox(height: 8),
                    _bar(shade, width: 110, height: 10),
                    const SizedBox(height: 4),
                    _bar(shade, width: 60, height: 10),
                    const SizedBox(height: 12),
                    Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: shade,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(Color color, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
