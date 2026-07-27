import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';

enum ServiceId { kadastr3d, aiValuation, calculator, smetaPro }

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.accent,
    required this.layout,
  });

  final ServiceId id;
  final String title;
  final String subtitle;
  final String asset;
  final Color accent;
  final ServiceLayout layout;
}

enum ServiceLayout { square, wide }

class ServiceStrings {
  const ServiceStrings._();

  static String pageTitle(Locale l) => tr(l, 'services.model.services_title');

  static String kadastrTitle(Locale l) =>
      tr(l, 'services.model.service_kadastr.title');

  static String kadastrSubtitle(Locale l) =>
      tr(l, 'services.model.service_kadastr.subtitle');

  static String aiTitle(Locale l) => tr(l, 'services.model.service_ai.title');

  static String aiSubtitle(Locale l) =>
      tr(l, 'services.model.service_ai.subtitle');

  static String calculatorTitle(Locale l) =>
      tr(l, 'services.model.service_calc.title');

  static String calculatorSubtitle(Locale l) =>
      tr(l, 'services.model.service_calc.subtitle');

  static String smetaProTitle(Locale l) =>
      tr(l, 'services.model.service_smeta.title');

  static String smetaProSubtitle(Locale l) =>
      tr(l, 'services.model.service_smeta.subtitle');
}
