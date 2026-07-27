/// AI Baholash wizard — review/preview step (step 6 of 6).
///
/// The last screen before the valuation request fires. Shows the uploaded
/// photos/docs as tappable thumbnails plus a summary of every entered field,
/// each section editable via a pencil that jumps back to the right step
/// (`Navigator.popUntil` on the named routes set up across the flow). The
/// "Hisoblash" CTA pushes the unchanged status screen, which submits the bundle.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/file_preview_gallery.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/wizard_review_section.dart';
import 'ai_target_price_screen.dart';

class AiReviewScreen extends StatefulWidget {
  const AiReviewScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

  @override
  State<AiReviewScreen> createState() => _AiReviewScreenState();
}

class _AiReviewScreenState extends State<AiReviewScreen> {
  // Jump back to a step to edit it. popUntil removes the screens above the
  // target (incl. this review), so re-traversing forward rebuilds them from the
  // shared bundle — no duplicate routes. NOTE: editing Kadastr re-enters from
  // the root (the cadastre step rebuilds the bundle), since it's the property's
  // identity; the other steps mutate the shared bundle, so their data survives.
  void _edit(BuildContext context, String routeName) {
    HapticFeedback.lightImpact();
    Navigator.of(context).popUntil(ModalRoute.withName(routeName));
  }

  void _submit(BuildContext context) {
    HapticFeedback.lightImpact();
    // Natijadan OLDIN maqsadli narxni so'raymiz; narx ekrani natija ekraniga
    // (AiStatusScreen) o'tadi va u yerda ariza yuboriladi.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/target-price'),
        builder: (_) => AiTargetPriceScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final bundle = widget.bundle;
    final k = bundle.kadastr;
    final loc = bundle.location;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ServiceAppBar(
                    title: _S.title(l),
                    subtitle: _S.subtitle(l),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 8, activeIndex: 6),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      // ── Uploaded files ──
                      _UploadReviewCard(
                        title: _S.photos(l),
                        paths: bundle.imagePaths,
                        onEdit: () => _edit(context, 'ai/intake'),
                      ),
                      _UploadReviewCard(
                        title: _S.docs(l),
                        paths: bundle.kadastrPaths,
                        onEdit: () => _edit(context, 'ai/intake'),
                      ),
                      if (bundle.passportPaths.isNotEmpty)
                        _UploadReviewCard(
                          title: _S.passport(l),
                          paths: bundle.passportPaths,
                          onEdit: () => _edit(context, 'ai/intake'),
                        ),
                      // ── Entered data ──
                      WizardReviewSection(
                        title: _S.kadastr(l),
                        onEdit: () => _edit(context, 'ai/cadastre'),
                        rows: [
                          (_S.cadastreNumber(l), k.cadastreNumber),
                          (_S.address(l), k.address ?? ''),
                          (_S.area(l), _fmtArea(bundle.areaM2 ?? k.totalArea)),
                          (_S.value(l), _fmtUzs(k.cadastreValue, l)),
                        ],
                      ),
                      WizardReviewSection(
                        title: _S.client(l),
                        onEdit: () => _edit(context, 'ai/client'),
                        rows: [
                          (_S.name(l), bundle.client?.name ?? ''),
                          (_S.stir(l), bundle.client?.stir ?? ''),
                          (_S.phone(l), bundle.client?.phone ?? ''),
                          (_S.email(l), bundle.client?.email ?? ''),
                        ],
                      ),
                      WizardReviewSection(
                        title: _S.location(l),
                        onEdit: () => _edit(context, 'ai/location'),
                        rows: [
                          (_S.address(l), loc?.addressText ?? ''),
                          (
                            _S.coords(l),
                            loc == null
                                ? ''
                                : '${loc.lat.toStringAsFixed(5)}, '
                                      '${loc.lng.toStringAsFixed(5)}',
                          ),
                        ],
                      ),
                      WizardReviewSection(
                        title: _S.purpose(l),
                        onEdit: () => _edit(context, 'ai/purpose'),
                        chips: [bundle.purpose.label(l)],
                      ),
                      WizardReviewSection(
                        title: _S.floorRooms(l),
                        onEdit: () => _edit(context, 'ai/intake'),
                        rows: [
                          (
                            _S.floor(l),
                            (bundle.floor == null || bundle.totalFloors == null)
                                ? ''
                                : '${bundle.floor} / ${bundle.totalFloors}',
                          ),
                        ],
                        chips: [
                          for (final r in bundle.rooms)
                            r.count > 1
                                ? '${r.kind.label(l)} ×${r.count}'
                                : r.kind.label(l),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _S.calculate(l),
                    enabled: true,
                    onTap: () => _submit(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtArea(double? v) {
    if (v == null) return '';
    final s = v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
    return '$s m²';
  }

  static String _fmtUzs(double? v, Locale l) {
    if (v == null) return '';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} ${_S.billion(l)}';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)} ${_S.million(l)}';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }
}

// ── One upload category: title + edit pencil + a row of tappable thumbnails ──
class _UploadReviewCard extends StatelessWidget {
  const _UploadReviewCard({
    required this.title,
    required this.paths,
    required this.onEdit,
  });

  final String title;
  final List<String> paths;
  final VoidCallback onEdit;

  static const Set<String> _imageExts = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'gif',
    'bmp',
  };

  static String _ext(String p) {
    final n = p.toLowerCase();
    final dot = n.lastIndexOf('.');
    return dot >= 0 ? n.substring(dot + 1) : '';
  }

  static bool _isImage(String p) => _imageExts.contains(_ext(p));

  void _openImage(BuildContext context, List<String> images, String path) {
    final i = images.indexOf(path);
    if (i < 0) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FilePreviewGallery(paths: images, initialIndex: i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    final chipBg = isDark ? const Color(0xFF14181A) : const Color(0xFFF1F2F4);

    final images = paths.where(_isImage).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  paths.isEmpty ? title : '$title · ${paths.length}',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: titleColor,
                  ),
                ),
              ),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 19,
                    color: AppColors.splashGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (paths.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text(
                _S.empty(l),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 13.5,
                  color: muted,
                ),
              ),
            )
          else
            SizedBox(
              height: 66,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 8),
                itemCount: paths.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final path = paths[i];
                  if (_isImage(path)) {
                    return GestureDetector(
                      onTap: () => _openImage(context, images, path),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(path),
                          width: 66,
                          height: 66,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 66,
                            height: 66,
                            color: chipBg,
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 22,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 24,
                          color: muted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _ext(path).toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 9.5,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Localized strings ─────────────────────────────────────────────────
class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'services.ai.review.title');

  static String subtitle(Locale l) => tr(l, 'services.ai.review.subtitle');

  static String photos(Locale l) => tr(l, 'services.ai.review.photos');

  static String docs(Locale l) => tr(l, 'services.ai.review.docs');

  static String passport(Locale l) => tr(l, 'services.ai.review.passport');

  static String kadastr(Locale l) => tr(l, 'services.ai.review.kadastr');

  static String client(Locale l) => tr(l, 'services.ai.review.client');

  static String location(Locale l) => tr(l, 'services.ai.review.location');

  static String purpose(Locale l) => tr(l, 'services.ai.review.purpose');

  static String floorRooms(Locale l) => tr(l, 'services.ai.review.floor_rooms');

  static String cadastreNumber(Locale l) =>
      tr(l, 'services.ai.review.cadastre_number');

  static String address(Locale l) => tr(l, 'services.ai.review.address');

  static String area(Locale l) => tr(l, 'services.ai.review.area');

  static String value(Locale l) => tr(l, 'services.ai.review.value');

  static String name(Locale l) => tr(l, 'services.ai.review.name');

  static String stir(Locale l) => tr(l, 'services.ai.review.stir');

  static String phone(Locale l) => tr(l, 'services.ai.review.phone');

  static String email(Locale l) => tr(l, 'services.ai.review.email');

  static String coords(Locale l) => tr(l, 'services.ai.review.coords');

  static String floor(Locale l) => tr(l, 'services.ai.review.floor');

  static String calculate(Locale l) => tr(l, 'services.ai.review.calculate');

  static String empty(Locale l) => tr(l, 'services.ai.review.empty');

  static String million(Locale l) => tr(l, 'services.ai.review.million');

  static String billion(Locale l) => tr(l, 'services.ai.review.billion');
}
