import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/market/models/market_listing.dart';
import 'package:kadastr/features/market/widgets/listing_card.dart';
import 'package:kadastr/features/market/widgets/listing_skeleton_card.dart';

/// The market grid uses a masonry sliver, which measures each child with an
/// UNBOUNDED main-axis (height) constraint. A card whose Column is not
/// intrinsically sized (MainAxisSize.max / Expanded / Spacer) throws a
/// RenderFlex "unbounded" assertion there — which is what crashed the Market
/// tab (the ErrorWidget then broke the viewport's sliver expectation).
///
/// A vertical ListView reproduces the exact same unbounded-height constraint,
/// so these guard against the regression without needing the whole screen.
void main() {
  Widget underUnboundedHeight(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 180, child: ListView(children: [child])),
        ),
      );

  testWidgets('ListingSkeletonCard lays out under unbounded height',
      (tester) async {
    await tester.pumpWidget(underUnboundedHeight(const ListingSkeletonCard()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ListingCard lays out under unbounded height', (tester) async {
    const listing = MarketListing(
      id: 'x',
      imageUrl: 'https://example.com/a.jpg',
      priceUzs: 0, // also exercises the "Bepul" badge path
      title: 'Test',
      district: 'Sergeli tumani',
      areaM2: 80,
      categoryId: 'residential',
      floor: 3,
    );
    await tester.pumpWidget(
      underUnboundedHeight(ListingCard(listing: listing, onTap: (_) {})),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}
