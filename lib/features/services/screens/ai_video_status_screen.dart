/// Xona videosi yuborilgandan keyingi ekran: yuklash progressi → 3DGS
/// serverdagi ishning holati → tayyor modelni ochish.
///
/// Uch bosqich:
/// 1. `uploading` — video v2m serveriga oqib boradi, baytlar bo'yicha progress.
///    Bu yagona bosqich foydalanuvchini ekranda ushlab turadi: fon yuklash
///    yo'q, ekran yopilsa transfer uziladi.
/// 2. `waiting` — har 4 soniyada `GET /api/models/{id}`; bosqich nomi va
///    foizi ko'rsatiladi. Bu yerda ilovani yopish MUMKIN — ish serverda
///    davom etadi.
/// 3. `ready` / `failed` — tayyor splat serverdagi Spark viewer'ida
///    ([V2mViewerScreen]) ochiladi, yoki xato ko'rsatiladi.
///
/// DIQQAT: `status == 'done'` bo'lishi modelning chiqqanini KAFOLATLAMAYDI —
/// SfM sifatsiz chiqsa quvur ogohlantirish bilan davom etadi va eksport
/// bo'lmasligi mumkin. Shu sababli UI `files['scene']` bo'yicha hal qiladi.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../data/room_capture_store.dart';
import '../data/v2m_client.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import 'v2m_viewer_screen.dart';

/// `confirm` — video tayyor, lekin YUKLANMAGAN. Yuklash foydalanuvchi
/// tugmani bosgandan keyin boshlanadi: fayl 1.5 GB gacha bo'lishi mumkin va
/// jimgina yuborish serverda GPU vaqtini behuda sarflaydi.
/// `gone` — model serverda topilmadi (o'chirilgan). Ilgari bunday holatda
/// polling xatosi jimgina yutilib, ekran abadiy kutish holatida qolardi.
enum _Phase { confirm, uploading, waiting, ready, failed, gone }

class AiVideoStatusScreen extends StatefulWidget {
  const AiVideoStatusScreen({
    super.key,
    required this.room,
    this.roomName,
    this.videoPath,
    this.arizaId,
    this.modelId,
    this.autoUpload = false,
    this.allowAddRoom = false,
    this.onUploaded,
    this.onStatus,
    this.onDeleted,
  });

  /// Yozib olingan video (lokal temp/cache fayli). `null` — yozuv serverdan
  /// kelgan, lokal video yo'q: faqat kuzatish mumkin, qayta yuborish emas.
  final String? videoPath;

  /// Qaysi xona — v2m'ga metadata bo'lib ketadi.
  final RoomKind room;

  /// "Boshqa" xonaga foydalanuvchi bergan nom. Berilsa sarlavhada va
  /// serverdagi ish yorlig'ida turning tarjimasi o'rniga shu ishlatiladi.
  final String? roomName;

  /// Asosiy backend yaratgan ariza id — serverga alohida `ariza_id` maydoni
  /// bo'lib ketadi, keyin `GET /api/models?ariza_id=` shu bo'yicha topadi.
  final int? arizaId;

  /// Berilsa — video allaqachon yuborilgan, ekran to'g'ridan kuzatuvdan
  /// boshlanadi (ariza ichidan xonani qayta ochish).
  final String? modelId;

  /// Ekran ochilishi bilan yuklashni boshlaydimi. FAQAT foydalanuvchi
  /// tasdiq varag'ida "yuklash" ni tanlagan yo'l `true` beradi.
  ///
  /// Default `false` ataylab: ilgari ekran `initState` da darhol yuklardi va
  /// ro'yxatdagi yuklanmagan qatorni bosish ham qayta yuklab yuborardi —
  /// serverda bir xil videoning ikki nusxasi shundan paydo bo'lgan.
  final bool autoUpload;

  /// "Yana xona qo'shish" ko'rsatiladimi.
  ///
  /// Faqat video qadamidan (`AiStartScreen`) ochilganda `true`: tugma ekranni
  /// `true` bilan yopadi va chaqiruvchi darhol yangi xona yozuvini boshlaydi.
  /// Yozib olish oqimi o'sha ekranda turgani uchun bu yerda takrorlanmaydi.
  /// Ariza tafsilotidan (`RoomModelsSection`) ochilganda yozish oqimi umuman
  /// yo'q — tugma ham chizilmaydi.
  final bool allowAddRoom;

  /// Yuklash tugab, server model id bergan payt. Callback ataylab: ekran
  /// qanday yopilishidan qat'i nazar (tugma, orqaga, sistema) chaqiriladi.
  final void Function(String modelId)? onUploaded;

  /// Har pollingda joriy holat (`queued`/`processing`/`done`/`failed`).
  final void Function(String status)? onStatus;

  /// Model serverdan o'chirilgan payt — chaqiruvchi ro'yxatdan qatorni
  /// olib tashlashi kerak.
  final void Function(String modelId)? onDeleted;

  @override
  State<AiVideoStatusScreen> createState() => _AiVideoStatusScreenState();
}

class _AiVideoStatusScreenState extends State<AiVideoStatusScreen> {
  static const _pollInterval = Duration(seconds: 4);

  final V2mClient _v2m = V2mClient();

  _Phase _phase = _Phase.uploading;
  int _sent = 0;
  int _total = 0;
  String? _modelId;
  V2mModel? _model;
  String? _error;
  Timer? _poll;
  int _localBytes = 0;
  bool _deleting = false;

  /// Lokal video diskda YO'Q. Saqlangan yo'l "o'lik" bo'lishi odatiy hol —
  /// iOS tmp/Caches ni tozalaydi va qayta o'rnatishda konteyner nomi
  /// o'zgaradi. Shunda "Qayta urinish" ning ma'nosi yo'q: yuboradigan fayl
  /// yo'q, xonani qaytadan olish kerak.
  bool _videoGone = false;

  /// Ketma-ket muvaffaqiyatsiz pollinglar soni; [_maxPollFails] ga yetganda
  /// kutish to'xtatiladi.
  int _pollFails = 0;
  static const int _maxPollFails = 5;

  @override
  void initState() {
    super.initState();
    final existing = widget.modelId;
    if (existing != null) {
      _modelId = existing;
      _phase = _Phase.waiting;
      _startPolling();
    } else if (widget.autoUpload) {
      _upload();
    } else {
      _phase = _Phase.confirm;
      _measureLocalVideo();
    }
    // Har qanday bosqichda tekshiramiz: ekran `failed` bilan ochilganda
    // (server modeli yiqilgan) `_measureLocalVideo` ishlamaydi, lekin
    // "Qayta urinish" tugmasi aynan o'sha yerda ko'rsatiladi.
    _checkLocalVideo();
  }

  /// Lokal fayl hali joyidami — bitta `stat`, natijasi faqat tugmani
  /// ko'rsatish/yashirish uchun.
  Future<void> _checkLocalVideo() async {
    final path = widget.videoPath;
    if (path == null) return;
    final exists = await File(path).exists();
    if (!mounted || exists) return;
    setState(() => _videoGone = true);
  }

  /// Tasdiq ekranida hajmni ko'rsatish uchun. Fayl yo'q bo'lib qolgan bo'lsa
  /// (temp tozalangan) — darhol xato holatiga o'tamiz.
  Future<void> _measureLocalVideo() async {
    final path = widget.videoPath;
    if (path == null) {
      setState(() {
        _phase = _Phase.failed;
        _error = null;
      });
      return;
    }
    try {
      final size = await File(path).length();
      if (!mounted) return;
      setState(() => _localBytes = size);
    } on FileSystemException {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _videoGone = true;
        _error = _S.videoMissing(Localizations.localeOf(context));
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _v2m.dispose();
    super.dispose();
  }

  /// Tur + nom juftligi — "Boshqa" da nom turning tarjimasini almashtiradi.
  RoomChoice get _choice => RoomChoice(widget.room, name: widget.roomName);

  String get _jobName =>
      v2mJobName(arizaId: widget.arizaId, room: _choice.labelUz);

  /// Ekranni "yana xona" signali bilan yopadi. Qo'llanma → xona tanlash →
  /// kamera zanjiri `AiStartScreen` da, shuning uchun bu yerda faqat pop.
  void _addRoom() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(true);
  }

  Future<void> _upload() async {
    final path = widget.videoPath;
    if (path == null) {
      setState(() {
        _phase = _Phase.failed;
        _error = null;
      });
      return;
    }
    setState(() {
      _phase = _Phase.uploading;
      _error = null;
      _sent = 0;
      _total = 0;
    });
    try {
      final id = await _v2m.upload(
        file: File(path),
        name: _jobName,
        arizaId: widget.arizaId?.toString(),
        room: widget.room.wire,
        roomOrd: 1,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _sent = sent;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _modelId = id;
        _phase = _Phase.waiting;
      });
      widget.onUploaded?.call(id);
      _startPolling();
    } on V2mException catch (e) {
      if (!mounted) return;
      final gone = e.code == 'NO_FILE' || e.code == 'EMPTY_FILE';
      setState(() {
        _phase = _Phase.failed;
        if (gone) _videoGone = true;
        _error = gone
            ? _S.videoMissing(Localizations.localeOf(context))
            : e.message;
      });
    } catch (e) {
      // Kutilmagan xato ham ekranni "yuklanmoqda" da qoldirmasligi kerak:
      // aynan shu holat foydalanuvchiga cheksiz "0.0 / 0.0 MB" bo'lib
      // ko'rinardi va bekor qilishning ham iloji yo'q edi.
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$e';
      });
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _pollOnce());
    _pollOnce();
  }

  Future<void> _pollOnce() async {
    final id = _modelId;
    if (id == null) return;
    try {
      final model = await _v2m.getModel(id);
      _pollFails = 0;
      if (!mounted) return;
      setState(() => _model = model);
      widget.onStatus?.call(model.status);
      if (model.isDone || model.isFailed) {
        _poll?.cancel();
        HapticFeedback.mediumImpact();
        setState(() {
          _phase = model.isFailed ? _Phase.failed : _Phase.ready;
          if (model.isFailed) _error = model.error;
        });
      }
    } on V2mException catch (e) {
      // Model o'chirilgan bo'lsa kutishning ma'nosi yo'q — aks holda
      // aylanuvchi halqa abadiy aylanardi.
      if (e.code == 'NOT_FOUND') {
        _poll?.cancel();
        if (mounted) setState(() => _phase = _Phase.gone);
        return;
      }
      _onPollFailed(e.message);
    } catch (e) {
      // Kutilmagan xato: `FormatException` (server HTML qaytardi),
      // `http.ClientException`, yoki `V2mModel.fromMap` dagi cast xatosi.
      _onPollFailed('$e');
    }
  }

  /// Ketma-ket xatolar hisobi. O'tkinchi uzilish normal — bitta xato uchun
  /// kutishni to'xtatmaymiz. Lekin server BUTUNLAY yiqilgan bo'lsa
  /// (502, buzuq javob) ilgari halqa abadiy aylanardi va har 4 soniyada
  /// so'rov ketaverardi: foydalanuvchi ishlayotgan jobni kutayotgandek
  /// ko'rinardi, aslida esa kutadigan narsa yo'q edi.
  void _onPollFailed(String message) {
    _pollFails++;
    if (_pollFails < _maxPollFails) return;
    _poll?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  /// Modelni serverdan o'chiradi. Ishlov berish ketayotgan bo'lsa server
  /// jarayonni to'xtatadi va navbatdagi ishga o'tadi — shuning uchun
  /// tasdiqlash matni ham boshqacha.
  Future<void> _delete() async {
    final id = _modelId;
    if (id == null) return;
    final l = Localizations.localeOf(context);
    final busy = _phase == _Phase.waiting;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(busy ? _S.cancelTitle(l) : _S.deleteTitle(l)),
        content: Text(busy ? _S.cancelBody(l) : _S.deleteBody(l)),
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

    // O'chirish 30 soniyagacha ketishi mumkin (server jarayonni to'xtatadi),
    // shuning uchun ekranni band holatga qo'yamiz.
    setState(() => _deleting = true);
    try {
      await _v2m.deleteModel(id);
      _poll?.cancel();
      if (!mounted) return;
      widget.onDeleted?.call(id);
      HapticFeedback.mediumImpact();
      AppToast.success(context, _S.deleted(l));
      Navigator.of(context).pop();
    } on V2mException catch (e) {
      if (!mounted) return;
      AppToast.error(context, '${_S.deleteFailed(l)}: ${e.message}');
    } catch (e) {
      // Masalan `http.ClientException` — ishlayotgan jobni to'xtatganda
      // server ulanishni uzib yuborishi mumkin. U V2mException EMAS.
      if (!mounted) return;
      AppToast.error(context, '${_S.deleteFailed(l)}: $e');
    } finally {
      // Bayroq HAR DOIM tushadi. Ilgari u faqat V2mException tarmog'ida
      // tushardi: boshqa xato chiqsa qizil tugma abadiy spinner bo'lib
      // qolardi va boshqa bosilmasdi.
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Splatni serverdagi Spark viewer'ida ochadi (qulflangan WebView).
  /// Fayl yuklab olinmaydi — viewer uni o'zi oqim bilan o'qiydi.
  Future<void> _openModel() async {
    final model = _model;
    if (model == null) return;
    final url = _v2m.viewerUrlFor(model, title: widget.room.labelUz);
    if (url == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => V2mViewerScreen(
          url: url,
          title: widget.room.labelUz,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return PopScope(
      // Yuklash ketayotganda orqaga chiqish transferni uzadi — ogohlantiramiz.
      canPop: _phase != _Phase.uploading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) AppToast.error(context, _S.uploadHint(l));
      },
      child: Scaffold(
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
                      subtitle: _choice.label(l),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                      children: [
                        _StatusRing(
                          phase: _phase,
                          progress: _ringValue,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _title(l),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            height: 1.25,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _subtitle(l),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 14,
                            height: 1.45,
                            color: subColor,
                          ),
                        ),
                        if (_model?.note != null) ...[
                          const SizedBox(height: 18),
                          _NoteCard(text: _model!.note!, isDark: isDark),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _actions(l, subColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(Locale l, Color subColor) {
    switch (_phase) {
      case _Phase.confirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListingCtaButton(label: _S.confirmUpload(l), onTap: _upload),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _S.later(l),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: subColor,
                ),
              ),
            ),
          ],
        );
      case _Phase.uploading:
        return const SizedBox.shrink();
      case _Phase.waiting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ishlov berish 10-20 daqiqa davom etadi va shu vaqtda qilinadigan
            // eng foydali ish — keyingi xonani olish. Bu bosqichda asosiy
            // tugma o'rni bo'sh turardi, endi o'sha yerda.
            if (widget.allowAddRoom)
              ListingCtaButton(label: _S.addRoom(l), onTap: _addRoom),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _S.close(l),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: subColor,
                ),
              ),
            ),
            _DestructiveButton(
              label: _S.stopJob(l),
              busy: _deleting,
              onTap: _delete,
            ),
          ],
        );
      case _Phase.ready:
        final hasScene = _model?.scene != null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasScene)
              ListingCtaButton(label: _S.openModel(l), onTap: _openModel)
            else
              ListingCtaButton(
                label: _S.close(l),
                onTap: () => Navigator.of(context).pop(),
              ),
            if (widget.allowAddRoom)
              TextButton(
                onPressed: _addRoom,
                child: Text(
                  _S.addRoom(l),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: subColor,
                  ),
                ),
              ),
            _DestructiveButton(
              label: _S.delete(l),
              busy: _deleting,
              onTap: _delete,
            ),
          ],
        );
      case _Phase.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fayl yo'q bo'lsa qayta yuborishga narsa qolmagan.
            if (widget.videoPath != null && !_videoGone)
              ListingCtaButton(label: _S.retry(l), onTap: _upload),
            // Server yiqilgan bo'lsa qayta urinish ham yordam bermaydi —
            // foydalanuvchi qolgan xonalarni olib qo'yib, keyinroq
            // ro'yxatdan birma-bir yuborishi mumkin.
            if (widget.allowAddRoom)
              TextButton(
                onPressed: _addRoom,
                child: Text(
                  _S.addRoom(l),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: subColor,
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _S.close(l),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: subColor,
                ),
              ),
            ),
            // Yiqilgan ish ham serverda joy va yozuv egallaydi — tozalash
            // imkoni bo'lishi kerak.
            if (_modelId != null)
              _DestructiveButton(
                label: _S.delete(l),
                busy: _deleting,
                onTap: _delete,
              ),
          ],
        );
      case _Phase.gone:
        return ListingCtaButton(
          label: _S.close(l),
          onTap: () => Navigator.of(context).pop(),
        );
    }
  }

  /// Halqa qiymati: yuklashda baytlar, ishlov berishda serverning foizi.
  /// Noma'lum bo'lsa null — aylanuvchi (indeterminate) holat.
  double? get _ringValue {
    if (_phase == _Phase.uploading) {
      return _total > 0 ? (_sent / _total).clamp(0.0, 1.0) : null;
    }
    if (_phase == _Phase.ready || _phase == _Phase.gone) return 1;
    final p = _model?.progress ?? 0;
    return p > 0 ? (p / 100).clamp(0.0, 1.0) : null;
  }

  String _title(Locale l) => switch (_phase) {
        _Phase.confirm => _S.confirmTitle(l),
        _Phase.uploading => _S.uploading(l),
        _Phase.waiting => _S.processing(l),
        _Phase.ready =>
          _model?.scene != null ? _S.readyTitle(l) : _S.failedTitle(l),
        _Phase.failed => _S.failedTitle(l),
        _Phase.gone => _S.goneTitle(l),
      };

  String _subtitle(Locale l) {
    switch (_phase) {
      case _Phase.confirm:
        final mb = (_localBytes / (1024 * 1024)).toStringAsFixed(1);
        final size = _localBytes > 0 ? '$mb MB\n' : '';
        return '$size${_S.confirmHint(l)}';
      case _Phase.uploading:
        final mb = (_sent / (1024 * 1024)).toStringAsFixed(1);
        final totalMb = (_total / (1024 * 1024)).toStringAsFixed(1);
        return '$mb / $totalMb MB\n${_S.uploadHint(l)}';
      case _Phase.waiting:
        final model = _model;
        final stage = model == null ? '' : _S.stage(l, model.stage);
        final pct = (model?.progress ?? 0) > 0 ? ' · ${model!.progress}%' : '';
        return '$stage$pct\n${_S.processingHint(l)}';
      case _Phase.ready:
        final scene = _model?.scene;
        return scene == null ? _S.noScene(l) : scene.sizeLabel;
      case _Phase.failed:
        return _error ?? _S.noScene(l);
      case _Phase.gone:
        return _S.modelMissing(l);
    }
  }
}

class _StatusRing extends StatelessWidget {
  const _StatusRing({
    required this.phase,
    required this.progress,
    required this.isDark,
  });

  final _Phase phase;
  final double? progress;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final failed = phase == _Phase.failed || phase == _Phase.gone;
    final accent = failed ? AppColors.chatRedDeep : AppColors.splashGreen;
    final track = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final icon = switch (phase) {
      _Phase.confirm => Icons.videocam_rounded,
      _Phase.gone => Icons.delete_outline_rounded,
      _Phase.uploading => Icons.cloud_upload_rounded,
      _Phase.waiting => Icons.auto_awesome_rounded,
      _Phase.ready => Icons.view_in_ar_rounded,
      _Phase.failed => Icons.error_outline_rounded,
    };

    return Center(
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(
                value: failed ? 1 : progress,
                strokeWidth: 2.6,
                backgroundColor: track,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Qizil, ikkilamchi tugma: o'chirish / to'xtatish. Asosiy CTA'ning ostida
/// turadi va tasodifan bosilmasligi uchun ataylab tugma emas, matn ko'rinishi.
class _DestructiveButton extends StatelessWidget {
  const _DestructiveButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: busy ? null : onTap,
      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.chatRedDeep,
                ),
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.chatRedDeep,
              ),
            ),
    );
  }
}

/// Serverning sifat ogohlantirishi (SSIM/LPIPS darvozasi) — o'zbekcha yozilgan.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const warn = Color(0xFFE0A12A);
    return Container(
      decoration: BoxDecoration(
        color: warn.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.white : AppColors.textBlack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String appBar(Locale l) => tr(l, 'services.ai.common.brand_title');
  static String uploading(Locale l) => tr(l, 'services.ai.capture.uploading');
  static String uploadHint(Locale l) =>
      tr(l, 'services.ai.capture.upload_hint');
  static String processing(Locale l) => tr(l, 'services.ai.capture.processing');
  static String processingHint(Locale l) =>
      tr(l, 'services.ai.capture.processing_hint');
  static String readyTitle(Locale l) =>
      tr(l, 'services.ai.capture.ready_title');
  static String openModel(Locale l) => tr(l, 'services.ai.capture.open_model');
  static String failedTitle(Locale l) =>
      tr(l, 'services.ai.capture.failed_title');
  static String retry(Locale l) => tr(l, 'services.ai.capture.retry');
  static String close(Locale l) => tr(l, 'services.ai.capture.close');
  static String noScene(Locale l) => tr(l, 'services.ai.capture.no_scene');
  static String videoMissing(Locale l) =>
      tr(l, 'services.ai.capture.video_missing');
  static String confirmTitle(Locale l) =>
      tr(l, 'services.ai.capture.confirm_title');
  static String confirmHint(Locale l) =>
      tr(l, 'services.ai.capture.confirm_hint');
  static String confirmUpload(Locale l) =>
      tr(l, 'services.ai.capture.review_upload');
  static String later(Locale l) => tr(l, 'services.ai.capture.later');
  static String addRoom(Locale l) => tr(l, 'services.ai.capture.add_room');
  static String delete(Locale l) => tr(l, 'common.delete');
  static String keep(Locale l) => tr(l, 'common.cancel');
  static String deleteTitle(Locale l) =>
      tr(l, 'services.ai.capture.delete_title');
  static String deleteBody(Locale l) =>
      tr(l, 'services.ai.capture.delete_body');
  static String cancelTitle(Locale l) =>
      tr(l, 'services.ai.capture.cancel_title');
  static String cancelBody(Locale l) =>
      tr(l, 'services.ai.capture.cancel_body');
  static String stopJob(Locale l) => tr(l, 'services.ai.capture.stop_job');
  static String deleted(Locale l) => tr(l, 'services.ai.capture.deleted');
  static String deleteFailed(Locale l) =>
      tr(l, 'services.ai.capture.delete_failed');
  static String goneTitle(Locale l) => tr(l, 'services.ai.capture.gone_title');
  static String modelMissing(Locale l) =>
      tr(l, 'services.ai.capture.model_missing');

  /// v2m `stage` qiymatini o'zbekchaga o'giradi; noma'lum bo'lsa xom qiymat.
  static String stage(Locale l, String stage) {
    if (stage.isEmpty) return '';
    final key = 'services.ai.capture.stage_$stage';
    final label = tr(l, key);
    return label == key ? stage : label;
  }
}
