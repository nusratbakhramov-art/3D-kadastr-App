class MarketListing {
  const MarketListing({
    required this.id,
    required this.imageUrl,
    required this.priceUzs,
    required this.title,
    required this.district,
    required this.areaM2,
    required this.categoryId,
  });

  final String id;
  final String imageUrl;
  final int priceUzs;
  final String title;
  final String district;
  final int areaM2;
  final String categoryId;
}

class MarketCategory {
  const MarketCategory({required this.id, required this.label});

  final String id;
  final String label;
}

const List<MarketCategory> marketCategories = [
  MarketCategory(id: 'all', label: 'Barchasi'),
  MarketCategory(id: 'residential', label: 'Turar joy'),
  MarketCategory(id: 'nonresidential', label: 'Noturar'),
  MarketCategory(id: 'projects', label: 'Loyihalar'),
];
