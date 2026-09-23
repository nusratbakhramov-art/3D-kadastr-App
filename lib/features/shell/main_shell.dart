import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../../core/app_navigation.dart';
import '../../core/i18n/app_translations.dart';
import '../../core/push_notifications.dart';
import '../auth/api_auth_service.dart';
import '../auth/auth_flow_screen.dart';
import '../auth/auth_storage.dart';
import '../auth/widgets/login_required_sheet.dart';
import '../applications/applications_screen.dart';
import '../help/help_screen.dart';
import '../home/home_screen.dart';
import '../home/user_profile.dart';
import '../market/market_screen.dart';
import '../notifications/notifications_screen.dart';
import '../onboarding/onboarding_page_data.dart';
import '../payments/payments_screen.dart';
import '../profile/about_app_screen.dart';
import '../profile/my_profile_screen.dart';
import '../profile/profile_screen.dart';
import '../services/screens/ai_scan_intro_screen.dart';
import '../services/screens/kadastr/kadastr_area_screen.dart';
import '../services/screens/online_calculator_screen.dart';
import '../bozor/feed/bozor_home_screen.dart';
import '../services/screens/taqiq_check_screen.dart';
import '../settings/settings_screen.dart';
import '../../theme/app_colors.dart';
import 'app_bottom_nav.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.locale = AppLocale.uz,
    this.authStorage = const AuthStorage(),
  });

  final Locale locale;
  final AuthStorage authStorage;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _profileAnimToken = 0;
  int _applicationsAnimToken = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    // Push / deep-link orqali tab almashtirish signalini tinglaymiz.
    shellTabRequest.addListener(_onShellTabRequest);
    // Cold start: app push bosilib ochilгan bo'lsa, kutilayotgan tab bor.
    if (shellTabRequest.value >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onShellTabRequest());
    }
  }

  void _onShellTabRequest() {
    final i = shellTabRequest.value;
    if (i < 0 || !mounted) return;
    shellTabRequest.value = -1; // bir martalik — reset
    _onTabChanged(i);
  }

  @override
  void dispose() {
    shellTabRequest.removeListener(_onShellTabRequest);
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int i) {
    if (i == _index) return;
    final delta = (i - _index).abs();
    setState(() {
      _index = i;
      if (i == 2) _applicationsAnimToken++;
      if (i == 3) _profileAnimToken++;
    });
    if (delta > 1) {
      _pageController.jumpToPage(i);
    } else {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _openAuth() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => AuthFlowScreen(
          storage: widget.authStorage,
          onAuthenticated: () => Navigator.of(context).pop(),
          onSkip: () => Navigator.of(context).pop(),
        ),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (mounted) setState(() {});
    // Login bo'lган bo'lsa — FCM tokenni backendga bog'laymiz.
    unawaited(PushNotifications.syncToken());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(onLogoutConfirmed: _handleLogout),
      ),
    );
  }

  Future<void> _handleLogout() async {
    // Tokenni backenddan o'chiramiz (storage tozalanishidan oldin — auth kerak).
    final session = await widget.authStorage.loadSession();
    final token = session.token;
    if (token != null) {
      await PushNotifications.unregister(token);
      // Backend sessiyasini ham yopamiz — aks holda access token 24 soat,
      // refresh token esa 30 kun yaroqli qolib, "chiqish" faqat mahalliy bo'lardi.
      await ApiAuthService().logout(token);
    }
    await widget.authStorage.clear();
    userProfileNotifier.value = null;
    notificationUnreadNotifier.value = 0;
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _index = 0);
    _pageController.jumpToPage(0);
  }

  Future<void> _openMyProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MyProfileScreen()));
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  Future<void> _openHelp() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));
  }

  Future<void> _openRatings() async {
    // "Baholashlarim" — Arizalar ro'yxati AI Baholash xizmatiga qulflangan
    // (bottom-nav Arizalar tabidagi haqiqiy `/ai-valuations` ma'lumotlari).
    final title = tr(widget.locale, 'shell.menu.ratings');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApplicationsScreen(
          lockedServiceId: 'ai_eval',
          titleOverride: title,
        ),
      ),
    );
  }

  Future<void> _openScans() async {
    // "Mening arizalarim" — Arizalar ro'yxati Kalkulyator xizmatiga qulflangan
    // (Kalkulyator/Arxitektura/Dizayn buyurtmalari). Avval faqat tugallanmagan
    // draftlar ko'rsatilardi, shuning uchun ro'yxat doim bo'sh chiqardi.
    final title = tr(widget.locale, 'shell.menu.scans');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ApplicationsScreen(lockedServiceId: 'calc', titleOverride: title),
      ),
    );
  }

  Future<void> _openAbout() async {
    // "Ilova haqida" — ilova ma'lumoti + Baholovchi hujjatlari (AI Baholash
    // to'lovdan oldingi qadamdagi bilan bir xil, ochiq endpoint). Mehmon ham,
    // tizimga kirgan foydalanuvchi ham ko'ra oladi.
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AboutAppScreen()));
  }

  Future<void> _openPayments() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PaymentsScreen()));
  }

  Future<void> _openAiValuation() async {
    // AI Baholash needs an account — gate with a login drawer before the
    // wizard opens (kadastr → client → location → purpose → intake → result).
    if (!await ensureLoggedIn(context, storage: widget.authStorage)) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Nom SHART: oqimni yopish (`closeAiWizard`) `ai/` bilan
        // boshlanmaydigan birinchi marshrutgacha poplaydi.
        settings: const RouteSettings(name: 'ai/scan-intro'),
        builder: (_) => const AiScanIntroScreen(),
      ),
    );
  }

  void _openCombinedCalc() {
    // Birlashgan kalkulyator = maydon → ko'p tanlovli xizmatlar → umumiy hisob
    // → "Ariza topshirish" (to'g'ridan buyurtma). "Kalkulyator" karta + banner.
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const KadastrAreaScreen()));
  }

  void _openServiceList() {
    // Xizmatlar ro'yxati = xizmatni tanla → formani to'ldir → hisob natijasi
    // → "Ariza topshirish". "3D kadastr" karta shu yerga.
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OnlineCalculatorScreen()),
    );
  }

  /// Home'dagi «Bozor AI» kartasi — sehrgarni EMAS, e'lonlar ekranini ochadi
  /// («E'lonlar» + «Mening e'lonlarim» tablari). Sehrgarga o'sha ekranning
  /// ichidagi «E'lon qo'shish» tugmasi orqali o'tiladi.
  ///
  /// ⚠️ Marshrutga `bozorRoute(...)` BERILMAYDI: `closeBozorWizard()` `bozor/`
  /// prefiksli hamma marshrutni pop qiladi, ya'ni shu prefiks bilan push
  /// qilsak sehrgar tugagach foydalanuvchi lentaga emas, Home'ga tushib
  /// qolardi.
  ///
  /// AI Baholash kabi mehmonga YOPIQ: lenta, «Mening e'lonlarim» va e'lon
  /// qo'shish — hammasi token talab qiladi, shuning uchun xom 401 o'rniga
  /// kirishdan oldin login drawer chiqadi.
  Future<void> _openBozorAi() async {
    if (!await ensureLoggedIn(context, storage: widget.authStorage)) return;
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const BozorHomeScreen()));
  }

  /// «Taqiqni tekshirish» — shaxsiy kadastr ma'lumoti bo'yicha so'rov, shuning
  /// uchun Bozor AI / AI Baholash bilan bir xil login drawer bilan qulflanadi.
  /// (Tekshiruvning o'zi ham token talab qiladi: davreestr captchasi backend
  /// orqali yechiladi.)
  Future<void> _openTaqiqCheck() async {
    if (!await ensureLoggedIn(context, storage: widget.authStorage)) return;
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TaqiqCheckScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final items = _ShellStrings.items(widget.locale);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Pages paint UNDER the tab bar; the bar's own gradient is what makes
      // content disappear as it scrolls behind it.
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) {
          if (i != _index) setState(() => _index = i);
        },
        children: [
          HomeScreen(
            locale: widget.locale,
            onLoginTap: _openAuth,
            // "3D kadastr" karta → xizmatlar ro'yxati kalkulyatori.
            onOpenKadastr3d: _openServiceList,
            onOpenAiValuation: _openAiValuation,
            onOpenBozorAi: _openBozorAi,
            onOpenTaqiqCheck: _openTaqiqCheck,
            // "Kalkulyator" karta → birlashgan (maydon → xizmatlar) kalkulyator.
            onOpenKalkulyator: _openCombinedCalc,
            // Banner "Online kalkulyator" → birlashgan kalkulyator.
            onOpenOrder: _openCombinedCalc,
            onOpenProfile: () => _onTabChanged(3),
            onOpenNotifications: _openNotifications,
          ),
          const MarketScreen(),
          ApplicationsScreen(animateToken: _applicationsAnimToken),
          ProfileScreen(
            locale: widget.locale,
            animateToken: _profileAnimToken,
            onSettingsTap: _openSettings,
            onMyProfileTap: _openMyProfile,
            onBellTap: _openNotifications,
            onHelpTap: _openHelp,
            onRatingsTap: _openRatings,
            onMyScansTap: _openScans,
            onAboutTap: _openAbout,
            onPaymentsTap: _openPayments,
            onLoginTap: _openAuth,
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        items: items,
        onChanged: _onTabChanged,
      ),
    );
  }
}

/// Pastki panel tablari — TEST uchun ochiq.
///
/// Ro'yxatning o'zi `_ShellStrings` ichida xususiy; bu yerda faqat unga
/// kirish nuqtasi. Sabab: tablarning RANGI jimgina qaytadigan narsa —
/// tint berilmasa Market va Arizalar o'z brend ranglarini (qizil, ko'k)
/// chiqaradi va buni `analyze` ham, boshqa testlar ham ko'rmaydi.
@visibleForTesting
List<AppBottomNavItem> shellNavItems(Locale locale) =>
    _ShellStrings.items(locale);

class _ShellStrings {
  const _ShellStrings._();

  // Each tab keeps one fixed colour — nothing here reacts to which tab is
  // selected. The 3D glyphs carry their own palette (green house, blue bag,
  // orange document), so the label below each one simply repeats that hue;
  // recolouring on selection would erase the cue the design navigates by.
  //
  // ⚠️ These are PNGs, not the old flat SVGs, and nothing tints them. Swapping
  // in a new glyph means picking its label colour here too, or the pair drifts
  // apart — `analyze` will not notice.
  static List<AppBottomNavItem> items(Locale locale) => [
    AppBottomNavItem(
      label: _home(locale),
      iconAsset: 'assets/icons/tab-home.png',
      // Designer's green, not the darker brand green: this label is the only
      // thing marking the active tab, so it is a specified colour.
      labelColorLight: const Color(0xFF00BF47),
      labelColorDark: const Color(0xFF00BF47),
    ),
    AppBottomNavItem(
      label: _market(locale),
      iconAsset: 'assets/icons/tab-market.png',
      labelColorLight: const Color(0xFF1B8FEA),
      labelColorDark: const Color(0xFF5CC0FF),
    ),
    AppBottomNavItem(
      label: _applications(locale),
      iconAsset: 'assets/icons/tab-applications.png',
      labelColorLight: const Color(0xFFF26522),
      labelColorDark: const Color(0xFFFF8A4C),
    ),
    AppBottomNavItem(
      label: _profile(locale),
      iconAsset: 'assets/icons/tab-profile.svg',
      labelColorLight: AppColors.textBlack,
      labelColorDark: Colors.white,
      // Profil is the one tab whose glyph is the person themselves: their
      // avatar if they have one, their initial if signed in without one, and a
      // neutral disc while a guest.
      iconBuilder: (context) => const _NavAvatar(),
    ),
  ];

  // Keyed through tr() so the admin panel can rename the tabs. A bare switch
  // means a code change and a store release to reword one label.
  static String _home(Locale l) => tr(l, 'nav.home');

  static String _market(Locale l) => tr(l, 'nav.market');

  static String _applications(Locale l) => tr(l, 'nav.applications');

  static String _profile(Locale l) => tr(l, 'nav.profile');
}

/// The Profil tab's glyph: the signed-in user's avatar, drawn as a disc the
/// same size as the other tabs' 3D icons.
///
/// It listens to [userProfileNotifier] itself so a profile edit repaints 30pt
/// of tab bar rather than rebuilding the shell (and with it every page the
/// [PageView] is holding alive).
class _NavAvatar extends StatelessWidget {
  const _NavAvatar();

  /// Squircle, not a circle: the other three glyphs are rounded squares, and a
  /// round avatar beside them read as a different kind of thing.
  static final BorderRadius _shape = BorderRadius.circular(8);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: ValueListenableBuilder<UserProfile?>(
        valueListenable: userProfileNotifier,
        builder: (context, profile, _) {
          final path = profile?.avatarPath;
          if (path != null) {
            return ClipRRect(
              borderRadius: _shape,
              child: path.startsWith('assets/')
                  ? Image.asset(path, fit: BoxFit.cover)
                  : Image.file(File(path), fit: BoxFit.cover),
            );
          }
          if (profile == null) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkIconBg : const Color(0xFFE3E6E8),
                borderRadius: _shape,
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: isDark ? Colors.white70 : const Color(0xFF6B7073),
              ),
            );
          }
          final initial = profile.name.isNotEmpty
              ? profile.name.characters.first.toUpperCase()
              : '?';
          return DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.brandGreen,
              borderRadius: _shape,
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
