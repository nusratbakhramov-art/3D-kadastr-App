class MarketListing {
  const MarketListing({
    required this.id,
    required this.imageUrl,
    required this.priceUzs,
    required this.title,
    required this.district,
    required this.areaM2,
    required this.categoryId,
    this.gallery = const [],
    this.description,
  });

  final String id;
  final String imageUrl;
  final int priceUzs;
  final String title;
  final String district;
  final int areaM2;
  final String categoryId;

  /// Additional images for the detail view. By convention, the primary
  /// [imageUrl] is at index 0 when populated.
  final List<String> gallery;

  /// Short marketing copy shown on the detail screen.
  final String? description;

  /// Images to show in the detail gallery — falls back to [imageUrl]
  /// when no gallery is set.
  List<String> get galleryImages =>
      gallery.isNotEmpty ? gallery : <String>[imageUrl];
}

class MarketCategory {
  const MarketCategory({required this.id, required this.label});

  final String id;
  final String label;
}

const String kMarketCategoryAll = 'all';

const List<MarketCategory> marketCategories = [
  MarketCategory(id: kMarketCategoryAll, label: 'Barchasi'),
  MarketCategory(id: 'residential', label: 'Turar joy'),
  MarketCategory(id: 'nonresidential', label: 'Noturar'),
  MarketCategory(id: 'projects', label: 'Loyihalar'),
];
