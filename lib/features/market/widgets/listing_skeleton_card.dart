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
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final shade = Color.lerp(
          const Color(0xFFE7EAEE),
          const Color(0xFFF2F4F7),
          _pulse.value,
        )!;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE3E5E8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(color: shade),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line(shade, width: 92, height: 14),
                      const SizedBox(height: 8),
                      _line(shade, width: double.infinity, height: 18),
                      const SizedBox(height: 12),
                      _line(shade, width: 124, height: 12),
                      const SizedBox(height: 8),
                      _line(shade, width: 76, height: 12),
                      const Spacer(),
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: shade,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _line(Color color, {required double width, required double height}) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
