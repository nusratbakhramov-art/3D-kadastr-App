/// `GET /releases/latest` javobining mobil modeli.
///
/// Backend matnlarni SO'RALGAN TILDA yechib beradi (`lang=`), shuning uchun bu
/// yerda tarjima mantig'i yo'q — faqat tayyor satrlar. Keshdagi javob qaysi
/// tilda olingani [lang] da turadi: foydalanuvchi tilni almashtirsa kesh
/// yaroqsiz bo'ladi va qaytadan so'raladi.
library;

import 'package:flutter/foundation.dart';

@immutable
class AppRelease {
  const AppRelease({
    this.hasUpdate = false,
    this.required = false,
    this.platform,
    this.version,
    this.buildNumber,
    this.title = '',
    this.subtitle = '',
    this.description = '',
    this.imageUrl,
    this.storeUrl,
    this.lang = 'uz',
  });

  /// Yangilanish YO'Q holati — tarmoq xatosida ham shu ishlatiladi.
  static const AppRelease none = AppRelease();

  final bool hasUpdate;

  /// MAJBURIY yangilanish. Faqat backend aniq `true` qaytargandagina true
  /// bo'ladi — mijoz tomonda hech qachon o'ylab topilmaydi.
  final bool required;

  final String? platform;
  final String? version;
  final int? buildNumber;

  final String title;
  final String subtitle;
  final String description;
  final String? imageUrl;

  /// App Store / Play Store havolasi. Bo'sh bo'lsa "Yangilash" tugmasi
  /// do'kon ilovasini zaxira havola bilan ochadi.
  final String? storeUrl;

  final String lang;

  /// Bloklovchi ekran faqat shu shart bajarilganda ko'rsatiladi.
  bool get isBlocking => hasUpdate && required;

  /// Bekor qilinadigan taklif.
  bool get isOptional => hasUpdate && !required;

  /// Xuddi shu relizni ikki marta ko'rsatmaslik uchun barqaror kalit.
  String get key => '${platform ?? ''}:${version ?? ''}+${buildNumber ?? 0}';

  static String _str(Object? v) => v is String ? v : '';

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
    hasUpdate: json['has_update'] == true,
    required: json['required'] == true,
    platform: json['platform'] as String?,
    version: json['version'] as String?,
    buildNumber: (json['build_number'] as num?)?.toInt(),
    title: _str(json['title']),
    subtitle: _str(json['subtitle']),
    description: _str(json['description']),
    imageUrl: (json['image_url'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['image_url'] as String).trim(),
    storeUrl: (json['store_url'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['store_url'] as String).trim(),
    lang: (json['lang'] as String?) ?? 'uz',
  );

  Map<String, dynamic> toJson() => {
    'has_update': hasUpdate,
    'required': required,
    'platform': platform,
    'version': version,
    'build_number': buildNumber,
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'image_url': imageUrl,
    'store_url': storeUrl,
    'lang': lang,
  };
}
