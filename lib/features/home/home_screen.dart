import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../support/support_service.dart';
import '../chat/screens/chat_screen.dart';
import '../onboarding/onboarding_page_data.dart';
import '../services/models/service_item.dart';
import '../services/widgets/service_card.dart';
import '../shell/app_bottom_nav.dart';
import 'user_profile.dart';
import 'widgets/home_header.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.locale = AppLocale.uz,
    this.today,
    this.onLoginTap,
    this.onOpenKadastr3d,
    this.onOpenAiValuation,
    this.onOpenBozorAi,
    this.onOpenTaqiqCheck,
    this.onOpenKalkulyator,
    this.onOpenOrder,
    this.onOpenProfile,
    this.onOpenNotifications,
  });

  final Locale locale;
  final DateTime? today;
  final VoidCallback? onLoginTap;
  final VoidCallback? onOpenKadastr3d;
  final VoidCallback? onOpenAiValuation;
  final VoidCallback? onOpenBozorAi;
  final VoidCallback? onOpenTaqiqCheck;
  final VoidCallback? onOpenKalkulyator;
  final VoidCallback? onOpenOrder;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenNotifications;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SupportService _supportService = SupportService();

  SupportInfo _supportInfo = const SupportInfo(
    phone: SupportService.fallbackPhone,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadSupportInfo());
  }

  Future<void> _loadSupportInfo() async {
    final info = await _supportService.fetchInfo();
    if (mounted) setState(() => _supportInfo = info);
  }

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: _supportInfo.phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // tel: ochilmasa jimgina o'tamiz.
    }
  }

  /// Height [HomeHeader] takes at the reader's text size: the avatar is fixed
  /// at 44, the greeting + date grow with the scale, and the taller of the two
  /// wins. Kept here as a calculation rather than a measured widget because the
  /// grid below has to be sized in the SAME layout pass.
  static double _headerHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Line heights rounded UP, plus a couple of points of slack. The header is
    // pinned to this number, so an under-estimate is not a cosmetic error — it
    // overflows the Row (a 2.8px overflow stripe, seen on the sim).
    final text = scaler.scale(20) * 1.3 + 4 + scaler.scale(14) * 1.4;
    return math.max(48, text);
  }

  void _openAssistant() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(locale: widget.locale),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.today ?? DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.greenBlack
        : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _HomePatternBackground(
            backgroundColor: backgroundColor,
            showPattern: !isDark,
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, viewport) {
                // The grid ABSORBS whatever height the rest of the page does
                // not use, down to a floor measured from the copy at the
                // reader's own text size. That is what makes this work on a
                // short phone, a tall one, and at 200% text alike: no fixed
                // aspect ratio, no magic clamps.
                //
                // Everything below the grid is measured, not guessed —
                // measured at the CURRENT text scale, so a reader who enlarges
                // type gets taller cards (or a page that scrolls) instead of
                // clipped words.
                // The bar is drawn OVER the page now, so the feed reserves the
                // slab and its gaps — but NOT the whole fade band. The top of
                // that band is fully transparent, so the support buttons can
                // sit in it without greying out, and reserving it whole is what
                // left ~64pt of dead background under them on a tall phone.
                final navHeight = AppBottomNav.contentInset(context);
                final verticalPadding = 12.0 + navHeight;
                const gapAboveGrid = 20.0;
                const gapAboveCta = 16.0;
                final gridWidth = viewport.maxWidth - 32;
                final gridMin = _CardsGrid.minHeight(
                  context,
                  widget.locale,
                  gridWidth,
                );
                // The header and the button row are PINNED to the heights
                // computed here — each is wrapped in a SizedBox below — so this
                // arithmetic is exact rather than an estimate. That is what
                // lets the grid take every remaining pixel: nothing left over
                // at the bottom, nothing sliding under the bar.
                final headerHeight = _headerHeight(context);
                final ctaHeight = _SupportCtaButton.heightFor(context);
                final leftover =
                    viewport.maxHeight -
                    verticalPadding -
                    gapAboveGrid -
                    gapAboveCta -
                    headerHeight -
                    ctaHeight;
                // Only a genuinely small screen scrolls: the floor is what the
                // cards' own copy needs at the reader's text size.
                final fits = leftover >= gridMin;
                final gridHeight = math.max(leftover, gridMin);

                final padding = EdgeInsets.fromLTRB(16, 12, 16, navHeight);
                final grid = RepaintBoundary(
                  child: _CardsGrid(
                    locale: widget.locale,
                    onOpenKadastr3d: widget.onOpenKadastr3d,
                    onOpenAiValuation: widget.onOpenAiValuation,
                    onOpenBozorAi: widget.onOpenBozorAi,
                    onOpenTaqiqCheck: widget.onOpenTaqiqCheck,
                    onOpenKalkulyator: widget.onOpenKalkulyator,
                  ),
                );

                // Every block below is wrapped in a RepaintBoundary. A
                // SingleChildScrollView — unlike a sliver list — adds none of
                // its own, so without them one scroll frame re-rasterised the
                // whole column: five cards' glow + elevation shadow + strings
                // each carrying three blurred text shadows, and the pattern.
                final column = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: headerHeight,
                      child: RepaintBoundary(
                        child: ValueListenableBuilder<UserProfile?>(
                          valueListenable: userProfileNotifier,
                          builder: (context, profile, _) {
                            return ValueListenableBuilder<int>(
                              valueListenable: notificationUnreadNotifier,
                              builder: (context, unread, _) {
                                return HomeHeader(
                                  profile: profile,
                                  unreadCount: unread,
                                  locale: widget.locale,
                                  today: date,
                                  onLoginTap: widget.onLoginTap,
                                  onAvatarTap: widget.onOpenProfile,
                                  onBellTap: widget.onOpenNotifications,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: gapAboveGrid),
                    // Exactly the leftover height when the page fits, the
                    // measured floor when it does not (and then it scrolls).
                    SizedBox(height: gridHeight, child: grid),
                    const SizedBox(height: gapAboveCta),
                    // Chat + call, in the feed. They used to be two floating
                    // FABs that hid themselves while the user scrolled; as a
                    // pair of ordinary buttons they are always reachable,
                    // never cover a card, and cost nothing to keep on screen.
                    SizedBox(
                      height: ctaHeight,
                      child: RepaintBoundary(
                        child: _SupportCtaRow(
                          locale: widget.locale,
                          onAskTap: hapticTap(_openAssistant),
                          onCallTap: hapticTap(_callSupport),
                        ),
                      ),
                    ),
                  ],
                );

                if (fits) {
                  // Everything is on screen; no scroll view at all.
                  return Padding(padding: padding, child: column);
                }
                return SingleChildScrollView(
                  clipBehavior: Clip.none,
                  padding: padding,
                  child: column,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The pair of pill buttons that close the Home feed: «Savol bering» opens the
/// in-app assistant, «Bog'lanish» dials the support number.
///
/// Each is outlined in its own hue with a matching tinted fill — light enough
/// that the 3D glyph on the right stays the loudest thing in the button.
class _SupportCtaRow extends StatelessWidget {
  const _SupportCtaRow({
    required this.locale,
    required this.onAskTap,
    required this.onCallTap,
  });

  final Locale locale;
  final VoidCallback? onAskTap;
  final VoidCallback? onCallTap;

  /// Gap between the two buttons. Tight on purpose — every point here is a
  /// point of label width, and the label is what runs out of room first (the
  /// pair shares ONE size, so the longest string sets it for both).
  static const double _gap = 8;

  /// Largest label size the design asks for. Both buttons come down together
  /// from here when the longer label does not fit.
  static const double _baseFontSize = 16;

  @override
  Widget build(BuildContext context) {
    final ask = tr(locale, 'home.support.ask');
    final contact = tr(locale, 'home.support.contact');

    // Width from the MEDIA QUERY, not a LayoutBuilder: this row is measured by
    // Home before it is built (to size the grid), and a builder that only knows
    // its width at paint time cannot answer that.
    final rowWidth = MediaQuery.sizeOf(context).width - 32;
    final buttonWidth = (rowWidth - _gap) / 2;
    // ONE size for the pair, not one per button. Each button used to shrink
    // its own label to fit (a FittedBox), so on a 360dp Galaxy the longer
    // "Savol bering" came out visibly smaller than "Bog'lanish" beside it.
    // Whichever label is tighter now sets the size for both.
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = math.min(
      _SupportCtaButton.fittedFontSize(
        ask,
        'assets/icons/cta-ask.png',
        buttonWidth,
        _baseFontSize,
        scaler,
      ),
      _SupportCtaButton.fittedFontSize(
        contact,
        'assets/icons/cta-call.png',
        buttonWidth,
        _baseFontSize,
        scaler,
      ),
    );

    return Row(
      children: [
        Expanded(
          child: _SupportCtaButton(
            label: ask,
            asset: 'assets/icons/cta-ask.png',
            // Brand pair, given by the designer: blue ask / green contact.
            accent: const Color(0xFF0069E1),
            fontSize: fontSize,
            onTap: onAskTap,
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          child: _SupportCtaButton(
            label: contact,
            asset: 'assets/icons/cta-call.png',
            accent: const Color(0xFF00BF47),
            fontSize: fontSize,
            onTap: onCallTap,
          ),
        ),
      ],
    );
  }
}

class _SupportCtaButton extends StatelessWidget {
  const _SupportCtaButton({
    required this.label,
    required this.asset,
    required this.accent,
    required this.fontSize,
    required this.onTap,
  });

  final String label;
  final String asset;
  final Color accent;

  /// Handed down by [_SupportCtaRow] so both buttons share one type size.
  final double fontSize;

  final VoidCallback? onTap;

  /// The design's pill height, and the floor. It grows when the reader's text
  /// does — a fixed 44 clipped the label at the larger accessibility sizes.
  static const double _baseHeight = 44;

  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(
      _baseHeight,
      math.max(_iconHeight + 6, scaler.scale(16) * 1.15 + 14),
    );
  }

  /// Sized by HEIGHT, and almost the full height of the pill — the design has
  /// the glyph nearly bursting out of it.
  ///
  /// ⚠️ Not a square box. These PNGs are wide (the headset is 125×88), so a
  /// square `contain` box scaled them to fit their WIDTH and the glyph came out
  /// a third shorter than the box it was given.
  static const double _iconHeight = 34;

  /// Rendered width of each glyph at [_iconHeight], from the PNG's own aspect.
  /// Hard-coded because it is needed BEFORE the image is laid out, to work out
  /// how much room the label has left.
  static const Map<String, double> _iconAspect = {
    'assets/icons/cta-ask.png': 125 / 88,
    'assets/icons/cta-call.png': 103 / 88,
  };

  // Trimmed to buy label width. Russian is the binding case: "Задать вопрос"
  // is 23% wider than the Uzbek string, and because the pair shares one size it
  // dragged BOTH labels down to ~9.6pt on a 360dp phone.
  static const double _padLeft = 12;
  static const double _padRight = 8;
  static const double _labelIconGap = 2;

  /// The largest size at or below [base] at which [label] fits one line inside
  /// a button of [buttonWidth]. Measured, not guessed: the Uzbek and Russian
  /// strings differ enough in width that a fixed size either clips one or
  /// leaves the other looking undersized.
  static double fittedFontSize(
    String label,
    String asset,
    double buttonWidth,
    double base,
    TextScaler scaler,
  ) {
    final iconWidth = _iconHeight * (_iconAspect[asset] ?? 1);
    final available =
        buttonWidth -
        _padLeft -
        _padRight -
        _labelIconGap -
        iconWidth -
        2; // the 1.2pt border on both sides, rounded up
    if (available <= 0) return base;

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: base,
          height: 1.15,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      // Measure at the reader's own text scale. Without it the label was
      // measured at 1.0 and painted larger, which is what ellipsised the longer
      // Russian string even though the maths said it fitted.
      textScaler: scaler,
    )..layout();

    if (painter.width <= available) return base;
    // 0.98 of the exact ratio: the painter measures the string, the Text widget
    // then lays it out with its own rounding, and an exact fit lost the last
    // glyph to an ellipsis.
    return base * available / painter.width * 0.98;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final fill = isDark
        ? accent.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.92);
    final labelColor = isDark
        ? Color.alphaBlend(accent.withValues(alpha: 0.75), Colors.white)
        : accent;
    final height = heightFor(context);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(height / 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.fromLTRB(_padLeft, 3, _padRight, 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.55 : 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                // One line, always. The label is set at 16 and allowed to scale
                // DOWN to fit: the two buttons share a phone width, so a long
                // translation ("Задать вопрос" on a 360dp Galaxy) would
                // otherwise wrap to two lines and unbalance the pair.
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize,
                      height: 1.15,
                      color: labelColor,
                    ),
                  ),
                ),
                const SizedBox(width: _labelIconGap),
                Image.asset(
                  asset,
                  height: _iconHeight,
                  fit: BoxFit.fitHeight,
                  cacheHeight: (_iconHeight * dpr).round(),
                  filterQuality: FilterQuality.medium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePatternBackground extends StatelessWidget {
  const _HomePatternBackground({
    required this.backgroundColor,
    required this.showPattern,
  });

  final Color backgroundColor;
  final bool showPattern;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The source is 1468×1516 — ~8.9 MB of decoded ARGB for something
            // drawn one screen wide. Decode it at the width it's actually
            // painted at instead.
            final dpr = MediaQuery.of(context).devicePixelRatio;
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: backgroundColor),
                  ),
                ),
                if (showPattern)
                  Positioned(
                    top: 0,
                    right: 0,
                    width: constraints.maxWidth,
                    height: constraints.maxWidth,
                    child: Image.asset(
                      'assets/images/home/pattern.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.topRight,
                      cacheWidth: (constraints.maxWidth * dpr).round(),
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The Home service grid — the rich dark cards brought over from the (removed)
/// Services page: two rows of square cards (3D kadastr + Bozor AI, then Taqiqni
/// tekshirish + AI baholash) and one wide card (Kalkulyator), each with an
/// accent glow and a 3D image. Market lives in the bottom tab, so it's not a
/// card here.
///
/// ⚠️ THE ORDER IS THE DESIGN'S, not a natural one — it reads 3D kadastr,
/// Bozor AI, Taqiq, AI baholash, Kalkulyator (the mockup calls them Xizmatlar,
/// Mulk bazaar, Ta'qiq tekshirish, Mulk baholash, Qurilish calculator). Adding
/// a card means placing it where the mockup puts it, not appending it.
class _CardsGrid extends StatelessWidget {
  const _CardsGrid({
    required this.locale,
    this.onOpenKadastr3d,
    this.onOpenAiValuation,
    this.onOpenBozorAi,
    this.onOpenTaqiqCheck,
    this.onOpenKalkulyator,
  });

  final Locale locale;
  final VoidCallback? onOpenKadastr3d;
  final VoidCallback? onOpenAiValuation;
  final VoidCallback? onOpenBozorAi;
  final VoidCallback? onOpenTaqiqCheck;
  final VoidCallback? onOpenKalkulyator;

  static const double gap = 12;

  /// The wide card's height as a share of a square one. Keeps the two in step
  /// however much room the grid is given.
  static const double wideRatio = 0.62;

  /// Row 1's share of the two square rows (the pair sums to 2). Under 1 makes
  /// the first row shorter and the second correspondingly taller.
  ///
  /// Only NARROW phones get the shift. On a 360dp Galaxy the row-2 titles
  /// ("Taqiqni tekshirish", "Baholash Ai") wrap to two lines and the copy needs
  /// the extra height; on a 402pt iPhone the same strings fit and the rows look
  /// better equal. Interpolated, so nothing jumps at one magic width.
  static double _topRowWeight(double gridWidth) {
    const narrow = 330.0; // ~360dp phone
    const wide = 370.0; // ~402pt phone
    final t = ((gridWidth - narrow) / (wide - narrow)).clamp(0.0, 1.0);
    return 0.9 + 0.1 * t;
  }

  /// Smallest the grid can be before its own copy stops fitting.
  ///
  /// Measured, at the reader's text size: the longest title and subtitle of the
  /// five cards are laid out for real, and the tallest result sets the floor.
  /// Below it the page scrolls rather than clipping a word — which is exactly
  /// what happens at the large accessibility text sizes.
  static double minHeight(BuildContext context, Locale locale, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final columnWidth = (width - gap) / 2;
    // The title dodges the chevron (18 + 36 + 18); the subtitle below it gets
    // the full column. Measured exactly as the card lays them out.
    final titleWidth = columnWidth - 18 - 30 - 18;
    final subtitleWidth = columnWidth - 36;

    double block(String title, String subtitle) {
      double lay(String text, TextStyle style, int maxLines, double width) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: width > 0 ? width : 1);
        return painter.height;
      }

      return lay(
            title,
            kServiceCardTitleStyle.copyWith(
              fontSize: serviceCardTitleSize(columnWidth),
            ),
            2,
            titleWidth,
          ) +
          6 +
          lay(
            subtitle,
            kServiceCardSubtitleStyle.copyWith(
              fontSize: serviceCardSubtitleSize(columnWidth),
            ),
            4,
            subtitleWidth,
          );
    }

    final l = locale;
    final tallest = [
      block(_CardStrings.kadastr3d(l), _CardStrings.kadastr3dSub(l)),
      block(_CardStrings.bozorAi(l), _CardStrings.bozorAiSub(l)),
      block(_CardStrings.taqiqCheck(l), _CardStrings.taqiqCheckSub(l)),
      block(_CardStrings.aiValuation(l), _CardStrings.aiValuationSub(l)),
    ].reduce(math.max);

    // Copy + its 18pt padding top and bottom + room for the artwork to read as
    // more than a sliver.
    final square = tallest + 36 + 56;
    return square * 2 + square * wideRatio + gap * 2;
  }

  @override
  Widget build(BuildContext context) {
    final l = locale;
    final kadastr = ServiceItem(
      id: ServiceId.kadastr3d,
      title: _CardStrings.kadastr3d(l),
      subtitle: _CardStrings.kadastr3dSub(l),
      asset: 'assets/images/home/cta-icon.png',
      accent: const Color(0xFF00E135),
      layout: ServiceLayout.square,
      // This object is a compact badge rather than a house that fills the
      // corner, so its light is tighter and sits a little further left.
      glow: const ServiceGlow(x: 0.50, y: 1.04, width: 1.70, height: 1.35),
      // The badge is drawn small inside its own frame — at the shared scale it
      // came out visibly smaller than the four houses beside it.
      artScale: 1.3,
    );
    final ai = ServiceItem(
      id: ServiceId.aiValuation,
      title: _CardStrings.aiValuation(l),
      subtitle: _CardStrings.aiValuationSub(l),
      // Mockup art, kept under the name it was exported with so the next
      // export drops straight in. The old `ai.png` chip still serves the
      // Services page, which is why this is a new file and not an overwrite.
      asset: 'assets/images/services/mulk-baholash.png',
      accent: const Color(0xFF7C3AED),
      layout: ServiceLayout.square,
    );
    // Row 2. Accents stay off the row-1 hues (purple / brand green) so the four
    // glows read as four services, not two pairs; the artwork is the same 3D
    // icon family as ai.png, re-cropped to the ~88% fill the card expects.
    final bozorAi = ServiceItem(
      id: ServiceId.bozorAi,
      title: _CardStrings.bozorAi(l),
      subtitle: _CardStrings.bozorAiSub(l),
      asset: 'assets/images/services/mulk-bazaar.png',
      accent: const Color(0xFFF5B301),
      layout: ServiceLayout.square,
    );
    final taqiq = ServiceItem(
      id: ServiceId.taqiqCheck,
      title: _CardStrings.taqiqCheck(l),
      subtitle: _CardStrings.taqiqCheckSub(l),
      asset: 'assets/images/services/taqiq-tekshrish.png',
      // Orange, not the old rose: the new art is an orange house, and the glow
      // under a 3D object has to be that object's own colour or it reads as a
      // second light source.
      accent: const Color(0xFFF26522),
      layout: ServiceLayout.square,
    );
    final calculator = ServiceItem(
      id: ServiceId.calculator,
      title: _CardStrings.calculator(l),
      subtitle: _CardStrings.calculatorSub(l),
      asset: 'assets/images/services/calculator.png',
      accent: const Color(0xFF22D3EE),
      layout: ServiceLayout.wide,
      // Pushed right, hard: on a card this wide a centred glow lights the copy
      // instead of the calculator, and the whole card goes cyan.
      // Wider and a touch hotter than the square cards': the calculator is a
      // dark object that hides most of the core, so what is left to see is the
      // spill around it.
      glow: const ServiceGlow(
        x: 0.50,
        y: 1.06,
        width: 1.25,
        height: 2.20,
        opacity: 1.05,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Heights come from the SPACE THE GRID IS GIVEN, split two-square-rows
        // to one wide row. No aspect ratio and no pt clamps: those were tuned
        // on one phone at one text size and were wrong on every other.
        //
        // The caller sizes the grid (viewport minus the rest of the page,
        // floored by [minHeight]); an unbounded height only happens in tests,
        // where the width-derived fallback keeps the cards sane.
        final squareWidth = (constraints.maxWidth - gap) / 2;
        final total = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : squareWidth / 0.86 * (2 + wideRatio) + gap * 2;
        final squareHeight = (total - gap * 2) / (2 + wideRatio);
        // The two rows are NOT equal. Row 1's copy is short (one-line titles,
        // two-line subtitles) and its cards looked airy, while row 2 carries
        // the long names — "Taqiqni tekshirish", "Baholash Ai" — over three
        // lines of text. The weights move height from the first row to the
        // second; they sum to 2, so the grid's total is unchanged.
        final topWeight = _topRowWeight(constraints.maxWidth);
        final topRowHeight = squareHeight * topWeight;
        final bottomRowHeight = squareHeight * (2 - topWeight);
        final wideHeight = squareHeight * wideRatio;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: topRowHeight,
              child: Row(
                children: [
                  Expanded(
                    child: ServiceCard(
                      item: kadastr,
                      onTap: onOpenKadastr3d ?? () {},
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: ServiceCard(
                      item: bozorAi,
                      onTap: onOpenBozorAi ?? () {},
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),
            SizedBox(
              height: bottomRowHeight,
              child: Row(
                children: [
                  Expanded(
                    child: ServiceCard(
                      item: taqiq,
                      onTap: onOpenTaqiqCheck ?? () {},
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: ServiceCard(
                      item: ai,
                      onTap: onOpenAiValuation ?? () {},
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),
            SizedBox(
              height: wideHeight,
              width: double.infinity,
              child: ServiceCard(
                item: calculator,
                onTap: onOpenKalkulyator ?? () {},
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CardStrings {
  const _CardStrings._();

  static String kadastr3d(Locale l) => tr(l, 'home.card.kadastr3d');

  static String kadastr3dSub(Locale l) => tr(l, 'home.card.kadastr3d_sub');

  static String aiValuation(Locale l) => tr(l, 'home.card.ai_valuation');

  static String aiValuationSub(Locale l) => tr(l, 'home.card.ai_valuation_sub');

  static String calculator(Locale l) => tr(l, 'home.card.calculator');

  static String calculatorSub(Locale l) => tr(l, 'home.card.calculator_sub');

  static String bozorAi(Locale l) => tr(l, 'home.card.bozor_ai');

  static String bozorAiSub(Locale l) => tr(l, 'home.card.bozor_ai_sub');

  static String taqiqCheck(Locale l) => tr(l, 'home.card.taqiq_check');

  static String taqiqCheckSub(Locale l) => tr(l, 'home.card.taqiq_check_sub');
}
