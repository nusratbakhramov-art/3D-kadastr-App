import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Splash — oldindan render qilingan intro roligi (ovozsiz).
///
/// `assets/branding/splash/intro-black.mp4` — 1280×720 (16:9), 3.1s, 30fps,
/// h264, audio YO'Q. Sahna: qop-qora fonda ilova belgisi o'zini chizadi.
///
/// Manba mijozdan 2560×1440 60fps 5s (3.4 MB) holida keldi. Ikki narsa
/// o'zgartirildi: (1) o'lcham yarmiga tushirildi — ekranda eni bo'yicha
/// ~1200px dan oshmaydi; (2) OXIRI KESILDI — animatsiya 3.05s da tugab,
/// qolgan 1.95s da qimirlamas belgi turardi, ya'ni splash shuncha vaqt
/// "o'lik" qotib qolardi. Natija: 55 KB.
///
/// Eski splash ekranlari ([BlueprintSplashScreen], [AnimatedSplashScreen]) va
/// eski rolik (`intro.mp4`) O'CHIRILMAGAN — main.dart dagi bitta konstanta
/// bilan qaytariladi.
///
/// ## Chaqnash yo'q
/// Rolik ilova ochilishi bilan DARHOL boshlanishi kerak. Shuning uchun OS
/// launch screen'i ham [launchColor] ga bo'yalgan (iOS: LaunchScreen.storyboard,
/// Android: drawable/launch_background.xml va values-v31/styles.xml). Yangi
/// rolikning foni sof qora (#000000) — launch screen, Flutter foni va videoning
/// o'zi bitta rang, ya'ni o'tishlar ko'rinmaydi.
///
/// ## Nega [BoxFit.contain]
/// Rolik ENI bo'yicha uzun (16:9), telefon esa bo'yiga. `cover` bilan u
/// balandlikka cho'zilib, enining ~70% i qirqilardi va belgi ekranni to'ldirib
/// yuborardi. `contain` da rolik ekran ENIGA tushadi, belgi esa kadrdagi
/// ulushini (eni bo'yicha ~30%) saqlaydi. Tepa-pastdagi bo'sh joy ko'rinmaydi:
/// u ham, rolikning foni ham bir xil qora.
class VideoSplashScreen extends StatefulWidget {
  const VideoSplashScreen({super.key, required this.onComplete});

  /// Rolik foni — SOF QORA, va shundayligicha qolishi kerak. Video ostidagi
  /// fon, OS launch screen'ining rangi (iOS: LaunchScreen.storyboard, Android:
  /// drawable/launch_background.xml + values-v31/styles.xml) va main.dart
  /// dagi splash konteyneri — hammasi shu rang. Boshqa qiymat qo'yilsa,
  /// rolikning cheti ko'rinib qoladi.
  static const Color launchColor = Color(0xFF000000);

  final VoidCallback onComplete;

  @override
  State<VideoSplashScreen> createState() => _VideoSplashScreenState();
}

class _VideoSplashScreenState extends State<VideoSplashScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _asset = 'assets/branding/splash/intro-black.mp4';

  /// Birinchi video kadri fon rangi ustida bilinmay ochilsin — launch screen
  /// bilan rang bir xil bo'lgani uchun bu deyarli sezilmaydi, lekin kadrning
  /// "sakrab" chiqishini yumshatadi.
  static const Duration _fadeIn = Duration(milliseconds: 180);

  /// Rolik yuklanmasa (asset buzuq, kodek yo'q) splash qotib qolmasin.
  static const Duration _bootTimeout = Duration(seconds: 4);

  /// Rolik tugagach oxirgi kadr shuncha turadi — belgi to'liq chizilgani
  /// ko'zga tashlanib ulgursin, keyin ilovaga o'tiladi.
  ///
  /// ⚠️ Ikki tomonga ham xato qilish oson — bu qiymat ikkalasi orasidagi
  /// o'rta nuqta:
  ///  • Manba rolikda animatsiya 3.05s da tugab, keyin 1.95s davomida
  ///    qimirlamas belgi turardi — u qism assetdan KESIB tashlandi (rolik endi
  ///    3.1s). Ustiga bu yerda 1 soniya kutilardi: oxirida ~3s "o'lik" ekran.
  ///  • Keyin 120ms qilib qo'yildi — bu esa teskari nuqson berdi: belgi
  ///    joyiga tushishi bilanoq main.dart dagi `AnimatedSwitcher` (350ms)
  ///    o'tishni boshlab yuborar, ya'ni splash "tugamay turib yopilardi".
  /// 450ms — tugagan belgi bir zum ko'rinib turishiga yetadi, lekin kutish
  /// sezilmaydi. Ekranga bosish bu kutishni baribir kesib o'tadi.
  static const Duration _holdLastFrame = Duration(milliseconds: 450);

  /// Ijro qandaydir sababga ko'ra to'xtab qolsa ham ilova ochiladi.
  static const Duration _playSlack = Duration(seconds: 2);

  /// Rolik ekran eniga sig'dirilgandan keyin yana shuncha kattalashtiriladi.
  /// Kadrdagi belgi eni bo'yicha ~30% joyni egallaydi, ya'ni 1.0 da u 402pt
  /// li ekranda ~123pt bo'lardi — kichkina ko'rinadi. 1.6 da ~195pt.
  ///
  /// Xavfsiz: rolikning foni va chetlari qop-qora, shuning uchun
  /// kattalashtirishda faqat qora joy qirqiladi.
  static const double _videoScale = 1.6;

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
    // Yangi rolikda audio dorozhka YO'Q; 0 — qurilma ovozini beixtiyor
    // o'zgartirmaslik uchun.
    await controller.setVolume(0);
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
        // Introni o'tkazib yuborish — 5 soniya har startda uzun tuyulishi
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
                      // `contain`, NOT `cover`: rolik eniga cho'zilgan (16:9),
                      // telefon esa bo'yiga. `cover` uni balandlikka cho'zib,
                      // enining ~70% ini qirqib tashlardi.
                      //
                      // Kattalashtirish esa [_videoScale] bilan: rolikning
                      // chetlari ham qop-qora bo'lgani uchun kattalashganda
                      // faqat qora joy qirqiladi, belgi esa butun qoladi.
                      child: Transform.scale(
                        scale: _videoScale,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: controller.value.size.width,
                            height: controller.value.size.height,
                            child: VideoPlayer(controller),
                          ),
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
