import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Splash — oldindan render qilingan intro roligi (ovoz bilan).
///
/// `assets/branding/splash/intro.mp4` — 720×1680 (9:21), 5.5s, h264 + AAC.
/// Sahna [BlueprintSplashScreen] dagi bilan bir xil g'oya (lockup paydo
/// bo'ladi → neon uy o'zini chizadi), faqat bu safar tayyor video sifatida.
///
/// Eski splash ekranlari ([BlueprintSplashScreen], [AnimatedSplashScreen])
/// O'CHIRILMAGAN — main.dart dagi bitta konstanta bilan qaytariladi.
///
/// ## Yashil chaqnash yo'q
/// Rolik ilova ochilishi bilan DARHOL boshlanishi kerak. Shuning uchun OS
/// launch screen'i ham [launchColor] ga bo'yalgan (iOS: LaunchScreen.storyboard,
/// Android: drawable/launch_background.xml va values-v31/styles.xml) — eski
/// yashil (#00E135) naqshli ekran olib tashlandi. Flutter tomonda ham xuddi
/// shu rang fon bo'lib turadi, shuning uchun native → Flutter → video
/// o'tishlarining hech biri ko'zga tashlanmaydi.
///
/// ## Nega ekranda "letterbox" chizig'i yo'q
/// Manba rolik 9:16 edi, telefonlar esa 9:19.5 gacha uzun. Ikkala oddiy yo'l
/// ham yomon chiqardi:
///   * "cover" — har chetdan ~11% qirqilib, o'ngdagi uy va daraxtlar kesilardi;
///   * "contain" + fon rangi — tepa/pastda tasma qolardi, va u tasma videoga
///     MOS TUSHMASDI: iOS videoni va Flutter ning solid rangini bir xil rang
///     profilidan o'tkazmaydi, shuning uchun rangni qo'lda tanlash bilan chok
///     baribir ko'rinib turardi.
///
/// Yechim asset darajasida: rolikning O'ZI 9:21 gacha kengaytirilgan —
/// tepa va past chetlari 200px dan "smear" (chekka qatorni davom ettirish)
/// bilan cho'zilgan (`ffmpeg -vf "pad=720:1680:0:200,fillborders=...
/// mode=smear"`). Endi bo'sh joy ham VIDEO ning o'zi, ya'ni bitta rang
/// quvuridan o'tadi va chok fizik jihatdan mumkin emas. Shuning uchun bu
/// yerda [BoxFit.cover] ishlatiladi:
///   * 16:9 ekranda — aynan kengaytirilgan qismi qirqiladi, kompozitsiya butun;
///   * 19.5:9 (iPhone) — kengaytirilganning bir qismi qirqiladi, butun;
///   * 21:9 — tep-tekis tushadi.
class VideoSplashScreen extends StatefulWidget {
  const VideoSplashScreen({super.key, required this.onComplete});

  /// Rolikning eng qorong'i cheti. Video ostidagi fon, shuningdek OS launch
  /// screen'ining rangi (iOS: LaunchScreen.storyboard, Android:
  /// drawable/launch_background.xml + values-v31/styles.xml) — hammasi bir xil
  /// bo'lgani uchun ilova ochilganda hech qanday chaqnash ko'rinmaydi.
  /// main.dart splash konteynerini ham shu rangga bo'yaydi.
  static const Color launchColor = Color(0xFF040E07);

  final VoidCallback onComplete;

  @override
  State<VideoSplashScreen> createState() => _VideoSplashScreenState();
}

class _VideoSplashScreenState extends State<VideoSplashScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _asset = 'assets/branding/splash/intro.mp4';

  /// Birinchi video kadri fon rangi ustida bilinmay ochilsin — launch screen
  /// bilan rang bir xil bo'lgani uchun bu deyarli sezilmaydi, lekin kadrning
  /// "sakrab" chiqishini yumshatadi.
  static const Duration _fadeIn = Duration(milliseconds: 180);

  /// Rolik yuklanmasa (asset buzuq, kodek yo'q) splash qotib qolmasin.
  static const Duration _bootTimeout = Duration(seconds: 4);

  /// Rolik tugagach oxirgi kadr shuncha turadi — uy to'liq chizilgan holda
  /// ko'zga tashlanib ulgursin, keyin ilovaga o'tiladi.
  static const Duration _holdLastFrame = Duration(seconds: 1);

  /// Ijro qandaydir sababga ko'ra to'xtab qolsa ham ilova ochiladi.
  static const Duration _playSlack = Duration(seconds: 2);

  VideoPlayerController? _controller;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeT;

  Timer? _bootWatchdog;
  Timer? _playWatchdog;
  Timer? _holdTimer;
  bool _ready = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fadeCtrl = AnimationController(vsync: this, duration: _fadeIn);
    _fadeT = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _bootWatchdog = Timer(_bootTimeout, () {
      if (!_ready) _finish();
    });
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final controller = VideoPlayerController.asset(
      _asset,
      // Foydalanuvchining musiqasini uzib qo'ymaymiz — intro uning ustidan
      // aralashib chiqadi. (iOS tomonda audio sessiya AppDelegate'da
      // `.ambient` qilib qo'yilgan: jimlik tugmasi hurmat qilinadi.)
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
    } catch (_) {
      _finish();
      return;
    }
    if (!mounted || _finished) return;

    controller.addListener(_handleTick);
    await controller.setLooping(false);
    await controller.setVolume(1);
    if (!mounted || _finished) return;

    _bootWatchdog?.cancel();
    _playWatchdog = Timer(
      controller.value.duration + _holdLastFrame + _playSlack,
      _finish,
    );
    setState(() => _ready = true);
    unawaited(controller.play());
    _fadeCtrl.forward();
    // Ikki zarbdan birinchisi — rolik boshlandi.
    HapticFeedback.lightImpact();
  }

  /// Rolik oxiriga yetdi (yoki xato berdi) — ilovaga o'tamiz.
  void _handleTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      _finish();
      return;
    }
    // Normal tugash — oxirgi kadr [_holdLastFrame] davomida ekranda qoladi.
    // (Ekranga bosish bu kutishni ham kesib o'tadi.) `_holdTimer` bir martalik
    // qo'riqchi: `isCompleted` har bir tick'da rost bo'lib turadi.
    if (controller.value.isCompleted && _holdTimer == null) {
      // Ikkinchi zarb — uy chizilib bo'ldi.
      HapticFeedback.mediumImpact();
      _holdTimer = Timer(_holdLastFrame, _finish);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fonga chiqqanda plugin ijroni to'xtatadi — qaytganda davom ettiramiz,
    // aks holda splash faqat watchdog bilan yopilardi.
    if (state != AppLifecycleState.resumed || _finished || !_ready) return;
    final controller = _controller;
    if (controller == null || controller.value.isCompleted) return;
    unawaited(controller.play());
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _bootWatchdog?.cancel();
    _playWatchdog?.cancel();
    _holdTimer?.cancel();
    // Ovoz keyingi ekranga "sudralib" o'tmasin.
    unawaited(_controller?.pause() ?? Future<void>.value());
    if (mounted) widget.onComplete();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bootWatchdog?.cancel();
    _playWatchdog?.cancel();
    _holdTimer?.cancel();
    _controller?.removeListener(_handleTick);
    unawaited(_controller?.dispose() ?? Future<void>.value());
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = _ready && controller != null && controller.value.isInitialized;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Sahna qorong'i — status bar belgilari oq bo'lishi kerak (ilovaning
      // light mavzusida ular qora bo'lib, fonda yo'qolib ketardi).
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness: Brightness.dark, // iOS
        systemNavigationBarColor: VideoSplashScreen.launchColor,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: GestureDetector(
        // Introni o'tkazib yuborish — 5.5 soniya har startda uzun tuyulishi
        // mumkin, ekranning istalgan joyiga bosish yetarli.
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: ColoredBox(
          // Launch screen bilan bir xil rang — o'tish ko'rinmaydi.
          color: VideoSplashScreen.launchColor,
          child: FadeTransition(
            opacity: _fadeT,
            child: SizedBox.expand(
              child: ready
                  ? SizedBox.expand(
                      // Rolik 9:21 — ekrandan uzunroq, shuning uchun "cover"
                      // faqat kengaytirilgan chetlarini yeydi. Cho'zilish yo'q
                      // (nisbat saqlanadi) va bo'sh tasma ham yo'q.
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
