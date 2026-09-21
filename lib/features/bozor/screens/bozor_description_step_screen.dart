/// "Bozor AI" sehrgarining tavsif qadami — `Описание`.
///
/// Maydonlar oltita variantda BIR XIL; farqi faqat tavsif sarlavhasida
/// ([PropertyTypeAddressX.descriptionLabel]).
///
/// Fayllar hozircha faqat LOKAL tanlanadi — yuklash endpoint'i yo'q. Yo'llar
/// qoralamada saqlanadi, yuborish keyingi ishda.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../panorama/screens/pano_tour_screen.dart';
import '../models/tour_link.dart';
import '../../panorama/data/pano_api.dart';
import '../../panorama/data/pano_capture_channel.dart';
import '../../panorama/screens/pano_capture_flow.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_field.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../bozor_routes.dart';
import '../data/bozor_draft_store.dart';
import '../data/pano_job_watcher.dart';
import '../data/tour_native.dart';
import '../widgets/pano_rooms_sheet.dart';
import '../../services/widgets/room_picker_sheet.dart';
import '../models/bozor_draft.dart';
import '../widgets/media_upload_row.dart';
import 'bozor_contacts_step_screen.dart';

/// Bitta e'londagi rasm chegarasi. Dizaynda ko'rsatilmagan — ilovaning
/// boshqa yuklash oqimlaridagi bilan bir xil qilib olindi.
const int _maxPhotos = 20;

class BozorDescriptionStepScreen extends StatefulWidget {
  const BozorDescriptionStepScreen({
    super.key,
    required this.draft,
    this.openCapture = openPanoCapture,
  });

  final BozorDraft draft;

  /// Capture chegarasi — testlarda nativ kamera va yuklashni almashtirish uchun.
  final PanoCaptureOpener openCapture;

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

  // Capture availability must not hide existing rooms or choose the viewer.
  PanoCaptureMode? _captureMode;
  bool _nativePanoViewer = false;

  final PanoJobWatcher _watcher = PanoJobWatcher.instance;

  void _onPanoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _probe360();
    // Fonda tikilayotgan panoramalar — tayyor bo'lganda qator o'zi
    // yangilanishi uchun kuzatuvchiga ulanamiz.
    _watcher
      ..addListener(_onPanoChanged)
      ..watch(widget.draft);
    _title.addListener(_onTitle);
    _text.addListener(_onText);
    _youtube.addListener(_onYoutube);
  }

  @override
  void dispose() {
    // ⚠️ Kuzatuvchi TO'XTATILMAYDI: u ilova bo'yicha yagona va sehrgarning
    // boshqa qadamlari ham unga tayanadi. Faqat tinglashni bekor qilamiz.
    _watcher.removeListener(_onPanoChanged);
    _title.removeListener(_onTitle);
    _text.removeListener(_onText);
    _youtube.removeListener(_onYoutube);
    _title.dispose();
    _text.dispose();
    _youtube.dispose();
    super.dispose();
  }

  Future<void> _probe360() async {
    final mode = await PanoCaptureChannel.preferredCaptureMode();
    final viewer = await PanoCaptureChannel.isViewerSupported();
    if (mounted) {
      setState(() {
        _captureMode = mode;
        _nativePanoViewer = viewer;
      });
    }
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

  /// 360° ni SFERADA ochadi va turni tahrirlash imkonini beradi.
  ///
  /// Havolalar S3 KALITI bilan yotadi — tayyor panorama yuklangan va
  /// sehrgarga tayyor kaliti bilan qaytgan. `resolveTourLinks` shu sababli
  /// ayniyat bo'ladi (`uploaded[ref] ?? ref`), lekin u baribir chaqiriladi:
  /// o'chirilgan panoramaga qolib ketgan havolani filtrlaydi.
  /// Eskiz bosilganda: tayyorni sferada ochadi, kutilayotgani haqida
  /// aytadi, yiqilganini qayta urinishga taklif qiladi.
  void _openPano(int index) {
    final l = Localizations.localeOf(context);
    final ref = _d.panoramas[index];
    if (_d.localPanoramas.containsKey(ref)) {
      unawaited(_resumeLocal(ref));
      return;
    }
    final p = _d.pendingPanoramas[ref];
    if (p == null) {
      _open360(index);
      return;
    }
    if (!p.failed) {
      AppToast.success(context, tr(l, 'bozor.pano.flow.stitching'));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(l, 'bozor.pano.flow.failed')),
        content: Text(p.error ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(l, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(_retryPano(ref));
            },
            child: Text(tr(l, 'bozor.pano.flow.retry')),
          ),
        ],
      ),
    );
  }

  /// Turni ochadi — iOS'da NATIV (SceneKit, Uy360 `TourViewerView`), aks
  /// holda Dart `PanoTourScreen` (zaxira: Android / eski qurilma).
  ///
  /// Nativ tur «Yangi xona — hozir tushirish» amalini qaytarishi mumkin: u
  /// paytda tur yopilgan bo'ladi, shu yerda capture → tikish → yuklash
  /// oqimi yuritiladi, havola ikki tomonlama qo'shiladi va tur YANGI xonada
  /// qayta ochiladi (`mergeNewRoomLinks`). Bekor qilinsa — foydalanuvchi
  /// turgan xonada qayta ochiladi.
  Future<void> _open360(int index) async {
    final l = Localizations.localeOf(context);
    // ⚠️ FAQAT TAYYORLARI. Kutilayotgan panoramaning tasviri hali yo'q —
    // uni turga qo'shsak ekran bo'sh sferada ochilardi. Tur baribir
    // hammasi tayyor bo'lgach quriladi (mahsulot qarori), shuning uchun
    // bu yerda faqat ogohlantiramiz.
    final ready = <String>[
      for (final String p in _d.panoramas)
        if (!_d.isPending(p)) p,
    ];
    if (ready.isEmpty) return;
    if (_d.pendingPanoramas.isNotEmpty) {
      AppToast.success(context, tr(l, 'bozor.pano.tour.wait'));
    }
    if (_nativePanoViewer) {
      await _openNativeTour(ready, startKey: _d.panoramas[index]);
      return;
    }
    final start = ready.indexOf(_d.panoramas[index]);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PanoTourScreen(
          panoramas: <TourPano>[
            // Panoramalar serverda — lokal fayl emas, URL bilan ochiladi.
            for (final String p in ready)
              TourPano(ref: p, url: _d.panoramaUrls[p] ?? p),
          ],
          links: _d.tourLinks,
          initialIndex: start < 0 ? 0 : start,
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

  /// Xona nomi: foydalanuvchi bergani (`panoramaNames`), bo'lmasa «Xona N».
  String _roomName(Locale l, String key) =>
      _d.roomName(key) ??
      tr(
        l,
        'bozor.pano.tour.room_n',
      ).replaceFirst('%d', '${_d.panoramas.indexOf(key) + 1}');

  Future<void> _openNativeTour(
    List<String> ready, {
    required String startKey,
  }) async {
    var start = startKey;
    while (mounted) {
      final l = Localizations.localeOf(context);
      final res = await PanoCaptureChannel.tour(
        context,
        panoramas: <PanoTourRoom>[
          for (final String p in ready)
            PanoTourRoom(
              key: p,
              name: _roomName(l, p),
              url: _d.panoramaUrls[p] ?? p,
            ),
        ],
        links: tourLinksToChannel(_d.tourLinks),
        startKey: start,
        editable: true,
      );
      if (!mounted || res == null) return;
      setState(() {
        _d.tourLinks
          ..clear()
          ..addAll(tourLinksFromChannel(res.links));
      });
      final action = res.newRoom;
      if (action == null) return;

      // «Yangi xona — hozir tushirish» — avval xona nomi.
      if (_d.panoramas.length >= _maxPhotos) {
        AppToast.error(context, _S.tooMany(l, _maxPhotos));
        return;
      }
      final choice = await showRoomPickerSheet(
        context,
        title: tr(l, 'bozor.pano.rooms.name_title'),
        hint: tr(l, 'bozor.pano.rooms.name_hint'),
      );
      if (!mounted) return;
      if (choice == null) {
        start = action.fromKey;
        continue;
      }
      final key = await _captureAndStore(roomName: choice.label(l));
      if (!mounted) return;
      if (key == null) {
        // Bekor yoki faqat saqlandi (qatorda `local:` turadi) — turgan
        // xonaga qaytamiz; havola yuklangandan keyin qo'yiladi.
        start = action.fromKey;
        continue;
      }
      setState(() {
        final merged = mergeNewRoomLinks(_d.tourLinks, action, key);
        _d.tourLinks
          ..clear()
          ..addAll(merged);
      });
      saveBozorDraftInBackground(widget.draft, WizardStep.description);
      ready.add(key);
      start = key;
    }
  }

  /// 360° qo'shish: nativ suratga olish → TELEFONDA tikish → yuklash →
  /// tayyor kalit. Foydalanuvchi natijani `PanoCaptureFlow` ekranida
  /// kutadi, qaytganda panorama ALLAQACHON serverda.
  ///
  /// ⚠️ GALEREYADAN YUKLASH OLIB TASHLANDI (izohga olingan —
  /// `pano_source_sheet.dart` ga qarang). Sabab: tikish har kadrning KAMERA
  /// POZASINI talab qiladi, galereyadagi tayyor equirect'da esa u yo'q.
  /// Qaytarish kerak bo'lsa o'sha fayldagi izohni oching va bu yerga tanlov
  /// varag'ini qaytaring.
  /// «360 foto qo'shish»: xona yo'q bo'lsa — to'g'ridan xona nomi so'raladi
  /// va skan boshlanadi; bor bo'lsa — XONALAR varag'i (ro'yxat + «Yangi xona
  /// skan qilish»). Har skan xonaga bog'lanadi — nom `panoramaNames` da.
  Future<void> _add360() async {
    if (_d.panoramas.isEmpty) {
      await _scanNewRoom();
      return;
    }
    final l = Localizations.localeOf(context);
    final res = await showPanoRoomsSheet(
      context,
      rooms: <PanoRoomItem>[
        for (final String p in _d.panoramas)
          PanoRoomItem(
            name: _roomName(l, p),
            status: _roomStatus(p),
            url: _d.panoramaUrls[p],
            file: _d.localPanoramas[p]?.previewPath,
          ),
      ],
      canAdd: _captureMode != null && _d.panoramas.length < _maxPhotos,
    );
    if (!mounted || res == null) return;
    if (res.newRoom) {
      await _scanNewRoom();
    } else {
      _openPano(res.index);
    }
  }

  PanoRoomStatus _roomStatus(String ref) {
    final lp = _d.localPanoramas[ref];
    if (lp != null) return lp.failed ? PanoRoomStatus.failed : PanoRoomStatus.local;
    final p = _d.pendingPanoramas[ref];
    if (p != null) return p.failed ? PanoRoomStatus.failed : PanoRoomStatus.pending;
    return PanoRoomStatus.ready;
  }

  /// Xona nomini so'raydi (tayyor turlar + «Boshqa» erkin nom), keyin skan.
  Future<void> _scanNewRoom() async {
    final l = Localizations.localeOf(context);
    if (_d.panoramas.length >= _maxPhotos) {
      AppToast.error(context, _S.tooMany(l, _maxPhotos));
      return;
    }
    final choice = await showRoomPickerSheet(
      context,
      title: tr(l, 'bozor.pano.rooms.name_title'),
      hint: tr(l, 'bozor.pano.rooms.name_hint'),
    );
    if (!mounted || choice == null) return;
    final key = await _captureAndStore(roomName: choice.label(l));
    if (!mounted || key == null) return;
    AppToast.success(context, tr(l, 'bozor.pano.flow.ready'));
  }

  /// Capture oqimini yuritadi va natijani qoralamaga yozadi.
  ///
  /// Qaytadi: yuklangan panoramaning S3 KALITI, yoki `null` (bekor / faqat
  /// saqlandi). Ikkala holatda ham qoralama TO'G'RI holatda:
  ///
  ///  * capture tugashi bilan (`onCaptured`) `local:<uuid>` havola qatorga
  ///    QO'SHILADI va qoralama diskka yoziladi — tikish paytida ilova o'lsa
  ///    ham kadrlar egasiz qolmaydi;
  ///  * yuklangach o'sha O'RINDA kalitga almashadi (uch qator — `panorama-360-
  ///    status.md` §2.3: `panoramas`, `panoramaUrls`, `uploadedMedia`);
  ///  * xato ekranidan chiqilsa `LocalPano` holati/xatosi yangilanadi va
  ///    qatorda «davom etish» belgisi bilan turadi.
  ///
  /// [resumeDir] — saqlangan tushirishni davom ettirish (o'sha havola).
  Future<String?> _captureAndStore({
    String? resumeDir,
    String? roomName,
  }) async {
    // Holat bitta oqimga tegishli. Retake katalogni almashtiradi, lekin
    // xona nomi va ro'yxatdagi o'rni yangi tushirishga o'tadi.
    final initialRef = resumeDir == null ? null : LocalPano.refOf(resumeDir);
    String? activeRef = initialRef;
    var insertAt = initialRef == null
        ? _d.panoramas.length
        : _d.panoramas.indexOf(initialRef);
    if (insertAt < 0) insertAt = _d.panoramas.length;
    var activeRoomName =
        roomName ?? (initialRef == null ? null : _d.roomName(initialRef));

    void storeLocal(String dir, LocalPanoStage stage, {String? error}) {
      final ref = LocalPano.refOf(dir);
      activeRef = ref;
      if (!_d.panoramas.contains(ref)) {
        _d.panoramas.insert(insertAt.clamp(0, _d.panoramas.length), ref);
      }
      _d.localPanoramas[ref] = LocalPano(dir: dir, stage: stage, error: error);
      if (activeRoomName != null) _d.panoramaNames[ref] = activeRoomName!;
    }

    final outcome = await widget.openCapture(
      context,
      resumeDir: resumeDir,
      onCaptured: (dir) {
        if (!mounted) return;
        setState(() => storeLocal(dir, LocalPanoStage.captured));
        saveBozorDraftInBackground(widget.draft, WizardStep.description);
      },
      onDiscarded: (dir) {
        if (!mounted) return;
        final ref = LocalPano.refOf(dir);
        if (ref != activeRef) return;
        setState(() {
          final index = _d.panoramas.indexOf(ref);
          if (index >= 0) {
            insertAt = index;
            _d.panoramas.removeAt(index);
          }
          activeRoomName = _d.panoramaNames.remove(ref) ?? activeRoomName;
          _d.localPanoramas.remove(ref);
          _d.panoramaUrls.remove(ref);
          _d.uploadedMedia.remove(ref);
          _d.tourLinks.removeWhere((link) => link.from == ref || link.to == ref);
          activeRef = null;
        });
        saveBozorDraftInBackground(widget.draft, WizardStep.description);
      },
    );
    if (!mounted) return null;
    switch (outcome) {
      case PanoUploaded(:final storageKey, :final url):
        setState(() {
          // Lokal havola turgan O'RINDA kalit — tartib saqlanadi.
          final replace = activeRef;
          final idx = replace == null ? -1 : _d.panoramas.indexOf(replace);
          if (idx >= 0) {
            final old = _d.panoramas[idx];
            _d.localPanoramas.remove(old);
            // Xona nomi havola bilan birga ko'chadi.
            final name = _d.panoramaNames.remove(old);
            if (name != null) _d.panoramaNames[storageKey] = name;
            _d.panoramas[idx] = storageKey;
          } else if (!_d.panoramas.contains(storageKey)) {
            _d.panoramas.insert(
              insertAt.clamp(0, _d.panoramas.length),
              storageKey,
            );
          }
          if (activeRoomName != null &&
              !_d.panoramaNames.containsKey(storageKey)) {
            _d.panoramaNames[storageKey] = activeRoomName!;
          }
          _d.panoramaUrls[storageKey] = url;
          _d.uploadedMedia[storageKey] = storageKey;
        });
        saveBozorDraftInBackground(widget.draft, WizardStep.description);
        return storageKey;
      case PanoSaved(:final dir, :final stitched, :final error):
        setState(() {
          storeLocal(
            dir,
            error == null
                ? (stitched ? LocalPanoStage.stitched : LocalPanoStage.captured)
                : LocalPanoStage.failed,
            error: error,
          );
        });
        saveBozorDraftInBackground(widget.draft, WizardStep.description);
        return null;
      case null:
        return null;
    }
  }

  /// Saqlangan tushirishni davom ettiradi (tikish yoki yuklash).
  Future<void> _resumeLocal(String ref) async {
    final lp = _d.localPanoramas[ref];
    if (lp == null) return;
    final l = Localizations.localeOf(context);
    if (!Directory(lp.dir).existsSync()) {
      // Katalog yo'q (iOS tozalagan / qurilma almashgan) — havola o'lik.
      setState(() {
        _d.panoramas.remove(ref);
        _d.localPanoramas.remove(ref);
      });
      saveBozorDraftInBackground(widget.draft, WizardStep.description);
      AppToast.error(context, tr(l, 'bozor.pano.view.err_missing'));
      return;
    }
    final key = await _captureAndStore(resumeDir: lp.dir);
    if (!mounted || key == null) return;
    AppToast.success(context, tr(l, 'bozor.pano.flow.ready'));
  }

  /// Yiqilgan SERVER tikishini qaytadan navbatga qo'yadi.
  ///
  /// ⚠️ FAQAT ESKI QORALAMALAR UCHUN (2026-09-13 gacha, `job:<id>` havolali).
  /// Yangi panoramalar telefonda tikiladi va `pendingPanoramas` ga umuman
  /// tushmaydi — bu yo'l va `PanoJobWatcher` o'sha eski yozuvlar tugagach
  /// olib tashlanadi.
  ///
  /// ⚠️ KADRLAR QAYTA YUBORILMAYDI. Server ularni 24 soat saqlaydi va
  /// `POST /pano/{id}/finish` XATO holatidagi ishni qaytadan yig'ib navbatga
  /// qo'yadi — ya'ni foydalanuvchi qaytadan surat olmaydi.
  Future<void> _retryPano(String ref) async {
    final p = _d.pendingPanoramas[ref];
    if (p == null) return;
    setState(() {
      _d.pendingPanoramas[ref] = PendingPano(
        jobId: p.jobId,
        startedAt: DateTime.now(),
      );
    });
    final api = PanoApi();
    try {
      await api.finish(p.jobId);
      _watcher.watch(widget.draft);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _d.pendingPanoramas[ref] = p.withError(
          e is PanoApiException ? e.message : e.toString(),
        );
      });
    } finally {
      api.dispose();
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
                        onBack: bozorStepBack(
                          context,
                          isFirstStep: draft.stepIndex(WizardStep.description) == 0,
                        ),
                        onClose: bozorStepClose(
                          context,
                          isFirstStep: draft.stepIndex(WizardStep.description) == 0,
                        ),
                        closeTooltip: tr(l, 'bozor.exit.title'),
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
                          // Existing rooms stay accessible even when capture
                          // is unavailable; viewer capability is independent.
                          if (_captureMode != null || _d.panoramas.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          MediaUploadRow(
                            label: _S.add360(l),
                            iconAsset: 'assets/icons/upload-360.svg',
                            // Yotiq ikonka — `MediaUploadRow.iconSize` izohiga
                            // qarang (PANO-04).
                            iconSize: 22,
                            paths: _d.panoramas,
                            // Eskiz serverdan keladi — kadrlar o'chirilgan,
                            // lokal nusxa yo'q.
                            urlOf: (k) => _d.panoramaUrls[k],
                            // Telefonda saqlangan tushirish: tikilgan bo'lsa
                            // `preview.jpg` eskizi, bo'lmasa «davom» belgisi.
                            fileOf: (k) => _d.localPanoramas[k]?.previewPath,
                            statusOf: (k) {
                              final lp = _d.localPanoramas[k];
                              if (lp != null) {
                                return lp.failed
                                    ? MediaItemStatus.failed
                                    : MediaItemStatus.local;
                              }
                              final p = _d.pendingPanoramas[k];
                              if (p == null) return MediaItemStatus.ready;
                              return p.failed
                                  ? MediaItemStatus.failed
                                  : MediaItemStatus.pending;
                            },
                            onAdd: _add360,
                            onRemove: (i) => setState(() {
                              final key = _d.panoramas.removeAt(i);
                              // Qoralamada osilib qolmasin: yuborishda
                              // `uploadedMedia` bo'yicha media ro'yxati
                              // quriladi va o'chirilgan panorama qaytib
                              // kelardi.
                              _d.panoramaUrls.remove(key);
                              _d.uploadedMedia.remove(key);
                              _d.panoramaNames.remove(key);
                              // Kutilayotganini ham olib tashlaymiz — aks
                              // holda e'lon YUBORILMAS bo'lib qolardi:
                              // qatorda ko'rinmaydigan ish uni to'sib
                              // turardi.
                              _d.pendingPanoramas.remove(key);
                              // Telefondagi kadrlar ham (75 MB) — egasiz
                              // qolmasin.
                              final lp = _d.localPanoramas.remove(key);
                              if (lp != null) {
                                unawaited(
                                  Directory(lp.dir)
                                      .delete(recursive: true)
                                      .then<void>((_) {}, onError: (_) {}),
                                );
                              }
                              _d.tourLinks.removeWhere(
                                (t) => t.from == key || t.to == key,
                              );
                            }),
                            // 360° SFERADA ochiladi. Oddiy galereya uni
                            // cho'zilgan lenta qilib ko'rsatadi va
                            // panorama ekani bilinmaydi. Bir nechta
                            // bo'lsa — yurib bo'ladigan TUR, va egasi
                            // shu yerda o'tish tugmalarini qo'yadi.
                            onOpen: _openPano,
                          ),
                          ],
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
