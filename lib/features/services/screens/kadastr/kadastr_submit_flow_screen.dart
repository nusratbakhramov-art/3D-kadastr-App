/// Kadastr combined calculator — submit coordinator.
///
/// Invoked from the estimate's "Ariza topshirish". It does NOT add a host
/// screen: each form is pushed over the estimate (so back returns to the
/// estimate, not a progress screen). One order per selected service.
///
///   - Arxitektura / Dizayn → their full TZ wizard (collects its own customer).
///     The first wizard's customer is reused for the simple services, so no
///     separate contact step is needed when a wizard is selected.
///   - Kadastr / 3D / Baholash / Ta'mirlash / Yuridik → already specified by
///     area + type; submitted as calculator orders with the contact attached.
///   - If NO wizard is selected, a single contact form is shown first.
/// After everything is collected, a brief loading overlay covers the batch
/// submit, then a combined success screen.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../auth/widgets/login_required_sheet.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_architecture_order_service.dart';
import '../../api_calculator_order_service.dart';
import '../../api_design_order_service.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/architecture_order_draft.dart';
import '../../models/calculator_draft.dart';
import '../../models/design_order_draft.dart';
import '../../models/kadastr_applicant.dart';
import '../../models/kadastr_estimate.dart';
import '../calculator/arxitektura_tz_wizard_screen.dart';
import '../calculator/dizayn_tz_wizard_screen.dart';
import 'kadastr_lead_form_screen.dart';

bool _isWizard(CalculatorCategory c) =>
    c == CalculatorCategory.arxitektura || c == CalculatorCategory.dizayn;

/// Runs the per-service submission. Anchored to [context] (the estimate
/// screen), which stays the base route the wizards are pushed over.
Future<void> runKadastrSubmit(
  BuildContext context, {
  required double areaM2,
  required List<CalculatorCategory> categories,
  required List<KadastrServiceEstimate> estimates,
  required int totalUzs,
  CalculatorServiceChoice? choice,
}) async {
  final l = Localizations.localeOf(context);
  if (!await ensureLoggedIn(context)) return;
  final token = (await const AuthStorage().loadSession()).token;
  if (token == null || token.isEmpty) return;
  if (!context.mounted) return;

  final wizards = categories.where(_isWizard).toList(growable: false);
  final simples =
      categories.where((c) => !_isWizard(c)).toList(growable: false);

  SharedApplicant? applicant;
  final archDrafts = <ArchitectureOrderDraft>[];
  final dizDrafts = <DizaynOrderDraft>[];

  if (wizards.isNotEmpty) {
    // Each wizard collects its own customer; reuse the first one downstream.
    for (final w in wizards) {
      if (!context.mounted) return;
      if (w == CalculatorCategory.arxitektura) {
        final price = _priceFor(w, areaM2, choice, l);
        final draft = await Navigator.of(context).push<ArchitectureOrderDraft>(
          MaterialPageRoute(
            builder: (ctx) => ArxitekturaTzWizardScreen(
              initialDraft: _seedArch(applicant, choice, areaM2, price),
              onSubmit: (d) => Navigator.of(ctx).pop(d),
            ),
          ),
        );
        if (draft == null) return; // backed out → return to the estimate
        archDrafts.add(draft);
        applicant ??= _applicantFromArch(draft);
      } else {
        final price = _priceFor(w, areaM2, choice, l);
        final draft = await Navigator.of(context).push<DizaynOrderDraft>(
          MaterialPageRoute(
            builder: (ctx) => DizaynTzWizardScreen(
              initialDraft: _seedDizayn(applicant, areaM2, price),
              onSubmit: (d) => Navigator.of(ctx).pop(d),
            ),
          ),
        );
        if (draft == null) return;
        dizDrafts.add(draft);
        applicant ??= _applicantFromDiz(draft);
      }
    }
  } else {
    // Wizard-less selection (e.g. Kadastr only) → one shared contact form.
    if (!context.mounted) return;
    applicant = await Navigator.of(context).push<SharedApplicant>(
      MaterialPageRoute(
        builder: (_) => KadastrLeadFormScreen(
          areaM2: areaM2,
          estimates: estimates,
          totalUzs: totalUzs,
        ),
      ),
    );
    if (applicant == null) return;
  }

  if (!context.mounted) return;
  // Batch submit under a brief, non-dismissible loading overlay.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: AppColors.splashGreen),
    ),
  );

  var created = 0;
  for (final d in archDrafts) {
    try {
      await ArchitectureOrderApiService().submit(draft: d, token: token);
      created++;
    } catch (_) {/* counted below as not created */}
  }
  for (final d in dizDrafts) {
    try {
      await DesignOrderApiService().submit(draft: d, token: token);
      created++;
    } catch (_) {}
  }
  for (final s in simples) {
    try {
      final est = estimateForCategory(
        category: s,
        areaM2: areaM2,
        pricing: calculatorPricingNotifier.value,
        locale: l,
        choice: choice,
      );
      await CalculatorOrderApiService().submit(
        result: _withContact(est.result, applicant!, l),
        token: token,
      );
      created++;
    } catch (_) {}
  }

  if (!context.mounted) return;
  Navigator.of(context).pop(); // dismiss the loading overlay
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => KadastrSubmitSuccessScreen(created: created),
    ),
  );
}

int _priceFor(
  CalculatorCategory c,
  double areaM2,
  CalculatorServiceChoice? choice,
  Locale l,
) =>
    estimateForCategory(
      category: c,
      areaM2: areaM2,
      pricing: calculatorPricingNotifier.value,
      locale: l,
      choice: choice,
    ).result.totalUzs;

/// Map the calculator object type → the architecture order's object +
/// construction type (same mapping the single Arxitektura form uses).
(ArchObjectType, ConstructionType) _archType(CalculatorServiceChoice? choice) =>
    switch (choice?.arxitektura) {
      ArxitekturaObject.yakkaSmall =>
        (ArchObjectType.yakkaSmall, ConstructionType.yangi),
      ArxitekturaObject.yakkaLarge =>
        (ArchObjectType.yakkaLarge, ConstructionType.yangi),
      ArxitekturaObject.kopQavatli =>
        (ArchObjectType.kopQavatli, ConstructionType.yangi),
      ArxitekturaObject.jamoat => (ArchObjectType.ofis, ConstructionType.yangi),
      ArxitekturaObject.sanoat =>
        (ArchObjectType.sanoat, ConstructionType.yangi),
      ArxitekturaObject.rekonstruksiya =>
        (ArchObjectType.yakkaSmall, ConstructionType.rekonstruksiya),
      null => (ArchObjectType.yakkaSmall, ConstructionType.yangi),
    };

ArchitectureOrderDraft _seedArch(
  SharedApplicant? a,
  CalculatorServiceChoice? choice,
  double areaM2,
  int priceUzs,
) {
  final (obj, con) = _archType(choice);
  final d = ArchitectureOrderDraft()
    ..totalAreaSqm = areaM2
    ..objectType = obj
    ..constructionType = con
    ..estimatedPriceUzs = priceUzs;
  // Only seed the customer for a *second* wizard (the first prefills itself
  // from the user's last application).
  if (a != null) {
    d
      ..customerName = a.name
      ..phone = a.phone
      ..address = a.address;
  }
  return d;
}

DizaynOrderDraft _seedDizayn(SharedApplicant? a, double areaM2, int priceUzs) {
  final d = DizaynOrderDraft()
    ..designAreaSqm = areaM2
    ..interiorAreaSqm = areaM2
    ..estimatedPriceUzs = priceUzs;
  if (a != null) {
    d
      ..customerName = a.name
      ..phone = a.phone
      ..address = a.address;
  }
  return d;
}

SharedApplicant _applicantFromArch(ArchitectureOrderDraft d) => SharedApplicant(
      name: d.customerName,
      phone: d.phone,
      address: d.address,
    );

SharedApplicant _applicantFromDiz(DizaynOrderDraft d) => SharedApplicant(
      name: d.customerName,
      phone: d.phone,
      address: d.address,
    );

/// Embed the shared contact into a calculator-order result so the admin sees
/// who applied (the simple services have no customer screen).
CalculatorResult _withContact(
  CalculatorResult r,
  SharedApplicant a,
  Locale l,
) =>
    CalculatorResult(
      categoryTitle: r.categoryTitle,
      category: r.category,
      totalUzs: r.totalUzs,
      note: r.note,
      lines: [
        ...r.lines,
        CalculatorLine(tr(l, 'services.kadastr.submit.customer'), a.name),
        CalculatorLine(tr(l, 'services.kadastr.phone'), a.fullPhone),
        if (a.address.isNotEmpty)
          CalculatorLine(tr(l, 'services.kadastr.address'), a.address),
      ],
    );

class KadastrSubmitSuccessScreen extends StatelessWidget {
  const KadastrSubmitSuccessScreen({super.key, required this.created});

  final int created;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final ok = created > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      ok
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 72,
                      color: ok ? AppColors.splashGreen : const Color(0xFFE5484D),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ok
                          ? tr(l, 'services.kadastr.submit.done_title')
                          : tr(l, 'services.kadastr.submit.fail_title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      ok
                          ? tr(l, 'services.kadastr.submit.done_body')
                              .replaceAll(r'$n', '$created')
                          : tr(l, 'services.kadastr.submit.fail_body'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 14,
                        height: 1.4,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ListingCtaButton(
                        label: tr(l, 'services.kadastr.submit.finish'),
                        enabled: true,
                        onTap: () =>
                            Navigator.of(context).popUntil((r) => r.isFirst),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

