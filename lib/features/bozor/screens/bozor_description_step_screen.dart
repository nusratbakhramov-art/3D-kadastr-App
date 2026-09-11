/// "Bozor AI" sehrgarining tavsif qadami — `Описание`.
///
/// Maydonlar oltita variantda BIR XIL; farqi faqat tavsif sarlavhasida
/// ([PropertyTypeAddressX.descriptionLabel]).
///
/// Fayllar hozircha faqat LOKAL tanlanadi — yuklash endpoint'i yo'q. Yo'llar
/// qoralamada saqlanadi, yuborish keyingi ishda.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../panorama/screens/pano_tour_screen.dart';
import '../models/tour_link.dart';
import '../widgets/pano_source_sheet.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_field.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../bozor_routes.dart';
import '../data/bozor_draft_store.dart';
import '../models/bozor_draft.dart';
import '../widgets/media_upload_row.dart';
import 'bozor_contacts_step_screen.dart';

/// Bitta e'londagi rasm chegarasi. Dizaynda ko'rsatilmagan — ilovaning
/// boshqa yuklash oqimlaridagi bilan bir xil qilib olindi.
const int _maxPhotos = 20;

class BozorDescriptionStepScreen extends StatefulWidget {
  const BozorDescriptionStepScreen({super.key, required this.draft});

  final BozorDraft draft;

  @override
  State<BozorDescriptionStepScreen> createState() =>
      _BozorDescriptionStepScreenState();
}

class _BozorDescriptionStepScreenState
    extends State<BozorDescriptionStepScreen> {
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _title =
      TextEditingController(text: widget.draft.title);
  late final TextEditingController _text =
      TextEditingController(text: _d.text);
  late final TextEditingController _youtube =
      TextEditingController(text: _d.youtubeUrl);

  DescriptionDraft get _d => widget.draft.description;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTitle);
    _text.addListener(_onText);
    _youtube.addListener(_onYoutube);
  }

  @override
  void dispose() {
    _title.removeListener(_onTitle);
    _text.removeListener(_onText);
    _youtube.removeListener(_onYoutube);
    _title.dispose();
    _text.dispose();
    _youtube.dispose();
    super.dispose();
  }

  void _onTitle() =>
      setState(() => widget.draft.title = _title.text.trim());
  void _onText() => setState(() => _d.text = _text.text);
  void _onYoutube() => setState(() => _d.youtubeUrl = _youtube.text.trim());

  Future<void> _pick(List<String> into, {required bool multiple}) async {
    final l = Localizations.localeOf(context);
    final remaining = _maxPhotos - into.length;
    if (remaining <= 0) {
      AppToast.error(context, _S.tooMany(l, _maxPhotos));
      return;
    }
    final picked = multiple
        ? await _picker.pickMultiImage(limit: remaining)
        : [
            ?await _picker.pickImage(source: ImageSource.gallery),
          ];
    if (!mounted || picked.isEmpty) return;
    setState(() => into.addAll(picked.map((x) => x.path)));
  }

  /// 360° foto: SURATGA OLISH yoki galereyadan.
  ///
  /// Ikkala yo'l ham haqiqiy — foydalanuvchi joyida bo'lsa panoramani
  /// shu yerda oladi, boshqa ilovada yasagan bo'lsa yuklaydi.
  /// 360° ni SFERADA ochadi va turni tahrirlash imkonini beradi.
  ///
  /// Havolalar qoralamada LOKAL YO'L bilan yotadi — panoramalar hali
  /// yuklanmagan. Yuborishda `resolveTourLinks` ularni S3 kalitiga
  /// o'giradi.
  void _open360(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PanoTourScreen(
          panoramas: <TourPano>[
            for (final String p in _d.panoramas) TourPano(ref: p, file: p),
          ],
          links: _d.tourLinks,
          initialIndex: index,
          editable: true,
          onChanged: (List<TourLink> links) => setState(() {
            _d.tourLinks
              ..clear()
              ..addAll(links);
          }),
        ),
      ),
    );
  }

  Future<void> _add360() async {
    final l = Localizations.localeOf(context);
    if (_d.panoramas.length >= _maxPhotos) {
      AppToast.error(context, _S.tooMany(l, _maxPhotos));
      return;
    }
    final source = await showPanoSourceSheet(context);
    if (!mounted || source == null) return;

    switch (source) {
      case PanoSource.gallery:
        await _pick(_d.panoramas, multiple: false);
      case PanoSource.capture:
        final path = await openPanoCapture(context);
        if (!mounted || path == null) return;
        setState(() => _d.panoramas.add(path));
    }
  }

  Future<void> _openContacts() async {
    // Qoralamani fonda saqlaymiz: foydalanuvchi shu qadamda chiqib
    // ketsa "Mening e'lonlarim" dan aynan shu joydan davom etadi.
    // `await` QILINMAYDI — tarmoq navigatsiyani muzlatmasin.
    saveBozorDraftInBackground(widget.draft, WizardStep.contacts);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('contacts'),
        builder: (_) => BozorContactsStepScreen(draft: widget.draft),
      ),
    );
    if (mounted) setState(() {});
  }

  // Sarlavha ham majburiy: backendda `title` NOT NULL va lenta kartasi
  // shusiz bo'sh chiqadi.
  bool get _isComplete =>
      widget.draft.title.length >= 3 && _d.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final draft = widget.draft;
    final type = draft.type;

    if (type == null) {
      return Scaffold(backgroundColor: bg, body: const SizedBox());
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxContent = c.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: _S.title(l),
                        subtitle:
                            '${draft.stepNumber(WizardStep.description)}'
                            '/${draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: draft.stepCount,
                        activeIndex: draft.stepIndex(WizardStep.description),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          WizardField(
                            label: _S.titleLabel(l),
                            controller: _title,
                            placeholder: _S.titleHint(l),
                            maxLength: 255,
                            required: true,
                          ),
                          const SizedBox(height: 12),
                          WizardField(
                            label: type.descriptionLabel(l),
                            controller: _text,
                            placeholder: _S.textHint(l),
                            // Dizayndagi 132pt li quti ~5 qatorga to'g'ri
                            // keladi.
                            maxLines: 5,
                            required: true,
                          ),
                          const SizedBox(height: 12),
                          MediaUploadRow(
                            label: _S.addPlan(l),
                            iconAsset: 'assets/icons/upload-plan.svg',
                            paths: _d.planFiles,
                            onAdd: () =>
                                _pick(_d.planFiles, multiple: false),
                            onRemove: (i) =>
                                setState(() => _d.planFiles.removeAt(i)),
                          ),
                          const SizedBox(height: 12),
                          MediaUploadRow(
                            label: _S.addPhoto(l),
                            iconAsset: 'assets/icons/upload-photo.svg',
                            paths: _d.photos,
                            onAdd: () => _pick(_d.photos, multiple: true),
                            onRemove: (i) =>
                                setState(() => _d.photos.removeAt(i)),
                          ),
                          const SizedBox(height: 12),
                          MediaUploadRow(
                            label: _S.add360(l),
                            iconAsset: 'assets/icons/upload-360.svg',
                            paths: _d.panoramas,
                            onAdd: _add360,
                            onRemove: (i) =>
                                setState(() => _d.panoramas.removeAt(i)),
                            // 360° SFERADA ochiladi. Oddiy galereya uni
                            // cho'zilgan lenta qilib ko'rsatadi va
                            // panorama ekani bilinmaydi. Bir nechta
                            // bo'lsa — yurib bo'ladigan TUR, va egasi
                            // shu yerda o'tish tugmalarini qo'yadi.
                            onOpen: _open360,
                          ),
                          const SizedBox(height: 16),
                          WizardField(
                            label: _S.youtube(l),
                            controller: _youtube,
                            placeholder: _S.youtubeHint(l),
                            keyboardType: TextInputType.url,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: WizardNavBar(
                        onBack: () => Navigator.of(context).maybePop(),
                        continueLabel: tr(l, 'bozor.common.next'),
                        continueEnabled: _isComplete,
                        onContinue: _openContacts,
                        onBlockedTap: () => AppToast.error(
                          context,
                          tr(l, 'bozor.common.fill_required'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'bozor.desc.title');
  static String titleLabel(Locale l) => tr(l, 'bozor.desc.listing_title');
  static String titleHint(Locale l) => tr(l, 'bozor.desc.listing_title_hint');
  static String textHint(Locale l) => tr(l, 'bozor.desc.hint');
  static String addPlan(Locale l) => tr(l, 'bozor.desc.add_plan');
  static String addPhoto(Locale l) => tr(l, 'bozor.desc.add_photo');
  static String add360(Locale l) => tr(l, 'bozor.desc.add_360');
  static String youtube(Locale l) => tr(l, 'bozor.desc.youtube');
  static String youtubeHint(Locale l) => tr(l, 'bozor.desc.youtube_hint');
  static String tooMany(Locale l, int max) =>
      tr(l, 'bozor.desc.too_many').replaceAll('%d', '$max');
}
