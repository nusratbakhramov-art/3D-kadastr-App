/// Xonalarni videoga olish ekrani.
///
/// ⚠️ OQIMDA EMAS. Bu AI Baholash wizardining 1-qadami edi; qadam oqimdan
/// olib tashlandi (skan intro → endi to'g'ridan kadastr qadamiga o'tadi) va
/// ekranga ilovadan hech qanday yo'l qolmadi. Kod ataylab saqlanmoqda —
/// qaytarish uchun `ai_scan_intro_screen.dart` va `ai_scan_process_screen.dart`
/// dagi marshrutlarni `ai/start` ga qaytarish, qadam chiziqlarini (hozir 7)
/// 8 ga ko'tarish va `ai_draft_resume.dart` zanjiriga `video` ni qo'shish
/// yetarli. Quyidagi izohlar o'sha oqimni tasvirlaydi.
///
/// Ekran ikki ishni bajaradi:
/// 1. Xona-ma-xona video oladi: "Videoga olish" → qo'llanma varag'i (olti
///    qoida birma-bir, `capture_guide_sheet.dart`) → xona tanlash → kamera →
///    [AiVideoStatusScreen] (yuklash + kuzatuv).
/// 2. Olingan xonalar ro'yxatini ko'rsatadi: lokal yozuvlar + 3DGS
///    serveridagi holat ([RoomCaptureStore.merge]).
///
/// Qoidalar ekranning o'zida TAKRORLANMAYDI — ular faqat "Videoga olish"
/// bosilganda chiqadigan varaqda, o'qilishi kerak bo'lgan paytda.
///
/// QADAM IXTIYORIY: video 3DGS modeli uchun — u baholash sifatini oshiradi,
/// lekin usiz ham ariza to'ldiriladi. Shuning uchun "Hozircha o'tkazib
/// yuborish" yo'li ochiq va foydalanuvchi videoni keyinroq, arizaga qaytib
/// kelib ham qo'sha oladi.
///
/// ARIZA ID: 3DGS serveridagi ish ariza id ga bog'lanadi (hozircha `name`
/// matni orqali, keyin alohida ustun bilan). Shu sababli video YUKLASHDAN
/// oldin draft ariza mavjudligiga ishonch hosil qilinadi — LiDAR yo'q
/// qurilmada draft skan qadamida yaratilmaydi va id'siz qolib ketardi.
/// Draft ataylab kech — birinchi YUKLASH oldidan — yaratiladi: qo'llanmani
/// ochib bekor qilgan foydalanuvchi bo'sh ariza qoldirmasin.
///
/// Kamera: [VideoCapture.capture] platformaga qarab tanlaydi — Android'da
/// qurilmaning o'z kamera ilovasi, iOS'da AVFoundation recorder'i.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../ai_draft_saver.dart';
import '../data/room_capture_store.dart';
import '../data/v2m_client.dart';
import '../data/video_capture.dart';
import '../models/ai_baholash_bundle.dart';
import '../models/ai_scan_result.dart';
import '../widgets/capture_guide_sheet.dart';
import '../widgets/capture_review_sheet.dart';
import '../widgets/room_picker_sheet.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/wizard_nav_bar.dart';
import 'ai_cadastre_screen.dart';
import 'ai_video_status_screen.dart';

class AiStartScreen extends StatefulWidget {
  const AiStartScreen({
    super.key,
    this.scan,
    this.draftId,
    this.scanJobId,
    this.resumeBundle,
  });

  /// Resume oqimi: draft'dan to'liq tiklangan bundle. Berilsa, "Davom etish"
  /// uni kadastr qadamiga uzatadi — aks holda saqlangan kadastr/mijoz/
  /// joylashuv ma'lumotlari bo'sh bundle bilan almashib ketardi.
  final AiBaholashBundle? resumeBundle;

  /// 3D skan natijasi (skan qadamidan) — keyingi ekranlarga uzatiladi.
  final AiScanResult? scan;

  /// Skandan keyin yaratilgan DRAFT ariza id (LiDAR yo'lida bo'ladi).
  final int? draftId;

  /// Resume oqimi: skanlangan 3D model bor draft id.
  final int? scanJobId;

  @override
  State<AiStartScreen> createState() => _AiStartScreenState();
}

class _AiStartScreenState extends State<AiStartScreen> {
  final V2mClient _v2m = V2mClient();

  int? _arizaId;
  List<CapturedRoom> _rooms = const [];
  bool _busy = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _arizaId = widget.draftId;
    _loadRooms();
  }

  @override
  void dispose() {
    _v2m.dispose();
    super.dispose();
  }

  /// Lokal ro'yxatni o'qiydi, so'ng 3DGS serverdagi holat bilan
  /// birlashtiradi. Server — haqiqiy manba: ilova qayta o'rnatilgan yoki
  /// boshqa qurilmada olingan xonalar ham shu yerdan chiqadi, chunki ular
  /// ariza id bo'yicha indekslangan.
  Future<void> _loadRooms({bool fromServer = true}) async {
    final id = _arizaId;
    final local = id == null
        ? await RoomCaptureStore.load(null)
        : await RoomCaptureStore.adoptOrphans(id);
    if (!mounted) return;
    setState(() => _rooms = local);
    if (!fromServer || id == null) return;

    setState(() => _refreshing = true);
    try {
      final remote = await _v2m.listByAriza(id.toString());
      if (!mounted) return;
      final merged = RoomCaptureStore.merge(local, remote);
      setState(() => _rooms = merged);
      await RoomCaptureStore.save(id, merged);
    } on V2mException {
      // Server yetib bo'lmasa lokal ro'yxat qoladi — oqim to'xtamaydi.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Draft ariza bo'lmasa yaratadi. Login/tarmoq yo'q bo'lsa `createAiDraft`
  /// jim `null` qaytaradi — bu yerda uni yutib yubormaymiz, chunki id'siz
  /// video serverda arizaga bog'lanmaydi.
  Future<int?> _ensureAriza() async {
    if (_arizaId != null) return _arizaId;
    // 'video' — tiklash zanjirining birinchi qadami: foydalanuvchi shu yerda
    // to'xtasa, keyin qaytib kelganda aynan shu ekran (va olingan xonalar
    // ro'yxati) ochiladi.
    final id = await createAiDraft(currentStep: 'video');
    if (id == null || !mounted) return null;
    setState(() => _arizaId = id);
    // "Draftsiz" yig'ilganlarni ariza kalitiga ko'chiramiz. Ro'yxat ATAYLAB
    // qayta O'QILMAYDI: xotiradagi [CapturedRoom] qatorlari qiymat bo'yicha
    // tenglashmaydi va ular ochilayotgan yuklash ekraniga havola bo'yicha
    // bog'langan — diskdan qayta o'qish o'sha bog'lanishni uzib qo'yardi.
    await RoomCaptureStore.adoptOrphans(id);
    await _persist();
    return id;
  }

  Future<void> _persist() => RoomCaptureStore.save(_arizaId, _rooms);

  void _updateRoom(CapturedRoom target, CapturedRoom updated) {
    final i = _rooms.indexOf(target);
    if (i < 0) return;
    final next = [..._rooms];
    next[i] = updated;
    setState(() => _rooms = next);
    _persist();
  }

  /// Qo'llanma varag'i → xona tanlash → kamera → yuklash ekrani.
  ///
  /// Sikl kuzatuv ekranidagi "Yana xona qo'shish" uchun: u ekranni yopib shu
  /// yerga qaytadi va zanjir boshidan takrorlanadi. Rekursiya EMAS — ketma-ket
  /// olingan o'nlab xona await zanjirini cho'zib yubormasin.
  Future<void> _record() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    var again = true;
    while (again) {
      if (!mounted) return;
      // Draft bu yerda YARATILMAYDI — faqat yuklash oldidan (_captureLoop /
      // _openStatus). Qo'llanmani ochib bekor qilgan odam ortida bo'sh ariza
      // qolmasin.
      final ready = await showCaptureGuideSheet(context);
      if (ready != true || !mounted) return;
      final room = await showRoomPickerSheet(context);
      if (room == null || !mounted) return;

      again = await _captureLoop(room);
    }
  }

  /// Kamera → tasdiq varag'i. "Qayta olish" tanlansa kamera yana ochiladi,
  /// qo'llanma va xona tanlash takrorlanmaydi.
  ///
  /// Yuklash HECH QACHON o'zidan-o'zi boshlanmaydi: video 1.5 GB gacha
  /// bo'lishi mumkin va yozuv foydalanuvchi tugatmasdan ham uzilishi mumkin
  /// (xotira, issiq, fon), shuning uchun qaror foydalanuvchida.
  ///
  /// Qaytadi: kuzatuv ekrani "Yana xona qo'shish" bilan yopilgan bo'lsa
  /// `true` — chaqiruvchi zanjirni yangi xona uchun qaytadan boshlaydi.
  Future<bool> _captureLoop(RoomChoice room) async {
    while (true) {
      setState(() => _busy = true);
      VideoCaptureResult? video;
      try {
        video = await VideoCapture.capture();
      } on VideoCaptureException catch (e) {
        if (!mounted) return false;
        setState(() => _busy = false);
        AppToast.error(context, e.message);
        return false;
      }
      if (!mounted) return false;
      setState(() => _busy = false);
      if (video == null) return false; // kamera bekor qilindi

      final choice = await showCaptureReviewSheet(
        context,
        video: video,
        room: room,
      );
      if (!mounted) return false;

      switch (choice) {
        case CaptureReviewChoice.upload:
          // Draft AYNAN shu yerda — birinchi yuklash oldidan — paydo bo'ladi.
          // Qatorni ro'yxatga qo'shishdan OLDIN: _ensureAriza "draftsiz"
          // yozuvlarni ko'chiradi, keyin qo'shilgan qator esa o'sha ko'chirish
          // ta'siriga tushmaydi.
          setState(() => _busy = true);
          final ariza = await _ensureAriza();
          if (!mounted) return false;
          setState(() => _busy = false);
          final captured = _capturedFrom(room, video.path);
          setState(() => _rooms = [..._rooms, captured]);
          await _persist();
          if (!mounted) return false;
          if (ariza == null) {
            // Ariza yaratilmadi (login/tarmoq) — video SAQLANIB qoladi va
            // ro'yxatda "Yuborilmagan" bo'lib turadi, qatordan qayta urinish
            // mumkin. 1.5 GB yozuvni tashlab yuborish mumkin emas.
            AppToast.error(context, _S.noDraft(Localizations.localeOf(context)));
            return false;
          }
          return _openStatus(captured, autoUpload: true);
        case CaptureReviewChoice.retake:
          await _deleteLocalVideo(video.path);
          continue; // kamerani qayta ochamiz
        case CaptureReviewChoice.discard:
          await _deleteLocalVideo(video.path);
          return false;
        case null:
          // Varaq tashqariga bosib yopilgan — videoni saqlab qolamiz va
          // ro'yxatga yuklanmagan qator sifatida qo'yamiz, aks holda 1.5 GB
          // yozuv bir tasodifiy teginishda yo'q bo'lardi.
          final dropped = _capturedFrom(room, video.path);
          setState(() => _rooms = [..._rooms, dropped]);
          await _persist();
          return false;
      }
    }
  }

  CapturedRoom _capturedFrom(RoomChoice room, String videoPath) => CapturedRoom(
        room: room.kind,
        customName: room.name,
        videoPath: videoPath,
        createdAt: DateTime.now(),
      );

  /// Yuklanmagan videoni diskdan o'chiradi. 4K60 yozuv daqiqasiga ~465 MB,
  /// shuning uchun tashlangan faylni qoldirib ketish mumkin emas.
  Future<void> _deleteLocalVideo(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // O'chirilmasa ham oqim davom etadi — iOS temp papkasini o'zi tozalaydi.
    }
  }

  /// Qatorni ro'yxatdan olib tashlaydi (server tomonda allaqachon
  /// o'chirilgan). Lokal video ham bo'lsa fayl bilan birga ketadi.
  void _forgetRoom(CapturedRoom target) {
    final path = target.videoPath;
    setState(() => _rooms = _rooms.where((r) => r != target).toList());
    _persist();
    if (path != null) _deleteLocalVideo(path);
  }

  /// Ro'yxatdagi qatorni o'chirish. Serverda modeli bo'lsa u ham
  /// o'chiriladi (ishlayotgan bo'lsa server jarayonni to'xtatadi).
  Future<void> _deleteRoom(CapturedRoom target) async {
    final l = Localizations.localeOf(context);
    final id = target.modelId;
    final busy = target.isUploaded && !target.isDone && !target.isFailed;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(busy ? _S.cancelTitle(l) : _S.deleteTitle(l)),
        content: Text(
          id == null
              ? _S.deleteLocalBody(l)
              : (busy ? _S.cancelBody(l) : _S.deleteBody(l)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_S.keep(l)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.chatRedDeep,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_S.delete(l)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Serverda modeli yo'q — faqat lokal qator va fayl.
    if (id == null) {
      _forgetRoom(target);
      return;
    }

    setState(() => _busy = true);
    try {
      await _v2m.deleteModel(id);
      if (!mounted) return;
      setState(() => _busy = false);
      _forgetRoom(target);
      HapticFeedback.mediumImpact();
      AppToast.success(context, _S.deleted(l));
    } on V2mException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, '${_S.deleteFailed(l)}: ${e.message}');
    }
  }

  /// Yuklash/kuzatuv ekrani. Model id va holat callback orqali qaytadi —
  /// ekran qanday yopilishidan qat'i nazar ro'yxat yangilanadi.
  ///
  /// Qaytadi: ekran "Yana xona qo'shish" bilan yopilgan bo'lsa `true`.
  Future<bool> _openStatus(
    CapturedRoom captured, {
    bool autoUpload = false,
  }) async {
    // Hali yuklanmagan qator — ariza id yuklashdan oldin kerak (video 3DGS
    // serverida shu id bilan arizaga bog'lanadi).
    if (captured.modelId == null && _arizaId == null) {
      setState(() => _busy = true);
      final ariza = await _ensureAriza();
      if (!mounted) return false;
      setState(() => _busy = false);
      if (ariza == null) {
        AppToast.error(context, _S.noDraft(Localizations.localeOf(context)));
        return false;
      }
    }
    var current = captured;
    final again = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: 'ai/video-status'),
        builder: (_) => AiVideoStatusScreen(
          videoPath: current.videoPath,
          room: current.room,
          roomName: current.customName,
          arizaId: _arizaId,
          modelId: current.modelId,
          autoUpload: autoUpload,
          allowAddRoom: true,
          onUploaded: (modelId) {
            final next = current.copyWith(modelId: modelId);
            _updateRoom(current, next);
            current = next;
          },
          onStatus: (status) {
            if (current.status == status) return;
            final next = current.copyWith(status: status);
            _updateRoom(current, next);
            current = next;
          },
          onDeleted: (_) => _forgetRoom(current),
        ),
      ),
    );
    if (mounted) await _loadRooms();
    return again == true;
  }

  /// Ro'yxatdagi qatorni ochadi; ekran "Yana xona qo'shish" bilan yopilsa
  /// darhol yangi yozuv zanjiri boshlanadi.
  Future<void> _openRoom(CapturedRoom captured) async {
    if (await _openStatus(captured) && mounted) await _record();
  }

  /// Kamida bitta video SERVERGA yuklanganmi.
  ///
  /// Davom etishga TO'SIQ EMAS (qadam ixtiyoriy) — faqat tugmalarni
  /// tartiblaydi: yuklangani bor bo'lsa asosiy tugma "Davom etish" bo'ladi.
  /// Ishlov berish holati (`queued`/`processing`/`done`) ahamiyatsiz: model
  /// 10-20 daqiqa tayyorlanadi va foydalanuvchini shuncha kutdirib bo'lmaydi.
  bool get _hasUpload => _rooms.any((r) => r.isUploaded);

  void _continue() {
    HapticFeedback.lightImpact();
    final bundle = widget.resumeBundle;
    // Qadamni saqlaymiz — shundagina tiklashda kadastrdan ochiladi. Bundle
    // bor bo'lsa (resume) u bilan, aks holda payloadga tegmasdan.
    if (bundle != null) {
      saveAiDraftStepInBackground(bundle, 'cadastre');
    } else if (_arizaId != null) {
      saveAiDraftStepOnlyInBackground(_arizaId!, 'cadastre');
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/cadastre'),
        builder: (_) => AiCadastreScreen(
          scan: widget.scan ?? bundle?.scan,
          draftId: _arizaId,
          scanJobId: widget.scanJobId,
          // Resume: saqlangan kadastr natijasi va to'liq bundle o'tadi, aks
          // holda keyingi qadamlar bo'sh bundle bilan qaytadan boshlanardi.
          // `initial` faqat HAQIQATAN topilgan kadastr uchun — video qadamida
          // yaratilgan draftning payloadi bo'sh va undagi natija ham bo'sh
          // bo'ladi, uni "yuklandi" holatida ko'rsatish noto'g'ri bo'lardi.
          areaM2: bundle?.areaM2,
          initial: (bundle != null && bundle.kadastr.cadastreNumber.isNotEmpty)
              ? bundle.kadastr
              : null,
          resumeBundle: bundle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final hasRooms = _rooms.isNotEmpty;
    final hasUpload = _hasUpload;

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
                    title: _S.appBar(l),
                    subtitle: _S.subtitle(l),
                    // Bu tugma butun oqimni yopadi — bitta qadam
                    // orqaga EMAS. Qadamma-qadam qaytish pastda.
                    onBack: () => confirmCloseAiWizard(context),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 8, activeIndex: 0),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      Text(
                        _S.heading(l),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1.2,
                          color: headingColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _S.body(l),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                      if (hasRooms) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _S.roomsTitle(l),
                                style: TextStyle(
                                  fontFamily: 'MTSCompact',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: headingColor,
                                ),
                              ),
                            ),
                            if (_refreshing)
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(subColor),
                                ),
                              )
                            else
                              InkWell(
                                onTap: _loadRooms,
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.refresh_rounded,
                                      size: 18, color: subColor),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final room in _rooms)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RoomRow(
                              captured: room,
                              isDark: isDark,
                              locale: l,
                              onTap: () => _openRoom(room),
                              onDelete: () => _deleteRoom(room),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy)
                        const _BusyButton()
                      else
                        ListingCtaButton(
                          // Bitta xona olingandan keyin "Videoga olish" ning
                          // ma'nosi aynan "Yana xona qo'shish" — video hali
                          // YUKLANMAGAN bo'lsa ham. Server yotgan paytda
                          // xonalarni ketma-ket olib qo'yib, keyin ro'yxatdan
                          // birma-bir yuborish shu yo'l bilan ishlaydi.
                          label: hasUpload
                              ? _S.continueLabel(l)
                              : (hasRooms ? _S.addRoom(l) : _S.record(l)),
                          onTap: hasUpload ? _continue : _record,
                        ),
                      // Ostidagi tugma har doim bor: video yuklangan bo'lsa —
                      // yana xona qo'shish, yo'q bo'lsa — qadamni o'tkazib
                      // yuborish (video ixtiyoriy).
                      TextButton(
                        onPressed: _busy
                            ? null
                            : (hasUpload ? _record : _continue),
                        child: Text(
                          hasUpload ? _S.addRoom(l) : _S.skip(l),
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: subColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Olingan xona qatori — holat belgisi bilan; bosilsa kuzatuv ekrani ochiladi.
class _RoomRow extends StatelessWidget {
  const _RoomRow({
    required this.captured,
    required this.isDark,
    required this.locale,
    required this.onTap,
    required this.onDelete,
  });

  final CapturedRoom captured;
  final bool isDark;
  final Locale locale;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final (IconData icon, Color accent, String label) = captured.isFailed
        ? (
            Icons.error_outline_rounded,
            AppColors.chatRedDeep,
            _S.statusFailed(locale),
          )
        : captured.isDone
            ? (
                Icons.check_circle_rounded,
                AppColors.callGreenDeep,
                _S.statusDone(locale),
              )
            : captured.isUploaded
                ? (
                    Icons.autorenew_rounded,
                    const Color(0xFFE0A12A),
                    _S.statusWorking(locale),
                  )
                : (
                    Icons.cloud_upload_outlined,
                    subColor,
                    _S.statusPending(locale),
                  );

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  captured.label(locale),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 13,
                  color: accent,
                ),
              ),
              const SizedBox(width: 4),
              // O'chirish qatorning O'ZIDA: yuklanmagan videoni (serverda
              // modeli yo'q) boshqa hech qanday yo'l bilan olib tashlash
              // mumkin emas edi — u ro'yxatda abadiy qolib ketardi.
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: subColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: subColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusyButton extends StatelessWidget {
  const _BusyButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(999),
      child: const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.buttonTextBlack),
            ),
          ),
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String delete(Locale l) => tr(l, 'common.delete');
  static String keep(Locale l) => tr(l, 'common.cancel');
  static String deleteTitle(Locale l) =>
      tr(l, 'services.ai.capture.delete_title');
  static String deleteBody(Locale l) =>
      tr(l, 'services.ai.capture.delete_body');
  static String deleteLocalBody(Locale l) =>
      tr(l, 'services.ai.capture.delete_local_body');
  static String cancelTitle(Locale l) =>
      tr(l, 'services.ai.capture.cancel_title');
  static String cancelBody(Locale l) =>
      tr(l, 'services.ai.capture.cancel_body');
  static String deleted(Locale l) => tr(l, 'services.ai.capture.deleted');
  static String deleteFailed(Locale l) =>
      tr(l, 'services.ai.capture.delete_failed');

  static String appBar(Locale l) => tr(l, 'services.ai.common.brand_title');
  static String subtitle(Locale l) => tr(l, 'services.ai.capture.subtitle');
  static String heading(Locale l) => tr(l, 'services.ai.capture.heading');
  static String body(Locale l) => tr(l, 'services.ai.capture.body');
  static String record(Locale l) => tr(l, 'services.ai.capture.record');
  static String continueLabel(Locale l) =>
      tr(l, 'services.ai.capture.continue');
  static String skip(Locale l) => tr(l, 'services.ai.capture.skip');
  static String roomsTitle(Locale l) =>
      tr(l, 'services.ai.capture.rooms_title');
  static String addRoom(Locale l) => tr(l, 'services.ai.capture.add_room');
  static String noDraft(Locale l) => tr(l, 'services.ai.capture.no_draft');
  static String statusPending(Locale l) =>
      tr(l, 'services.ai.capture.status_pending');
  static String statusWorking(Locale l) =>
      tr(l, 'services.ai.capture.status_working');
  static String statusDone(Locale l) =>
      tr(l, 'services.ai.capture.status_done');
  static String statusFailed(Locale l) =>
      tr(l, 'services.ai.capture.status_failed');
}
