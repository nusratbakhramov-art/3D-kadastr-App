import 'package:flutter/material.dart';

import '../models/market_listing.dart';
import 'listing_card.dart';
import 'listing_skeleton_card.dart';

class ListingGrid extends StatelessWidget {
  const ListingGrid({
    super.key,
    required this.items,
    required this.onDetailsTap,
  }) : isSkeleton = false,
       skeletonCount = 0;

  const ListingGrid.skeleton({super.key, this.skeletonCount = 6})
    : isSkeleton = true,
      items = const [],
      onDetailsTap = _noop;

  final bool isSkeleton;
  final int skeletonCount;
  final List<MarketListing> items;
  final ValueChanged<MarketListing> onDetailsTap;

  static void _noop(MarketListing _) {}

  @override
  Widget build(BuildContext context) {
    final count = isSkeleton ? skeletonCount : items.length;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.60,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (isSkeleton) return const ListingSkeletonCard();
        return ListingCard(listing: items[index], onDetailsTap: onDetailsTap);
      },
    );
  }
}
