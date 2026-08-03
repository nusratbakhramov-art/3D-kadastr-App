/// Kadastr combined calculator — quick (taxminiy) estimate per selected service.
///
/// The Kadastr flow collects only the property AREA up front, then lets the
/// user multi-select services. Each service's precise price needs an object
/// type (yakka / jamoat / tijorat …) that we don't ask here, so we compute an
/// INDICATIVE price using a sensible default type per service. The exact type
/// is settled later by the operator after the lead form is submitted.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import 'calculator_draft.dart';
import 'calculator_pricing.dart';

/// One selected service's indicative estimate.
class KadastrServiceEstimate {
  const KadastrServiceEstimate({
    required this.category,
    required this.result,
    this.isQuote = false,
  });

  final CalculatorCategory category;

  /// Computed breakdown. For [isQuote] services the total is 0 and the price
  /// is shown as "by agreement" instead of a number.
  final CalculatorResult result;

  /// Price-on-request service (Yuridik) — has no area-based price, so it's
  /// excluded from the numeric combined total.
  final bool isQuote;

  /// UZS contributed to the combined total (0 for quote-only services).
  int get totalUzs => isQuote ? 0 : result.totalUzs;
}

/// The object type chosen for each price-sensitive service, collected in the
/// per-service type steps that run after the multi-select. Services not listed
/// here don't price by type: Dizayn is area-only, Yuridik is quote-only.
///
/// Mutable so the type-step wizard can fill it in step by step.
class CalculatorServiceChoice {
  CalculatorServiceChoice({
    this.arxitektura,
    this.kadastr,
    this.kadastr3d,
    this.baholash,
    this.tamirlash,
  });

  ArxitekturaObject? arxitektura;
  KadastrObjectType? kadastr;
  KadastrObjectType? kadastr3d;
  BaholashObject? baholash;

  /// Ta'mirlash price depends on the service type (repair vs build); the
  /// object type and location are display-only, so we don't collect them.
  TamirlashServiceType? tamirlash;
}

/// Whether this service needs an object-type step before its price is exact.
/// Dizayn (area-only) and Yuridik (quote) don't.
bool categoryNeedsTypeStep(CalculatorCategory category) => switch (category) {
  CalculatorCategory.arxitektura ||
  CalculatorCategory.kadastr ||
  CalculatorCategory.kadastr3d ||
  CalculatorCategory.baholash ||
  CalculatorCategory.tamirlash => true,
  CalculatorCategory.dizayn ||
  CalculatorCategory.buxgalteriya ||
  CalculatorCategory.yuridik => false,
};

/// Indicative estimate for a service. When [choice] carries the user's picked
/// type for this service, the price is exact; otherwise a sensible default type
/// is used (e.g. the running total before the type steps are filled in).
KadastrServiceEstimate estimateForCategory({
  required CalculatorCategory category,
  required double areaM2,
  required CalculatorPricing pricing,
  required Locale locale,
  CalculatorServiceChoice? choice,
}) {
  switch (category) {
    case CalculatorCategory.arxitektura:
      return KadastrServiceEstimate(
        category: category,
        result: computeArxitektura(
          objectType: choice?.arxitektura ?? ArxitekturaObject.yakkaSmall,
          areaM2: areaM2,
          pricing: pricing,
          locale: locale,
        ),
      );
    case CalculatorCategory.kadastr:
      return KadastrServiceEstimate(
        category: category,
        result: computeKadastr(
          objectType: choice?.kadastr ?? KadastrObjectType.yakka,
          areaM2: areaM2,
          is3d: false,
          pricing: pricing,
          locale: locale,
        ),
      );
    case CalculatorCategory.kadastr3d:
      return KadastrServiceEstimate(
        category: category,
        result: computeKadastr(
          objectType: choice?.kadastr3d ?? KadastrObjectType.yakka,
          areaM2: areaM2,
          is3d: true,
          pricing: pricing,
          locale: locale,
        ),
      );
    case CalculatorCategory.baholash:
      return KadastrServiceEstimate(
        category: category,
        result: computeBaholash(
          objectType: choice?.baholash ?? BaholashObject.uyJoy,
          areaM2: areaM2,
          pricing: pricing,
          locale: locale,
        ),
      );
    case CalculatorCategory.dizayn:
      return KadastrServiceEstimate(
        category: category,
        result: computeDizayn(
          objectType: DizaynObjectType.turar,
          style: DizaynStyle.minimalizm,
          areaM2: areaM2,
          pricing: pricing,
          locale: locale,
        ),
      );
    case CalculatorCategory.tamirlash:
      return KadastrServiceEstimate(
        category: category,
        result: computeTamirlash(
          objectType: TamirlashObjectType.turar,
          location: TamirlashLocation.toshkentShahar,
          serviceType: choice?.tamirlash ?? TamirlashServiceType.tamir,
          areaM2: areaM2,
          pricing: pricing,
          locale: locale,
        ),
      );
    case CalculatorCategory.buxgalteriya:
    case CalculatorCategory.yuridik:
      // No area-based price — settled individually with the client.
      return KadastrServiceEstimate(
        category: category,
        isQuote: true,
        result: CalculatorResult(
          categoryTitle: category.title(locale),
          category: category.name,
          totalUzs: 0,
          note: kadastrQuoteLabel(locale),
          lines: const [],
        ),
      );
  }
}

/// Sum of the numeric estimates (quote-only services contribute 0).
int kadastrCombinedTotalUzs(Iterable<KadastrServiceEstimate> items) =>
    items.fold(0, (sum, e) => sum + e.totalUzs);

String kadastrQuoteLabel(Locale l) => tr(l, 'services.model.kadastr_quote');
