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
    this.floor,
    this.categoryLabel,
    this.gallery = const [],
    this.description,
    this.isFree = false,
    this.isOwned = false,
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

  /// Obyekt qavati (nullable — barcha e'lonlarda bo'lavermaydi). Filtr faqat
  /// qiymat mavjud bo'lganda qo'llanadi.
  final int? floor;

  final String? categoryLabel;

  /// Additional images for the detail view. By convention, the primary
  /// [imageUrl] is at index 0 when populated.
  final List<String> gallery;

  /// Short marketing copy shown on the detail screen.
  final String? description;

  /// True for the free / open download policy (TZ §6.5). When false, the
  /// "Sotib olish" lead form + payment gate apply.
  final bool isFree;

  /// True when the current (authenticated) user has purchased this paid model
  /// — i.e. a completed `marketplace_purchase` payment exists. Always false for
  /// free models and anonymous requests. Gates download / 3D viewer access.
  final bool isOwned;

  /// Scenes (camera angles) saved inside this 3D model. Empty list means
  /// the model has only the default scene.
  final List<MarketListingScene> scenes;

  /// Downloadable file variants (GLB, USDZ, OBJ, etc.).
  final List<MarketListingFile> files;

  /// Images to show in the detail gallery. Order: cover image first,
  /// then scene preview URLs. Empty entries are dropped.
  List<String> get galleryImages {
    if (gallery.isNotEmpty) return gallery;
    final urls = <String>[];
    if (imageUrl.isNotEmpty) urls.add(imageUrl);
    for (final s in scenes) {
      final u = s.previewUrl;
      if (u != null && u.isNotEmpty) urls.add(u);
    }
    return urls.isEmpty ? const [] : urls;
  }

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
