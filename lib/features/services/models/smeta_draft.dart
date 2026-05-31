/// Professional smeta — line-item editor draft.
///
/// Mirrors the shape backend's `EstimatePayload` accepts at
/// `POST /abc4/jobs`. Stays loose on text fields so users can fill the
/// minimum (works, district, sections + items) and skip the rest.
library;

import 'package:flutter/foundation.dart';

class SmetaHeader {
  SmetaHeader({
    this.regNumber = '1000',
    this.works = const ['Н9', 'Ж5'],
    this.flags = 'М',
    this.district = '1',
  });

  String regNumber;
  List<String> works;
  String flags;
  String district;

  Map<String, dynamic> toJson() => {
        'regNumber': regNumber,
        'works': works,
        'flags': flags,
        'district': district,
      };
}

class SmetaTexts {
  SmetaTexts({
    this.constructionName = '',
    this.objectName = '',
    this.estimateName = '',
    this.priceLevel = '',
  });

  String constructionName;
  String objectName;
  String estimateName;
  String priceLevel;

  Map<String, dynamic> toJson() => {
        'constructionName': constructionName,
        'objectName': objectName,
        'estimateName': estimateName,
        'priceLevel': priceLevel,
      };
}

class SmetaItem {
  SmetaItem({
    required this.code,
    required this.name,
    required this.unit,
    required this.quantity,
  });

  /// e.g. "Е604-1-1"
  String code;
  String name;
  String unit;
  double quantity;

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'unit': unit,
        'quantity': quantity,
      };
}

class SmetaSection {
  SmetaSection({
    required this.code,
    required this.name,
    List<SmetaItem>? items,
  }) : items = items ?? <SmetaItem>[];

  String code;
  String name;
  final List<SmetaItem> items;

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// Top-level draft the user assembles in the editor.
class SmetaDraft extends ChangeNotifier {
  SmetaDraft({
    SmetaHeader? header,
    SmetaTexts? texts,
    List<SmetaSection>? sections,
  })  : header = header ?? SmetaHeader(),
        texts = texts ?? SmetaTexts(),
        sections = sections ?? <SmetaSection>[];

  final SmetaHeader header;
  final SmetaTexts texts;
  final List<SmetaSection> sections;

  int get itemCount =>
      sections.fold(0, (n, s) => n + s.items.length);

  void addSection(SmetaSection s) {
    sections.add(s);
    notifyListeners();
  }

  void removeSection(int i) {
    sections.removeAt(i);
    notifyListeners();
  }

  void addItem(int sectionIndex, SmetaItem item) {
    sections[sectionIndex].items.add(item);
    notifyListeners();
  }

  void removeItem(int sectionIndex, int itemIndex) {
    sections[sectionIndex].items.removeAt(itemIndex);
    notifyListeners();
  }

  Map<String, dynamic> toEstimatePayload() => {
        'header': header.toJson(),
        'texts': texts.toJson(),
        'sections': sections.map((s) => s.toJson()).toList(),
      };
}

/// Curated СНиР code returned by `/abc4/catalog/codes`.
class CatalogCode {
  const CatalogCode({
    required this.code,
    required this.name,
    required this.unit,
    required this.book,
  });

  final String code;
  final String name;
  final String unit;
  final String book;

  factory CatalogCode.fromJson(Map<String, dynamic> j) => CatalogCode(
        code: (j['code'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        unit: (j['unit'] ?? '') as String,
        book: (j['book'] ?? '') as String,
      );
}

/// СНиР book / chapter (e.g. E01 "Земляные работы"). Used to filter the
/// catalog search.
class CatalogBook {
  const CatalogBook({
    required this.file,
    required this.label,
    required this.letter,
    required this.count,
  });

  /// Adapter's file id (e.g. `00-UZ-E01`) — what catalog_search takes as
  /// the `book` query param.
  final String file;

  /// Human label (e.g. "Земляные работы").
  final String label;

  /// "Е" or "Ц".
  final String letter;

  /// Number of codes in this book (for the picker UI).
  final int count;

  factory CatalogBook.fromJson(Map<String, dynamic> j) => CatalogBook(
        file: (j['file'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        letter: (j['letter'] ?? '') as String,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// Snapshot of an `/abc4/jobs/{id}` poll. Loose shape because the driver
/// result_payload varies — anything beyond `id` + `state` is best-effort.
class SmetaJobSnapshot {
  const SmetaJobSnapshot({
    required this.id,
    required this.state,
    this.result,
    this.records,
  });

  final String id;
  final String state; // queued | running | done | unknown
  final Map<String, dynamic>? result;
  final List<dynamic>? records;

  bool get isTerminal => state == 'done' || state == 'unknown';

  factory SmetaJobSnapshot.fromJson(Map<String, dynamic> j) => SmetaJobSnapshot(
        id: (j['id'] ?? '') as String,
        state: (j['state'] ?? 'unknown') as String,
        result: j['result'] is Map<String, dynamic>
            ? j['result'] as Map<String, dynamic>
            : null,
        records: j['records'] is List ? j['records'] as List<dynamic> : null,
      );
}
