/// One downloadable file attached to a marketplace listing (GLB, USDZ, OBJ…).
class MarketListingFile {
  const MarketListingFile({
    required this.id,
    required this.format,
    required this.fileSize,
  });

  final int id;
  final String format; // 'GLB', 'USDZ', etc.
  final int fileSize; // bytes
}

/// Saved camera angle / view inside a single 3D model.
class MarketListingScene {
  const MarketListingScene({
    required this.id,
    required this.name,
    this.previewUrl,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final String? previewUrl;
  final int sortOrder;
}

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
    this.isFree = false,
    this.scenes = const [],
    this.files = const [],
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

  /// True for the free / open download policy (TZ §6.5). When false, the
  /// "Sotib olish" lead form + payment gate apply.
  final bool isFree;

  /// Scenes (camera angles) saved inside this 3D model. Empty list means
  /// the model has only the default scene.
  final List<MarketListingScene> scenes;

  /// Downloadable file variants (GLB, USDZ, OBJ, etc.).
  final List<MarketListingFile> files;

  /// Images to show in the detail gallery — falls back to [imageUrl]
  /// when no gallery is set.
  List<String> get galleryImages =>
      gallery.isNotEmpty ? gallery : <String>[imageUrl];

  /// Numeric backend id (or `null` when this listing is mock-only).
  int? get backendId => int.tryParse(id);
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
