import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';

enum ServiceId {
  kadastr3d,
  aiValuation,
  calculator,
  smetaPro,
  bozorAi,
  taqiqCheck,
}

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.accent,
    required this.layout,
    this.glow,
    this.artScale = 1.0,
  });

  final ServiceId id;
  final String title;
  final String subtitle;
  final String asset;
  final Color accent;
  final ServiceLayout layout;

  /// Where the card's pool of coloured light sits. Null takes the default for
  /// the layout — see [ServiceGlow.forLayout] — which is what most cards want:
  /// the glow belongs behind the 3D object, and the object is in the same
  /// corner on every square card.
  final ServiceGlow? glow;

  /// Multiplies the artwork box. The cards share one size, but the artwork does
  /// not share one scale: a house fills its frame edge to edge, while the 3D
  /// kadastr badge is drawn small inside a lot of empty pixels and needs to be
  /// pushed up to read as the same size on the card.
  final double artScale;

  ServiceGlow get effectiveGlow => glow ?? ServiceGlow.forLayout(layout);
}

/// The ambient light a card's 3D object appears to cast on its own background.
///
/// Every value is a FRACTION of the card, never a pt size: the same card is
/// ~179×230 on an iPhone 17 Pro and ~158×202 on a Galaxy S23, and a glow
/// measured in points drifts off the object between the two.
@immutable
class ServiceGlow {
  const ServiceGlow({
    this.color,
    this.opacity = 1.0,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Square cards put the object in the bottom-right corner; the wide card puts
  /// it on the right, running nearly the full height.
  factory ServiceGlow.forLayout(ServiceLayout layout) =>
      layout == ServiceLayout.wide
      // A wide bloom rising from the BOTTOM EDGE, per the mockup: the card is
      // black at the top and saturated across its whole width at the bottom,
      // with the artwork sitting in that light rather than beside it.
      //
      // The centre is pushed just past the bottom edge (y > 1) so the card only
      // ever shows the top half of the ellipse — that is what makes the colour
      // strongest at the edge and fade upward, instead of peaking mid-card.
      ? const ServiceGlow(x: 0.50, y: 1.06, width: 1.25, height: 2.20)
      : const ServiceGlow(x: 0.50, y: 1.04, width: 1.70, height: 1.35);

  /// Null = the card's own [ServiceItem.accent].
  final Color? color;

  /// Scales the whole ramp. 1.0 is the tuned default; lower it for artwork
  /// that is already bright enough to light the card by itself.
  final double opacity;

  /// Centre of the light, as a fraction of card width / height. Follow the
  /// object: a glow centred on a card whose object sits right reads as a
  /// coloured card, not as light coming off the object.
  final double x;
  final double y;

  /// Size of the ellipse, as a fraction of card width / height.
  final double width;
  final double height;
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
