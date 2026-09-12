/// Fonda tikilayotgan 360° panoramalarni kuzatadi.
///
/// NEGA BOR. Tikish prodda **7–9 daqiqa** oladi (o'lchangan: 420…567 s), va
/// foydalanuvchi buni ekranda kutib o'tirmaydi — capture ekrani kadrlar
/// yuborilishi bilan yopiladi. Kimdir esa natijani kutib olishi kerak: shu
/// sinf ishlarni so'rab turadi va tayyor bo'lganini qoralamaga yozadi.
///
/// ⚠️ BITTA NUSXA (`instance`). Sehrgarning har qadami ALOHIDA marshrut va
/// hammasi stack'da tirik qoladi — har biri o'z kuzatuvchisini yaratsa
/// bitta ish uchun yetti parallel so'rov ketardi.
///
/// ⚠️ QORALAMAGA YOZADI va uni SAQLAYDI. Ilova yopilib ochilsa kuzatuv
/// qoralamadagi `pendingPanoramas` dan davom etadi; saqlamasak `job:<id>`
/// havolasi qolib, uni hech kim haqiqiy kalitga almashtirmasdi va e'lon
/// abadiy yuborib bo'lmas holga tushardi.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/i18n/app_translations.dart';
import '../../panorama/data/pano_api.dart';
import '../../settings/settings_state.dart' show localeNotifier;
import '../models/bozor_draft.dart';
import 'bozor_draft_store.dart';

class PanoJobWatcher extends ChangeNotifier with WidgetsBindingObserver {
  PanoJobWatcher({
    PanoApi? api,
    this.interval = const Duration(seconds: 12),
    this.deadline = const Duration(minutes: 45),
    void Function(BozorDraft draft, WizardStep reached)? save,
  }) : _api = api ?? PanoApi(),
       _save = save ?? saveBozorDraftInBackground;

  /// Qoralamani saqlash.
  ///
  /// ⚠️ TASHQARIDAN BERILADI. Sukut bo'yicha `saveBozorDraftInBackground`,
  /// lekin u `shared_preferences` ga boradi — ya'ni tashqaridan
  /// berilmasa bu sinfni sof birlik testi bilan sinab bo'lmasdi.
  final void Function(BozorDraft draft, WizardStep reached) _save;

  /// Ilova bo'yicha yagona nusxa.
  static final PanoJobWatcher instance = PanoJobWatcher();

  final PanoApi _api;

  /// So'rash oralig'i.
  ///
  /// 12 s: tikish daqiqalar bilan o'lchanadi, ya'ni tez-tez so'rashning
  /// ma'nosi yo'q — u faqat batareya va trafik yeydi.
  final Duration interval;

  /// Shundan oshgan ish YIQILGAN deb belgilanadi.
  ///
  /// Eng uzun o'lchangan tikish 567 s. 45 daqiqa — undan ~5 barobar, ya'ni
  /// navbatda bir necha ish tursa ham yetadi. Chegarasiz qoldirsak,
  /// worker o'lgan holatda foydalanuvchi e'lonini abadiy yubora olmasdi.
  final Duration deadline;

  BozorDraft? _draft;
  WizardStep _reached = WizardStep.description;
  Timer? _timer;

  /// Ketayotgan so'rov.
  ///
  /// ⚠️ Ilgari bu yerda oddiy `bool _busy` turardi va [poll] band bo'lsa
  /// DARHOL qaytardi. Natijada uni KUTGAN chaqiruvchi yolg'on «tugadi»
  /// olardi: `watch()` o'zi bitta so'rovni boshlaydi, keyin darhol
  /// `await poll()` qilingan joy hech narsa kutmasdan o'tib ketardi.
  /// Endi ikkinchi chaqiruv o'sha so'rovning O'ZINI kutadi.
  Future<void>? _inFlight;

  /// Endigina tayyor bo'lganlar — lenta shulardan o'qiydi.
  final List<String> _justReady = [];

  bool get hasPending => (_draft?.description.pendingPanoramas.isNotEmpty) ?? false;

  /// Lentani ko'rsatgach chaqiriladi — ro'yxat tozalanadi.
  List<String> takeReady() {
    final out = List<String>.from(_justReady);
    _justReady.clear();
    return out;
  }

  /// Qoralamani kuzatishga oladi. Bir necha marta chaqirilishi xavfsiz.
  void watch(BozorDraft draft, {WizardStep reached = WizardStep.description}) {
    _reached = reached;
    if (!identical(_draft, draft)) {
      _draft = draft;
      _justReady.clear();
    }
    _sync();
  }

  void _sync() {
    if (!hasPending) {
      _timer?.cancel();
      _timer = null;
      WidgetsBinding.instance.removeObserver(this);
      return;
    }
    if (_timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => unawaited(poll()));
    unawaited(poll());
  }

  /// Ilova fondan qaytdi — darhol so'raymiz.
  ///
  /// iOS/Android ilova fonda turganda taymerni to'xtatadi, ya'ni qaytganda
  /// keyingi tik kutilsa foydalanuvchi 12 sekund eski holatni ko'rardi.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(poll());
  }

  /// Hamma kutilayotgan ishni bir marta so'raydi.
  ///
  /// Allaqachon so'rov ketayotgan bo'lsa — O'SHANI qaytaradi.
  Future<void> poll() => _inFlight ??= _pollOnce().whenComplete(() {
    _inFlight = null;
  });

  Future<void> _pollOnce() async {
    final draft = _draft;
    if (draft == null) return;
    final pending = Map<String, PendingPano>.from(
      draft.description.pendingPanoramas,
    );
    if (pending.isEmpty) {
      _sync();
      return;
    }

    var changed = false;
    for (final entry in pending.entries) {
      // Yiqilganini qayta so'ramaymiz — qayta urinish ATAYLAB qo'lda
      // (foydalanuvchi qatordagi tugmani bosadi).
      if (entry.value.failed) continue;
      changed = await _refresh(draft, entry.key, entry.value) || changed;
    }

    if (changed) {
      notifyListeners();
      // ⚠️ Saqlash JIM va bloklamaydi (`bozor_draft_store` izohiga qarang).
      _save(draft, _reached);
      _sync();
    }
  }

  /// Bitta ishni so'raydi. Qoralama o'zgargan bo'lsa `true`.
  Future<bool> _refresh(BozorDraft draft, String ref, PendingPano p) async {
    PanoJob job;
    try {
      job = await _api.status(p.jobId);
    } on Object {
      // Tarmoq uzilishi kuzatuvni to'xtatmaydi — keyingi tikda qayta
      // so'raladi. Faqat muddat o'tgan bo'lsa voz kechamiz.
      return _expire(draft, ref, p);
    }

    final d = draft.description;
    if (job.isDone && (job.storageKey ?? '').isNotEmpty) {
      final key = job.storageKey!;
      // ⚠️ O'RNIGA QO'YAMIZ, oxiriga qo'shmaymiz: foydalanuvchi panoramalar
      // TARTIBINI ko'rib turibdi va tur havolalari ham shu tartibga
      // tayanadi.
      final i = d.panoramas.indexOf(ref);
      if (i >= 0) {
        d.panoramas[i] = key;
      } else {
        d.panoramas.add(key);
      }
      d.panoramaUrls.remove(ref);
      d.panoramaUrls[key] = job.url ?? '';
      // Busiz `bozor_submit` kalitni fayl yo'li deb bilib yuklashga
      // urinadi va e'lon yiqiladi.
      d.uploadedMedia[key] = key;
      d.pendingPanoramas.remove(ref);
      _justReady.add(key);
      return true;
    }

    if (job.isError) {
      d.pendingPanoramas[ref] = p.withError(
        (job.error ?? '').isNotEmpty ? job.error! : 'xato',
      );
      return true;
    }

    return _expire(draft, ref, p);
  }

  /// Muddat o'tgan bo'lsa ishni yiqilgan deb belgilaydi.
  bool _expire(BozorDraft draft, String ref, PendingPano p) {
    if (DateTime.now().difference(p.startedAt) < deadline) return false;
    draft.description.pendingPanoramas[ref] = p.withError(
      tr(localeNotifier.value, 'bozor.pano.flow.timeout'),
    );
    return true;
  }

  /// Kuzatuvni to'xtatadi (sehrgardan chiqilganda).
  void release(BozorDraft draft) {
    if (!identical(_draft, draft)) return;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _draft = null;
    _justReady.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
