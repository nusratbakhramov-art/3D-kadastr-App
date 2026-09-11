/// 360° panorama suratga olish ekrani.
///
/// Foydalanuvchi bir joyda turib aylanadi; ekran keyingi kadr QAYERDA
/// ekanini devorga aylana qo'yib ko'rsatadi va telefon nishonda
/// qimirlamay turganda zatvorni O'ZI ochadi. Hamma majburiy kadr
/// olingach «Tayyor» tugmasi chiqadi; qutb (zenit/nadir) kadrlari
/// ixtiyoriy va ulardan keyin tikish avtomatik boshlanadi.
///
/// ⚠️ DOIRA. Bu ekran ilovaning MAVJUD kodiga TEGMAYDI. Kameraga
/// egalik ziddiyati (AI Baholash skani va videosi ham kamerani ochadi)
/// SHU YERDA, panorama tomonidan hal qilinadi: ekran ochilishdan oldin
/// [CameraGuard] dan ijara so'raydi va band bo'lsa umuman ochilmaydi.
///
/// Narxi ochiq aytiladi: bu FAQAT bir tomonni yopadi. Panorama ochiq
/// turganda AI Baholash kamerani so'rasa, u guard'ni ko'rmaydi va
/// ziddiyat baribir yuzaga keladi. Uni yopish uchun mavjud fayllarga
/// tegish SHART — va u paytda FOYDALANUVCHIDAN SO'RALADI.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/i18n/app_translations.dart';
import '../../settings/settings_state.dart' show localeNotifier;
import '../../../theme/app_colors.dart';
import '../data/camera_guard.dart';
import '../data/capture_log.dart';
import '../data/heading_source.dart';
import '../models/capture_guidance.dart';
import '../models/capture_ring.dart';
import '../models/pano_progress.dart';
import '../models/sensor_shot.dart';
import '../models/stitch_outcome.dart';
import '../stitch/dart_stitcher.dart';
import '../stitch/image_frame_loader.dart';
import '../stitch/work_dir.dart';
import '../widgets/ring_dial.dart';
import '../widgets/target_overlay.dart';

/// Preview o'zining UZUN tomoni bo'ylab qamraydigan ko'rish burchagi.
///
/// Tikuvchi kadr geometriyasini AYNAN shu sondan chiqaradi — nishon kadr
/// sferada haqiqatan qayerga tushishi bilan kelishishi shart. Preview va
/// tayyor surat bu rezolyutsiyada bir xil sensor sohasi, ya'ni bitta son
/// ikkalasiga ham xizmat qiladi.
const double kPreviewFovDeg = 67.3;

/// Ekspozitsiyaning IKKI TOMONIDAGI yo'nalishlarning o'rtasi.
///
/// Zatvorni ochgan yo'nalish undan OLDIN o'qilgan, `takePicture` esa bir
/// necha yuz millisekundda qaytadi. Telefon shu vaqtda qimirlashda davom
/// etadi, ya'ni triggerning burchagini yozish yorug'lik kelishidan
/// biroz OLDINGI holatni yozish bo'lardi. Ikki o'qishni o'rtachalash
/// ekspozitsiyani QAMRAB oladi.
///
/// ⚠️ Yaw QISQA yo'l bilan o'rtachalanadi. Oddiy o'rtacha 359 va 1 uchun
/// 180 berardi — kadr sferaning QARAMA-QARSHI tomoniga tushardi.
DeviceAim atShutter(DeviceAim before, DeviceAim? after) {
  if (after == null) return before;
  final double delta = ((after.yawDeg - before.yawDeg + 540) % 360) - 180;
  return DeviceAim(
    yawDeg: (before.yawDeg + delta / 2 + 360) % 360,
    pitchDeg: (before.pitchDeg + after.pitchDeg) / 2,
    rollDeg: (before.rollDeg + after.rollDeg) / 2,
    rawDeviceRollDeg: (before.rawDeviceRollDeg + after.rawDeviceRollDeg) / 2,
    // Zatvor ochilgan payt qimirlamagan bo'lsa, keyin qimirlagani kadrni
    // bekor qilmaydi.
    steady: before.steady,
  );
}

/// Olingan tasvirning KO'RSATILADIGAN o'lchami: portret, chunki
/// [CameraController.lockCaptureOrientation] uni shunga qotirgan.
/// `previewSize` esa telefon nima qilayotganidan qat'i nazar sensorning
/// o'z LANDSHAFT o'qishini beradi.
Size imageSizeOf(CameraController camera) {
  final Size? p = camera.value.previewSize;
  if (p == null) return const Size(3, 4);
  return Size(math.min(p.width, p.height), math.max(p.width, p.height));
}

/// Tikish bosqichi uchun i18n kaliti.
///
/// ⚠️ Bosqich nomi kalitga DINAMIK qo'shiladi, ya'ni yetishmagan kalit
/// kompilyatsiya xatosi BERMAYDI — ekranda xom kalit ko'rinadi. Sof
/// funksiya sifatida ajratilgani shu uchun: `pano_capture_screen_test`
/// har bosqich uchun kalit borligini tekshiradi.
String stitchLabelKey(StitchPhase? phase) =>
    'bozor.pano.stitch.${(phase ?? StitchPhase.decode).name}';

enum _Stage { starting, shooting, stitching, failed }

class PanoCaptureScreen extends StatefulWidget {
  const PanoCaptureScreen({super.key});

  @override
  State<PanoCaptureScreen> createState() => _PanoCaptureScreenState();
}

class _PanoCaptureScreenState extends State<PanoCaptureScreen>
    with WidgetsBindingObserver {
  final CaptureRing _ring = CaptureRing();
  final HeadingSource _heading = HeadingSource();

  /// Olingan kadr fayllari.
  final Map<ShotId, String> _shots = <ShotId, String>{};

  /// Har kadr uchun telefon qayerga qaragan — tikuvchi shundan
  /// joylashtiradi, fayl nomidan EMAS.
  final Map<ShotId, DeviceAim> _aims = <ShotId, DeviceAim>{};

  CameraController? _camera;
  StitchWorkDir? _workDir;
  Directory? _shotsDir;

  /// Burchaklar yozuvi — har kadrdan keyin diskka.
  CaptureLog? _log;

  _Stage _stage = _Stage.starting;
  String? _error;
  PanoProgress? _progress;
  bool _holdsGuard = false;

  /// `takePicture()` uchayotgan chaqiruv ustiga chaqirilsa istisno
  /// tashlaydi, yo'nalish nasosi esa sekundiga 30 marta uradi — shuning
  /// uchun har kadr shu darvozadan o'tadi.
  bool _busy = false;

  /// Oxirgi zenit/nadir kadri qachon olingan.
  ///
  /// Qutb kadrlari FAQAT pitch bo'yicha nazorat qilinadi — tik yuqorida
  /// yaw ma'nosiz — ya'ni busiz uchalasi telefon qutbga yetib
  /// qimirlamay turishi bilan BIRDANIGA otilardi va bitta kadrning uch
  /// nusxasi chiqardi. Ular hech narsa qo'shmaydi: qutbda rasmni
  /// o'zgartiradigan narsa — BURILISH. Oraliq qo'yish foydalanuvchiga
  /// burilishga joy beradi, ekrandagi yo'riqnoma aynan shuni so'raydi.
  DateTime? _lastPoleShot;
  static const Duration _poleInterval = Duration(milliseconds: 1400);

  Locale get _l => localeNotifier.value;
  String _t(String key) => tr(_l, key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heading.aim.removeListener(_onAim);
    _heading.dispose();
    unawaited(_camera?.dispose());
    if (_holdsGuard) CameraGuard.release(CameraGuard.panorama);
    // Ish papkasi tikishdan KEYIN o'chiriladi; ekran yopilganda esa
    // qoldiq qolmasin.
    unawaited(_workDir?.dispose());
    super.dispose();
  }

  /// Kamera plagini hayot siklini O'ZI boshqarmaydi — jonli kontrollerni
  /// qoldirib ketish «used after being disposed» yiqilishini beradi.
  ///
  /// ⚠️ Bu yerda `inactive` ham fonga tushish deb qaraladi va bu
  /// `CameraGuard` ning siyosatidan ATAYLAB farq qiladi (u `inactive` ni
  /// e'tiborsiz qoldiradi, chunki iOS'da bildirishnoma pardasi ham shuni
  /// beradi). Sabab: guard uchun erta bo'shatish arzon, kamera uchun esa
  /// jonli sessiyani qoldirib ketish qimmat — iOS uni baribir uzadi va
  /// qaytganda kontroller o'lik bo'ladi.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _camera = null;
      unawaited(camera.dispose());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_openCamera());
    }
  }

  Future<void> _start() async {
    // ⚠️ IJARA BIRINCHI. Kamerani ochishdan oldin so'raladi — aks holda
    // AI Baholash skani ochiq turganda ikkinchi sessiya ochilib iOS'da
    // ikkalasi ham qotardi.
    if (!CameraGuard.acquire(CameraGuard.panorama)) {
      _fail(_t('bozor.pano.err.camera_busy'));
      return;
    }
    _holdsGuard = true;

    try {
      final Directory parent = await getApplicationDocumentsDirectory();
      await StitchWorkDir.purgeStale(parent);

      // ⚠️ `purgeStale` dan KEYIN: eskirgani allaqachon o'chirilgan
      // bo'lishi kerak, aks holda ekran o'chirilishi lozim bo'lgan
      // sessiyani taklif qilardi.
      //
      // ⚠️ HOZIRGI papka CHETLATILADI. `_retry` shu yerga qaytadi, va
      // usiz ekran aynan hozir yiqilgan sessiyani «yig'aylikmi?» deb
      // taklif qilardi — u esa xuddi shu tarzda yana yiqilardi.
      final StrandedCapture? stranded = await findStranded(
        parent,
        exclude: _workDir?.dir,
      );
      if (stranded != null && mounted && await _offerResume(stranded)) {
        await _resume(stranded);
        return;
      }

      final wd = await StitchWorkDir.create(parent);
      _workDir = wd;
      _shotsDir = await Directory(
        '${wd.path}/$kShotsDirName',
      ).create(recursive: true);
      _log = CaptureLog(wd.dir);

      await _openCamera();
      _heading.start();
      _heading.aim.addListener(_onAim);
      if (mounted) setState(() => _stage = _Stage.shooting);
    } on Object catch (e) {
      _fail('${_t('bozor.pano.err.camera_open')}: $e');
    }
  }

  /// Tashlab ketilgan suratga olishni yig'ishni TAKLIF qiladi.
  ///
  /// So'raladi, o'z-o'zidan qilinmaydi: foydalanuvchi bu ekranga yangi
  /// panorama olish uchun kelgan bo'lishi mumkin, va uning o'rniga
  /// eskisini yig'ib berish — u so'ramagan ish.
  Future<bool> _offerResume(StrandedCapture stranded) async {
    final int n = stranded.shots.length;
    // Burchaklar fayl nomlaridan tiklangan bo'lsa buni AYTAMIZ: natija
    // bir-ikki gradus xato bo'ladi va foydalanuvchi buni tikishdan oldin
    // bilishi kerak, keyin emas.
    final String body =
        _t(
          stranded.source == AimSource.recorded
              ? 'bozor.pano.resume.body'
              : 'bozor.pano.resume.body_approx',
        ).replaceAll('{n}', '$n');

    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(_t('bozor.pano.resume.title')),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t('bozor.pano.resume.no')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t('bozor.pano.resume.yes')),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  /// Tashlab ketilgan kadrlarni yig'adi — kamerasiz.
  Future<void> _resume(StrandedCapture stranded) async {
    // Kamera umuman ochilmaydi, ya'ni guard'ni ushlab turishning ma'nosi
    // yo'q: tikish daqiqalab ketadi va shu vaqt ichida AI Baholash
    // skanini bloklab turardi.
    if (_holdsGuard) {
      CameraGuard.release(CameraGuard.panorama);
      _holdsGuard = false;
    }
    _workDir = StitchWorkDir.adopt(stranded.dir);
    await _stitch(shots: stranded.shots);
  }

  Future<void> _openCamera() async {
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      _fail(_t('bozor.pano.err.no_camera'));
      return;
    }
    final CameraDescription back = cameras.firstWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // ⚠️ `enableAudio` sukut bo'yicha ROST, ya'ni u bizga kerak bo'lmagan
    // va so'ramaydigan mikrofon ruxsatini talab qilardi.
    //
    // `ultraHigh` — 3840×2160. Tikuvchi kadrlarni baribir xotira byudjeti
    // uchun kichraytiradi, ya'ni bu yakuniy panoramaga ko'proq piksel
    // BERMAYDI. Beradigani — TOZAROQ piksel: 4K kadrni kichraytirish
    // shovqin va aliasingni o'rtachalab yo'q qiladi, natively-1080p kadr
    // esa ularni saqlab qoladi.
    final CameraController camera = CameraController(
      back,
      ResolutionPreset.ultraHigh,
      enableAudio: false,
    );
    await camera.initialize();

    // Busiz Android har suratda ekran burilishini qayta o'qiydi va bitta
    // sweep bir-biriga mos kelmaydigan orientatsiyali kadrlar berardi.
    await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);

    // Ekspozitsiya, oq balans va fokusni BUTUN sweep uchun qotirish.
    //
    // Avtomatda kamera har kadrni qayta o'lchaydi, xona esa bir tekis
    // yoritilmagan: derazaga qaraganda diafragma yopiladi, devorga
    // qaraganda ochiladi. Bir devorning ikki kadri shunda tikuvchi
    // qaytara oladiganidan ko'proq farq qiladi — kadrga bitta
    // koeffitsiyent yoritilgan joyni QAYTARA OLMAYDI, chunki u yerdagi
    // detal butunlay yo'qolgan. Haqiqiy capture'da bitta deraza ikki
    // marta chiqqan: birida oynasi ko'rinadi, ikkinchisida oq dog'.
    //
    // Avval JOYLASHISH kutiladi — qotiriladigan narsa sensorning
    // yoqilgandagi tasodifiy o'qishi emas, sahnaning oqilona o'qishi
    // bo'lsin. Fokus ham u bilan qotiriladi: qayta fokuslash ko'rish
    // burchagini biroz o'zgartiradi, bu esa HAR CHOKNI siljitadi.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    for (final Future<void> Function() lock in <Future<void> Function()>[
      () => camera.setExposureMode(ExposureMode.locked),
      () => camera.setFocusMode(FocusMode.locked),
    ]) {
      try {
        await lock();
      } on CameraException {
        // Har qurilma har qulfni bermaydi. Avto — yomonroq, halokatli emas.
      }
    }

    // ⚠️ Ekran yopilgan bo'lsa kontroller MAJBURAN yopiladi. Busiz
    // 600 ms joylashish paytida tez chiqib ketish jonli
    // `AVCaptureSession` ni qoldirib ketardi.
    if (!mounted) {
      await camera.dispose();
      return;
    }
    setState(() => _camera = camera);
  }

  void _onAim() {
    final DeviceAim? aim = _heading.aim.value;
    if (aim == null) return;
    if (_stage != _Stage.shooting || _busy) return;
    final ShotId? due = _ring.dueAt(aim.yawDeg, aim.pitchDeg);
    if (due == null || !aim.steady || !_poleIntervalElapsed(due)) {
      // Nishonda emas, hali qimirlayapti, yoki oxirgi qutb kadridan keyin
      // erta. Kompas strelkasi BARIBIR jonli qoladi — «qimirlamang» va
      // «burilishda davom eting» ikkalasi ham foydalanuvchi ko'rishi
      // kerak bo'lgan holat.
      setState(() {});
      return;
    }
    unawaited(_shoot(aim));
  }

  bool _poleIntervalElapsed(ShotId due) {
    if (!_ring.isPoleRow(due.row)) return true;
    final DateTime? last = _lastPoleShot;
    return last == null || DateTime.now().difference(last) >= _poleInterval;
  }

  Future<void> _shoot(DeviceAim aim) async {
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    final ShotId? shot = _ring.dueAt(aim.yawDeg, aim.pitchDeg);
    final Directory? dir = _shotsDir;
    if (shot == null || dir == null || _busy) return;

    _busy = true;
    try {
      final XFile raw = await camera.takePicture();

      // ⚠️ Zatvorni ochgan yo'nalish undan OLDIN o'qilgan, `takePicture`
      // esa bir necha yuz millisekundda qaytadi. Telefon shu vaqtda
      // qimirlashda davom etadi, ya'ni triggerning burchagini yozish
      // yorug'lik kelishidan biroz OLDINGI holatni yozish bo'lardi. Ikki
      // o'qishni o'rtachalash ekspozitsiyani QAMRAB oladi.
      final DeviceAim shotAim = atShutter(aim, _heading.aim.value);

      // Suratlar plagin hech qachon tozalamaydigan vaqtinchalik keshga
      // tushadi — o'z papkamizga ko'chirib, aslini o'chiramiz.
      //
      // Nom `shotFileName` dan: aynan shu qoidani burchaklarni fayl
      // nomlaridan tiklovchi ham o'qiydi.
      final String dest = '${dir.path}/${shotFileName(shot)}';
      await File(raw.path).copy(dest);
      try {
        await File(raw.path).delete();
      } on FileSystemException {
        // Qolib ketgan vaqtinchalik fayl uchun capture'ni yo'qotishga
        // arzimaydi.
      }

      _shots[shot] = dest;
      _aims[shot] = shotAim;
      _ring.record(shot, shotAim.yawDeg);

      // ⚠️ HOZIR yoziladi, suratga olish oxirida EMAS. Bu burchaklar —
      // telefon qayerga qaraganining yagona yozuvi, tikish esa
      // capture'ning eng uzun va eng noaniq qismi: 76 kadr telefonni
      // daqiqalab band qilishi mumkin. «Qotib qoldi» deb ilovani
      // yopgan foydalanuvchi ilgari butun sessiyaning burchaklarini
      // yo'qotardi — suratlar diskda qolardi va befoyda bo'lardi.
      _log?.write(_sensorShots());

      if (_ring.isPoleRow(shot.row)) _lastPoleShot = DateTime.now();
      if (!mounted) return;
      setState(() {});

      // Olinadigan narsa BUTUNLAY qolmagandagina avtomatik tikiladi.
      // Majburiylari tugagach foydalanuvchi o'zi hal qiladi: qutblarni
      // ham oladimi yoki «Tayyor» ni bosadimi.
      if (_ring.isFullyComplete) unawaited(_stitch());
    } on CameraException catch (e) {
      _fail('${_t('bozor.pano.err.shot')}: ${e.description ?? e.code}');
    } finally {
      _busy = false;
    }
  }

  /// Olingan kadrlar — tikuvchi kutadigan shaklda.
  ///
  /// Bir joyda yig'ilgani sababi: uni IKKI chaqiruvchi ishlatadi —
  /// tikish va har kadrdan keyingi yozuv. Ikki joyda takrorlansa ular
  /// jimgina bir-biridan uzoqlashardi va diskdagi yozuv tikilgan
  /// narsadan boshqa bo'lib qolardi.
  List<SensorShot> _sensorShots() => <SensorShot>[
    for (final MapEntry<ShotId, String> e in _shots.entries)
      SensorShot(
        path: e.value,
        yawDeg: _aims[e.key]!.yawDeg,
        pitchDeg: _aims[e.key]!.pitchDeg,
        // ⚠️ `rollDeg` — LINZA roll'i, xom qurilma roll'i EMAS.
        rollDeg: _aims[e.key]!.rollDeg,
        row: e.key.row,
      ),
  ];

  /// [shots] berilsa AYNAN ular tikiladi (tashlab ketilgan sessiyani
  /// tiklash), aks holda hozirgi sessiyaning kadrlari.
  Future<void> _stitch({List<SensorShot>? shots}) async {
    if (_stage == _Stage.stitching) return;
    final StitchWorkDir? wd = _workDir;
    if (wd == null) return;

    // Kamerani DARHOL bo'shatamiz — tikish bir necha daqiqa olishi
    // mumkin va jonli sessiyani ushlab turishning ma'nosi yo'q.
    final CameraController? camera = _camera;
    _camera = null;
    unawaited(camera?.dispose());
    await _heading.stop();

    setState(() {
      _stage = _Stage.stitching;
      _progress = const PanoProgress(
        phase: StitchPhase.decode,
        done: 0,
        total: 1,
      );
    });

    try {
      final req = StitchRequest(
        shots: shots ?? _sensorShots(),
        workDir: wd,
        longSideFovDeg: kPreviewFovDeg,
      );
      final loader = ImageFrameLoader(
        workDir: wd,
        canvasW: req.canvasW,
        longSideFovDeg: req.longSideFovDeg,
        readBytes: (p) async {
          final f = File(p);
          return f.existsSync() ? f.readAsBytes() : null;
        },
      );

      final String outPath = '${wd.path}/panorama.jpg';
      final outcome = await stitchSensor(
        req,
        loader,
        outputPath: outPath,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        writeOutput: (rgb, w, h) => _writeJpeg(outPath, rgb, w, h),
      );

      if (!mounted) return;
      switch (outcome) {
        case StitchSuccess(:final path):
          // ⚠️ NATIJA ISH PAPKASIDAN CHIQARILADI.
          //
          // Ilgari qoralamaga `<ish papkasi>/panorama.jpg` yo'li
          // berilardi — ya'ni ilovaning O'ZI o'chiradigan papka ichidagi
          // fayl. `purgeStale` capture ekrani har ochilganda 6 soatdan
          // eski `pano_stitch_*` papkalarni o'chiradi, shuning uchun
          // saqlangan qoralamadagi panorama bir kundan keyin jimgina
          // yo'qolardi va faqat «ochib bo'lmadi» bo'lib ko'rinardi.
          final String kept = await _keepOutput(path);
          // Endi papkada kerakli narsa qolmadi: 76 kadr va xom kesh
          // DARHOL bo'shatiladi. Ilgari ular keyingi tozalashgacha
          // yotardi — har panorama uchun yuzlab megabayt.
          final StitchWorkDir? done = _workDir;
          _workDir = null;
          unawaited(done?.dispose());
          if (!mounted) return;
          Navigator.of(context).pop(kept);
        case StitchFailure(:final message):
          _fail(message);
      }
    } on Object catch (e) {
      _fail('${_t('bozor.pano.err.stitch')}: $e');
    }
  }

  /// Tikilgan panoramani BARQAROR joyga ko'chiradi va yangi yo'lni
  /// qaytaradi.
  ///
  /// Qoralama bu yo'lni haftalab saqlashi mumkin — foydalanuvchi e'lonni
  /// bir kunda tugatmaydi. Shuning uchun natija [StitchWorkDir] ning
  /// tozalanadigan hududidan chiqariladi.
  ///
  /// Ko'chirish YIQILSA asl yo'l qaytadi: panorama tayyor va uni
  /// foydalanuvchiga bermaslik — ko'chira olmaslikdan ko'ra battar.
  /// U holda fayl eski joyida qoladi, ya'ni eski xatti-harakat.
  Future<String> _keepOutput(String path) async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory dest = await Directory(
        '${docs.path}/$kPanoramaDirName',
      ).create(recursive: true);
      final String name =
          'pano_${DateTime.now().millisecondsSinceEpoch}_'
          '${path.hashCode.toUnsigned(16).toRadixString(36)}.jpg';
      final File moved = await File(path).copy('${dest.path}/$name');
      try {
        await File(path).delete();
      } on FileSystemException {
        // Asl nusxa qolib ketsa ish papkasi bilan birga o'chadi.
      }
      return moved.path;
    } on Object {
      return path;
    }
  }

  /// Planar RGB → JPEG.
  Future<void> _writeJpeg(String path, Uint8List rgb, int w, int h) async {
    // `package:image` interleaved kutadi; tikuvchi planar beradi.
    final int n = w * h;
    final inter = Uint8List(n * 3);
    for (int i = 0; i < n; i++) {
      inter[i * 3] = rgb[i];
      inter[i * 3 + 1] = rgb[n + i];
      inter[i * 3 + 2] = rgb[2 * n + i];
    }
    final im = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: inter.buffer,
      numChannels: 3,
    );
    // 92 — panorama uchun: 100 fayl hajmini ikki barobar oshiradi, ko'z
    // esa farqni sferada ko'rmaydi.
    await File(path).writeAsBytes(img.encodeJpg(im, quality: 92), flush: true);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _stage = _Stage.failed;
    });
  }

  void _retry() {
    _ring.reset();
    _shots.clear();
    _aims.clear();
    _lastPoleShot = null;
    _busy = false;
    setState(() {
      _error = null;
      _stage = _Stage.starting;
    });
    unawaited(_start());
  }

  /// Keyingi nishon telefon hozir qaragan joydan qanday ko'rinadi.
  TargetSight? _sight() {
    final DeviceAim? aim = _heading.aim.value;
    if (aim == null) return null;
    final next = _ring.nextTarget(aim.yawDeg, aim.pitchDeg);
    if (next == null) return null;
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized) return null;
    final Size img = imageSizeOf(camera);
    return sightTarget(
      yawDeg: aim.yawDeg,
      pitchDeg: aim.pitchDeg,
      targetYawDeg: aim.yawDeg + next.turnDeg,
      targetPitchDeg: aim.pitchDeg + next.tiltDeg,
      imageWidth: img.width,
      imageHeight: img.height,
      longSideFovDeg: kPreviewFovDeg,
      toleranceDeg: _ring.yawToleranceDeg,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Tikish ketayotganda orqaga chiqish natijani yo'qotardi.
      canPop: _stage != _Stage.stitching,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_camera case final CameraController camera
                when camera.value.isInitialized)
              // ⚠️ Aspect-fill OCHIQ e'lon qilinadi, meros olinmaydi.
              // Overlay tasvir pikselini ekran pikseliga AYNAN shu qoida
              // bilan o'giradi (`markerAt` dagi `max(w/iw, h/ih)`), ya'ni
              // preview ham shu bilan masshtablansagina nishon
              // foydalanuvchi qarab turgan narsaga tushadi.
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: imageSizeOf(camera).width,
                    height: imageSizeOf(camera).height,
                    child: CameraPreview(camera),
                  ),
                ),
              )
            else
              const ColoredBox(color: Colors.black),

            if (_stage == _Stage.shooting && _camera != null)
              TargetOverlay(
                sight: _sight(),
                imageSize: imageSizeOf(_camera!),
                stability: _heading.aim.value?.steadyProgress ?? 0,
              ),

            // ⚠️ Kompas va banner overlay'dan KEYIN — ya'ni ular
            // USTIDAN chiziladi. Manbada ham shunday.
            if (_stage == _Stage.shooting) _shootingOverlay(),
            if (_stage == _Stage.shooting && _ring.isComplete) _finishBar(),
            if (_stage == _Stage.stitching) _working(),
            if (_stage == _Stage.failed) _errorOverlay(),

            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _stage == _Stage.stitching
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shootingOverlay() {
    final DeviceAim? aim = _heading.aim.value;
    final next = aim == null
        ? null
        : _ring.nextTarget(aim.yawDeg, aim.pitchDeg);

    // ⚠️ `pitchToleranceDeg` (4°), `polePitchToleranceDeg` (25°) EMAS.
    // Bu qaysi yo'riqnoma ko'rsatilishini hal qiladi.
    final bool needsTilt =
        next != null && next.tiltDeg.abs() > _ring.pitchToleranceDeg;

    String instruction;
    if (aim == null) {
      instruction = _t('bozor.pano.hint.sensor');
    } else if (next == null) {
      instruction = _t('bozor.pano.hint.done');
    } else if (needsTilt) {
      // ⚠️ Qator INDEKSIGA emas, PITCH ishorasiga qarab hal qilinadi.
      // Manbada `target.shot.row == 3` yozilgan edi va qatorlar tartibi
      // o'zgarsa matn jimgina teskari bo'lardi.
      instruction = _ring.rows[next.shot.row].pitchDeg > 0
          ? _t('bozor.pano.hint.up')
          : _t('bozor.pano.hint.down');
    } else {
      instruction = _t('bozor.pano.hint.turn');
    }

    return SafeArea(
      child: Column(
        children: <Widget>[
          const SizedBox(height: 56),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  instruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          RingDial(
            ring: _ring,
            relativeYaw: aim == null
                ? 0
                : (_ring.relativeYaw(aim.yawDeg) ?? 0),
            activeRow: aim == null ? null : _ring.rowAt(aim.pitchDeg),
          ),
          const SizedBox(height: 8),
          Text(
            '${_ring.takenCount} / ${_ring.requiredShots}',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _finishBar() {
    final int extra = _ring.takenCount - _ring.requiredShots;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                extra > 0
                    ? '${_t('bozor.pano.finish.extra')}: $extra'
                    : _t('bozor.pano.finish.enough'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.splashGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  onPressed: () => unawaited(_stitch()),
                  child: Text(
                    _t('bozor.pano.finish.cta'),
                    style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _working() {
    final PanoProgress? p = _progress;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                value: p?.overall,
                backgroundColor: Colors.white24,
                color: AppColors.splashGreen,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _t(stitchLabelKey(p?.phase)),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${((p?.overall ?? 0) * 100).round()} %',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorOverlay() => ColoredBox(
    color: Colors.black.withValues(alpha: 0.9),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.white, size: 40),
            const SizedBox(height: 12),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _retry,
              child: Text(_t('bozor.pano.err.retry')),
            ),
          ],
        ),
      ),
    ),
  );
}
