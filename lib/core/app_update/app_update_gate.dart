/// Yangilanish oqimining UI qismi.
///
/// [AppUpdateGate] butun ilovani o'raydi va [appReleaseNotifier] ni tinglaydi:
///
///   * `required=true` → BLOKLOVCHI ekran. Orqaga tugmasi ham ishlamaydi
///     (`PopScope(canPop: false)`), yagona amal — do'konni ochish.
///   * `has_update=true, required=false` → bekor qilinadigan pastki oyna
///     ("Yangilash" / "Keyinroq"). Bir sessiyada bir marta.
///   * qolgan barcha holat (jumladan tarmoq xatosi) → hech narsa. Ilova
///     yangilanish tekshiruvi tufayli HECH QACHON ishlamay qolmaydi.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../i18n/app_translations.dart';
import '../../widgets/remote_image.dart';
import '../../widgets/sheet_button.dart';
import '../../theme/app_colors.dart';
import 'app_release.dart';
import 'app_update_store.dart';
import 'store_launcher.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child, required this.locale});

  final Widget child;
  final Locale locale;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    appReleaseNotifier.addListener(_onRelease);
    // Splash/onboarding tugagach ham qayta tekshiramiz: javob shu paytgacha
    // kelgan bo'lishi mumkin va u kutib turibdi.
    appShellReadyNotifier.addListener(_onRelease);
    // Kesh allaqachon to'lgan bo'lishi mumkin (store sovuq startда o'qiydi).
    scheduleMicrotask(_onRelease);
  }

  @override
  void dispose() {
    appReleaseNotifier.removeListener(_onRelease);
    appShellReadyNotifier.removeListener(_onRelease);
    super.dispose();
  }

  void _onRelease() {
    // Splash roligi yoki onboarding ustida yangilanish oynasi chiqmaydi —
    // foydalanuvchi ilovani hali ko'rmagan bo'lsa, oyna kontekstsiz turadi.
    if (!appShellReadyNotifier.value) return;
    final release = appReleaseNotifier.value;
    // Taklif oynasi ochiq turgan payt reliz MAJBURIYGA aylansa (masalan fondan
    // qaytganda backend `required=true` qaytardi), oyna bloklovchi ekran
    // USTIDA osilib qolardi — "Keyinroq" tugmasi bilan. Yopamiz.
    if (release.isBlocking && _sheetOpen) {
      scheduleMicrotask(_closeSheet);
      return;
    }
    // Bloklovchi holat oyna emas, to'liq ekran — build() hal qiladi.
    if (!release.isOptional || _sheetOpen) return;
    if (AppUpdateStore.instance.dismissedKey == release.key) return;
    // Mikrotask — kadr (frame) chizilishini KUTMAYDI. `addPostFrameCallback`
    // faqat kadr rejalashtirilgan bo'lsa ishlaydi; notifier'ni oddiy listener
    // o'qiganda hech narsa "dirty" bo'lmaydi, shuning uchun oyna kech ochilar
    // (yoki umuman ochilmas) edi.
    scheduleMicrotask(() => _showOptionalSheet(release));
  }

  void _closeSheet() {
    if (!mounted || !_sheetOpen) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) navigator.pop();
  }

  Future<void> _showOptionalSheet(AppRelease release) async {
    if (!mounted || _sheetOpen) return;
    // Oraliqда majburiyga aylangan bo'lsa oyna kerak emas.
    if (!appReleaseNotifier.value.isOptional) return;
    _sheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (_) => _UpdateSheet(release: release, locale: widget.locale),
    );
    _sheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppRelease>(
      valueListenable: appReleaseNotifier,
      builder: (context, release, child) {
        if (!release.isBlocking) return child!;
        // Bloklovchi ekran ham splashdan KEYIN — aks holda ilova ochilishida
        // video o'rniga darhol "yangilang" chiqib, nima bo'layotgani
        // tushunarsiz bo'lardi.
        return ValueListenableBuilder<bool>(
          valueListenable: appShellReadyNotifier,
          builder: (context, ready, _) => ready
              ? ForcedUpdateScreen(release: release, locale: widget.locale)
              : child!,
        );
      },
      child: widget.child,
    );
  }
}

/// Matnlar — hammasi backend i18n bundle'idan (`tr`), inline zaxira yo'q.
class _S {
  const _S._();
  static String updateNow(Locale l) => tr(l, 'update.action_update');
  static String later(Locale l) => tr(l, 'update.action_later');
  static String requiredTitle(Locale l) => tr(l, 'update.required_title');
  static String requiredBody(Locale l) => tr(l, 'update.required_body');
  static String optionalTitle(Locale l) => tr(l, 'update.optional_title');
  static String optionalBody(Locale l) => tr(l, 'update.optional_body');
  static String openFailed(Locale l) => tr(l, 'update.open_failed');
  static String versionYours(Locale l) => tr(l, 'update.version_yours');
  static String versionNew(Locale l) => tr(l, 'update.version_new');
}

Future<void> _openStoreOrWarn(
  BuildContext context,
  AppRelease release,
  Locale locale,
) async {
  final ok = await openStore(release.storeUrl);
  if (ok || !context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(_S.openFailed(locale))));
}

/// Chiqib bo'lmaydigan ekran — majburiy yangilanish.
///
/// Ataylab QORONG'I va ilovaning o'zidan boshqacha: bu ilova emas, bu devor.
/// Splash ham qorong'i — shuning uchun o'tish silliq, va foydalanuvchi "ilova
/// ochilmadi" emas, "to'xtatildi" degan tuyg'uni oladi. Mavzuga (light/dark)
/// bog'liq emas: majburiy ekran har doim bir xil ko'rinadi.
class ForcedUpdateScreen extends StatefulWidget {
  const ForcedUpdateScreen({
    super.key,
    required this.release,
    required this.locale,
  });

  final AppRelease release;
  final Locale locale;

  @override
  State<ForcedUpdateScreen> createState() => _ForcedUpdateScreenState();
}

class _ForcedUpdateScreenState extends State<ForcedUpdateScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF05100A);

  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..forward();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  /// Do'kon belgisining kirishi — qolgan elementlardan boshqacha: pastdan
  /// ko'tarilish o'rniga bir oz KATTALASHIB chiqadi (`easeOutBack` — oxirida
  /// yengil "otilish"). 3D belgi shu bilan jonli ko'rinadi va ekrandagi
  /// birinchi fokus nuqtasi bo'lib qoladi.
  ///
  /// Ataylab CHEKLI animatsiya: cheksiz takrorlanuvchi harakat bloklovchi
  /// ekranda bezovta qiladi va widget testlaridagi `pumpAndSettle` hech qachon
  /// tugamay qolardi.
  Widget _markEntrance(Widget child) {
    final curve = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0, 0.62, curve: Curves.easeOutBack),
    );
    final fade = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0, 0.40, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: _entry,
      builder: (context, _) => Opacity(
        opacity: fade.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.78 + 0.22 * curve.value,
          alignment: Alignment.bottomLeft,
          child: child,
        ),
      ),
    );
  }

  /// Ketma-ket (staggered) paydo bo'lish: pastdan ko'tarilib, ochiladi.
  Widget _step(int index, Widget child) {
    final begin = (index * 0.12).clamp(0.0, 0.7);
    final curve = CurvedAnimation(
      parent: _entry,
      curve: Interval(
        begin,
        (begin + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final locale = widget.locale;
    final title = release.title.isNotEmpty
        ? release.title
        : _S.requiredTitle(locale);
    final body = release.subtitle.isNotEmpty
        ? release.subtitle
        : _S.requiredBody(locale);

    return PopScope(
      // Android "orqaga" tugmasi ham ilovaga qaytarmaydi.
      canPop: false,
      // Ekran QORONG'I — status bar ikonkalari OQ bo'lishi kerak. Ilovaning
      // qolgan qismi och mavzuda, shuning uchun global uslub bu yerda mos
      // kelmaydi va uni aynan shu ekran uchun bekor qilamiz (aks holda soat va
      // batareya qora fonda qora bo'lib o'qilmay qoladi).
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light, // Android
          statusBarBrightness: Brightness.dark, // iOS
          systemNavigationBarColor: _bg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    // Yassi rang emas — ikonka ortida yumshoq brend nuri.
                    gradient: RadialGradient(
                      center: Alignment(-0.5, -0.3),
                      radius: 1.0,
                      colors: [Color(0xFF0A2213), _bg],
                    ),
                  ),
                ),
              ),
              // Asosiy ekrandagi AYNAN o'sha naqsh (home/pattern.png), o'ng
              // yuqorida — bu ekranni ilovaning o'zi bilan bog'laydi.
              //
              // `pattern_dark.png` — o'sha faylning qorong'i mavzu uchun
              // tayyorlangan nusxasi: siyoh OQ, alfa esa asl naqshning
              // to'qligidan olingan, och fon esa TO'LIQ shaffof.
              //
              // Nega runtime'da ColorFilter bilan qilinmadi: Flutter rasmni
              // dekodlashda alfani RGBga ko'paytiradi (premultiplied). Asl
              // faylda alfa ~25/255 bo'lgani uchun filtrga fon ham (245→24),
              // naqsh ham (133→13) deyarli BIR XIL qiymatda yetib boradi va
              // ularni ajratib bo'lmaydi — ekranda naqsh emas, yassi to'rtburchak
              // dog' chiqadi. Shuning uchun konvertatsiya oldindan bajarilgan.
              Positioned(
                top: 0,
                right: 0,
                child: Image.asset(
                  'assets/images/home/pattern_dark.png',
                  width: MediaQuery.sizeOf(context).width,
                  height: MediaQuery.sizeOf(context).width,
                  fit: BoxFit.contain,
                  alignment: Alignment.topRight,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(flex: 2),
                      _markEntrance(_StoreMark(release: release)),
                      const SizedBox(height: 30),
                      // Chapga tekislangan sarlavha — markazlashtirilgan
                      // "bo'sh holat" ko'rinishidan qochamiz.
                      _step(
                        1,
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'MTSCompact',
                            fontSize: 30,
                            height: 1.12,
                            letterSpacing: -0.6,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _step(
                        2,
                        Text(
                          body,
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontSize: 15.5,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _step(
                        3,
                        _VersionRow(to: release.version, locale: locale),
                      ),
                      if (release.description.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        // Ramkasiz: reliz izohlari yuqoridagi matn bilan bitta
                        // blok bo'lib o'qiladi. Quti hech narsa qo'shmasdi — u
                        // bosiladigan ham, alohida ajratiladigan ham emas edi.
                        _step(
                          4,
                          Text(
                            release.description,
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontSize: 14,
                              height: 1.6,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(flex: 3),
                      // Yagona amal — pastga mahkamlangan, kattaligi bilan
                      // "boshqa yo'l yo'q" deydi.
                      _step(
                        5,
                        SheetButton(
                          label: _S.updateNow(locale),
                          isDark: true,
                          filled: true,
                          onTap: () =>
                              _openStoreOrWarn(context, release, locale),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Do'kon belgisi — foydalanuvchi qayerga borishini AYTADI.
///
/// Qulf ikonkasi "bloklandingiz" degani edi; do'kon logotipi esa "mana shu
/// yerdan yangilaysiz" deydi — ya'ni keyingi qadamni ko'rsatadi. Platformaga
/// qarab App Store yoki Play Store.
///
/// ⚠ Hozirgi rasmlar Iconscout'dan olingan VAQTINCHALIK namunalar (App Store
/// nusxasi "premium" yo'lidan): ishlab chiqarishga chiqarishdan oldin
/// litsenziyasi tekshirilishi yoki Apple/Google'ning rasmiy badge'lariga
/// almashtirilishi kerak.
class _StoreMark extends StatelessWidget {
  const _StoreMark({required this.release, this.size = 96});

  final AppRelease release;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Adminka rasm bergan bo'lsa — o'sha ustun turadi.
    final url = release.imageUrl;
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: RemoteImage(url: url),
        ),
      );
    }
    // Relizning platformasi (backenddan) — qurilmaniki bilan bir xil bo'ladi,
    // lekin bo'sh kelsa qurilmadan olamiz.
    final isIos = (release.platform ?? AppUpdateStore.platform) == 'ios';
    // Manba rasmning o'zida ~12% bo'sh chekka bor, shuning uchun ko'rinadigan
    // belgi quti o'lchamidan sezilarli kichik chiqadi — 96 qo'yilgan.
    return Image.asset(
      isIos
          ? 'assets/images/store/appstore.png'
          : 'assets/images/store/playstore.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// "Sizda 1.0.5 → Yangi 1.0.7" — ikki ustunli, belgilangan qator.
class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.to,
    required this.locale,
    this.onDark = true,
  });

  final String? to;
  final Locale locale;

  /// Qorong'i fon ustidami — matn ranglari shunga qarab tanlanadi.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (to == null) return const SizedBox.shrink();
    return Row(
      children: [
        _cell(_S.versionYours(locale), kAppVersion, false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 15,
            color: onDark
                ? Colors.white.withValues(alpha: 0.3)
                : const Color(0xFFB6BBC0),
          ),
        ),
        _cell(_S.versionNew(locale), to!, true),
      ],
    );
  }

  Widget _cell(String label, String value, bool strong) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontSize: 10.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: onDark
              ? Colors.white.withValues(alpha: 0.35)
              : const Color(0xFF9AA0A6),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontSize: 17,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: strong
              ? (onDark ? AppColors.splashGreen : AppColors.brandGreen)
              : (onDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFF8C9196)),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// Bekor qilinadigan taklif — pastki DRAWER, MAJBURIY ekran bilan bir tilda.
///
/// Pastga va yon tomonlarga yopishib turadi (faqat yuqori burchaklari
/// yumaloq) — ya'ni "modal kartochka" emas, tortib chiqariladigan tortma.
/// Yuzasi mavzuga mos: och mavzuda OQ. Majburiy ekrandan yagona farqi va u
/// ataylab yaqqol: bu yerda «Keyinroq» bor.
class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.release, required this.locale});

  final AppRelease release;
  final Locale locale;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  Widget _step(int index, Widget child) {
    final begin = (index * 0.13).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: _entry,
      curve: Interval(
        begin,
        (begin + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final locale = widget.locale;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = release.title.isNotEmpty
        ? release.title
        : _S.optionalTitle(locale);
    final body = release.subtitle.isNotEmpty
        ? release.subtitle
        : _S.optionalBody(locale);

    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final strong = isDark ? Colors.white : AppColors.sheetTitle;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF6C7278);
    final faint = isDark
        ? Colors.white.withValues(alpha: 0.48)
        : const Color(0xFF8C9196);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        // Uzun tavsif oynani ekrandan chiqarib yubormasin.
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: surface,
        // Faqat YUQORI burchaklar — pastga va yonlarga yopishib turadi.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : const Color(0xFFE3E5E8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _step(0, _StoreMark(release: release, size: 64)),
                const SizedBox(height: 18),
                _step(
                  1,
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontSize: 22,
                      height: 1.18,
                      letterSpacing: -0.4,
                      fontWeight: FontWeight.w700,
                      color: strong,
                    ),
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _step(
                    2,
                    Text(
                      body,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontSize: 15,
                        height: 1.45,
                        color: muted,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _step(
                  3,
                  _VersionRow(
                    to: release.version,
                    locale: locale,
                    onDark: isDark,
                  ),
                ),
                if (release.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _step(
                    4,
                    Text(
                      release.description,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontSize: 14,
                        height: 1.6,
                        color: faint,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                _step(
                  5,
                  SheetButton(
                    label: _S.updateNow(locale),
                    isDark: isDark,
                    filled: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      _openStoreOrWarn(context, release, locale);
                    },
                  ),
                ),
                const SizedBox(height: 9),
                // MAJBURIY ekrandan yagona farqi — chiqish yo'li.
                _step(
                  5,
                  SheetButton(
                    label: _S.later(locale),
                    isDark: isDark,
                    onTap: () {
                      AppUpdateStore.instance.dismissedKey = release.key;
                      Navigator.of(context).pop();
                    },
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
