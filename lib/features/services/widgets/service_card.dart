import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/pressable_scale.dart';
import '../models/service_item.dart';

/// A dark halo behind the card copy so the title/subtitle stay legible even
/// where a line passes over the bright 3D logo. Three stacked shadows: a solid
/// black core hugging the glyphs (kills contrast against light art), plus two
/// progressively wider, softer fall-offs so the halo reads as a glow of depth
/// rather than a hard outline. Strong on purpose — it has to hold up over the
/// brightest part of the logo.
const List<Shadow> _textShadows = [
  Shadow(color: Color(0xFF000000), blurRadius: 6),
  Shadow(color: Color(0xCC000000), blurRadius: 14),
  Shadow(color: Color(0x99000000), blurRadius: 22),
];

/// The card's type, shared with anything that needs to MEASURE a card before
/// building it (Home sizes its grid from the tallest card's copy).
const TextStyle kServiceCardTitleStyle = TextStyle(
  fontFamily: 'MTSCompact',
  fontWeight: FontWeight.w700,
  fontSize: 19,
  height: 1.2,
  letterSpacing: -0.2,
  color: Colors.white,
  shadows: _textShadows,
);

const TextStyle kServiceCardSubtitleStyle = TextStyle(
  fontFamily: 'MTSText',
  fontWeight: FontWeight.w400,
  fontSize: 11.5,
  height: 1.35,
  color: Color(0xFFB7BDC2),
  shadows: _textShadows,
);

/// Card type sized from the CARD, not from one phone.
///
/// The reference is a ~180pt-wide card (iPhone 17 Pro): title 19, subtitle
/// 11.5. A 158pt card on a Galaxy S23 gets proportionally less, which is what
/// keeps "Taqiqni tekshirish" off the chevron and stops the subtitle
/// ellipsising mid-word. The floors are the smallest sizes still comfortable to
/// read; below them the card grows instead (Home sizes the grid from these).
double serviceCardTitleSize(double cardWidth) =>
    (cardWidth * 0.106).clamp(15.5, 19.5);

double serviceCardSubtitleSize(double cardWidth) =>
    (cardWidth * 0.064).clamp(10.0, 12.0);

class ServiceCard extends StatefulWidget {
  const ServiceCard({super.key, required this.item, required this.onTap});

  final ServiceItem item;
  final VoidCallback onTap;

  @override
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard>
    with SingleTickerProviderStateMixin {
  // Subtle press-bounce on the card's logo: dip in, overshoot, settle. We let it
  // finish before navigating so the tap feels acknowledged (a beat, not a lag).
  //
  // Shortened from 300ms, which had crossed from beat into lag: with the ~300ms
  // route transition queued behind it a tap cost ~600ms before the next screen
  // was on its way, and a profile trace showed the app producing NO frames at
  // all for ~340ms after a tap — it was parked on this controller. 150ms still
  // reads as a distinct jump without outstaying it.
  static const Duration _bounceDuration = Duration(milliseconds: 150);

  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: _bounceDuration,
  );
  late final Animation<double> _logoScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.84,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 38,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.84,
        end: 1.06,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 34,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.06,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 28,
    ),
  ]).animate(_bounce);

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_bounce.isAnimating) return; // ignore double-taps mid-bounce
    HapticFeedback.mediumImpact();
    await _bounce.forward(from: 0);
    if (!mounted) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isWide = item.layout == ServiceLayout.wide;
    final radius = BorderRadius.circular(30);

    return PressableScale(
      child: Material(
        color: const Color(0xFF101010),
        // The ambient glow is clipped to the card: light belongs INSIDE it, and
        // an ellipse bleeding past the corners is what makes a card look like a
        // coloured tile instead of a dark one with a lamp in it.
        clipBehavior: Clip.antiAlias,
        // Near-neutral rim, and only a whisper of the accent in the drop
        // shadow. An accent-tinted border traced the whole card in colour,
        // which competed with the one thing that should look lit: the object.
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        elevation: 10,
        shadowColor: item.accent.withValues(alpha: 0.14),
        // RIPPLE YO'Q — ataylab. Karta bosilganini uchta narsa bilan
        // bildiradi: `PressableScale` (butun karta kichrayadi), logoning
        // sakrashi va `mediumImpact` haptikasi. Ustiga Material ripple'i
        // qo'shilsa to'rtinchi signal bo'lardi va u eng yomoni: `highlightColor`
        // qorong'i karta ustiga oqish parda tashlab, rangli glow va 3D
        // logoni bir zumga yuvib yuboradi.
        //
        // `InkWell` ATAYLAB qoldirilgan (GestureDetector o'rniga): u
        // semantikani beradi — skrinrider kartani TUGMA deb o'qiydi va
        // klaviatura fokusi ishlaydi. Faqat siyohi ko'rinmas qilingan.
        child: InkWell(
          onTap: _handleTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Stack(
            children: [
              // Ambient light the 3D object appears to cast on the card.
              //
              // A LOCALISED ellipse behind the object, not a gradient across
              // the whole card: filling the card made the colour read as the
              // card's background, tinted the title, and reached the rim. This
              // sits low and to the object's side, and is fully transparent
              // long before it gets near the copy.
              Positioned.fill(
                child: IgnorePointer(
                  child: _AmbientGlow(
                    glow: item.effectiveGlow,
                    accent: item.accent,
                  ),
                ),
              ),
              // Subtle top sheen — a faint light fall-off from the top edge for
              // a glossy, premium finish (top-light + bottom-accent depth).
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.white.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 3D object — anchored to the bottom-right corner, `contain`ed
              // inside a box measured from the CARD, not from fixed pt values.
              // Two reasons:
              //   • the artwork is not one aspect ratio, so sizing by height
              //     alone let a wide object (the Mulk bazaar house with its
              //     chart) run past the right edge and lose the chart;
              //   • a box in fixed pt is the same size on a 360dp Galaxy as on
              //     a 402pt iPhone, where the card is 20pt shorter — the object
              //     climbed into the four-line Uzbek subtitle.
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // Shorter than the card can take on purpose: at full
                      // height the object crowded the copy above it and left no
                      // dark card visible under itself. [ServiceItem.artScale]
                      // lets one card push back up — artwork that is drawn
                      // small inside its own frame needs it.
                      // The artwork YIELDS to the copy as the reader's text
                      // grows: at 150% type the same 60% of the card left the
                      // subtitle sitting on the roof of the house. The object
                      // shrinks, the words keep their room.
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(100) / 100;
                      final give = textScale.clamp(1.0, 1.6);
                      final artWidth =
                          box.maxWidth *
                          (isWide ? 0.50 : 0.80) *
                          item.artScale /
                          give;
                      final artHeight =
                          box.maxHeight *
                          (isWide ? 0.86 : 0.60) *
                          item.artScale /
                          give;
                      return Padding(
                        // No inset at all: the object sits ON the card's
                        // bottom-right corner, the way the mockup has it. Any
                        // gap made it look like it was floating in the middle
                        // of the card. What margin the artwork needs is the
                        // margin baked into the PNG itself.
                        padding: EdgeInsets.zero,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: SizedBox(
                            width: artWidth,
                            height: artHeight,
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                // Contact shadow. The artwork is a clean
                                // cut-out with no shadow of its own, so without
                                // this it floats over the accent glow instead
                                // of sitting on the card.
                                //
                                // A radial gradient, NOT a real blur: an
                                // `ImageFilter.blur` of the artwork is a live
                                // GPU pass on every frame the card paints, and
                                // five of those over a scrolling feed is the
                                // most expensive thing Home ever did. This
                                // costs one gradient fill.
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: artHeight * 0.34,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.black.withValues(alpha: 0.55),
                                          Colors.black.withValues(alpha: 0.22),
                                          Colors.transparent,
                                        ],
                                        stops: const [0.0, 0.45, 1.0],
                                      ),
                                    ),
                                  ),
                                ),
                                ScaleTransition(
                                  scale: _logoScale,
                                  // Boundary inside the transition, around the
                                  // thing being scaled, so the bounce doesn't
                                  // drag the card's gradients, shadow and
                                  // blurred text into a repaint with it.
                                  child: RepaintBoundary(
                                    child: Image.asset(
                                      item.asset,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.bottomRight,
                                      filterQuality: FilterQuality.medium,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // The chevron. Decorative on purpose (`IgnorePointer` + no
              // Semantics of its own): the whole card is already the button, so
              // a second tap target here would read to a screen reader as two
              // separate controls that do the same thing.
              Positioned(
                top: 16,
                right: 16,
                child: IgnorePointer(child: _CardChevron()),
              ),
              LayoutBuilder(
                builder: (context, box) {
                  // Type scales with the card. A 158pt Galaxy card at the
                  // iPhone's 19pt title wrapped "Taqiqni tekshirish" onto two
                  // lines and pushed it under the chevron.
                  final cardWidth = isWide ? box.maxWidth / 2 : box.maxWidth;
                  return Padding(
                    // Right inset clears the chevron so a long title never runs
                    // under it.
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Only the TITLE dodges the chevron. The subtitle
                        // sits below it and gets the full column: insetting it
                        // too squeezed three-line copy into four narrow lines
                        // on a 360dp phone.
                        Padding(
                          padding: const EdgeInsets.only(right: 30),
                          child: Text(
                            item.title,
                            // Kvadrat kartada ikki qator: "Taqiqni tekshirish"
                            // kabi uzun nom bitta qatorga sig'maydi. Keng
                            // kartada bitta qator — u yerda joy yetarli.
                            maxLines: isWide ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: kServiceCardTitleStyle.copyWith(
                              fontSize: serviceCardTitleSize(cardWidth),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Keep the copy on the left so it never collides with
                        // the 3D object in the bottom-right.
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          // Square cards: full width of the (already
                          // chevron-inset) column. Squeezing it further turned
                          // three-line copy into five narrow lines that ran
                          // down onto the artwork.
                          widthFactor: isWide ? 0.62 : 1.0,
                          child: Text(
                            item.subtitle,
                            // Clamped: the artwork sits close under the copy,
                            // and the four-line Uzbek strings ran onto it.
                            maxLines: isWide ? 2 : 4,
                            overflow: TextOverflow.ellipsis,
                            style: kServiceCardSubtitleStyle.copyWith(
                              fontSize: serviceCardSubtitleSize(cardWidth),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pool of coloured light behind a card's 3D object.
///
/// An ellipse, built as a circular [RadialGradient] stretched by a
/// [GradientTransform] rather than by a [Transform] widget — the gradient is
/// painted straight into the card's own layer, so there is no extra layer to
/// composite per frame.
///
/// ⚠️ NOT an `ImageFilter.blur`. The ramp below already reads as blurred light,
/// and a real blur is a live GPU pass on every frame each card paints; five of
/// them over a scrolling feed was the most expensive thing Home has ever done.
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.glow, required this.accent});

  final ServiceGlow glow;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = glow.color ?? accent;
    final o = glow.opacity;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth * glow.width;
        final h = box.maxHeight * glow.height;
        return Stack(
          children: [
            Positioned(
              left: box.maxWidth * glow.x - w / 2,
              top: box.maxHeight * glow.y - h / 2,
              width: w,
              height: h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    // 0.5 of the SHORTEST side, then stretched to the box's
                    // aspect by the transform below.
                    radius: 0.5,
                    transform: _StretchToBox(w == 0 ? 1 : w / (h == 0 ? 1 : h)),
                    colors: [
                      color.withValues(alpha: 0.95 * o),
                      color.withValues(alpha: 0.62 * o),
                      color.withValues(alpha: 0.22 * o),
                      color.withValues(alpha: 0.0),
                    ],
                    // The object sits ON the core of this ellipse and hides it,
                    // so the ramp stays bright well out from the centre — what
                    // the eye actually sees is the part spilling out from
                    // behind the artwork. It still reaches zero inside the
                    // card, or the ellipse's edge shows up as a ring and the
                    // title picks up the colour.
                    stops: const [0.0, 0.42, 0.68, 1.0],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Scales a gradient horizontally about the centre of its box, turning the
/// circle a [RadialGradient] would otherwise paint into an ellipse.
@immutable
class _StretchToBox extends GradientTransform {
  const _StretchToBox(this.scaleX);

  final double scaleX;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final centre = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(scaleX, 1, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  }
}

/// The white disc with a chevron in a card's top-right corner.
///
/// Painted, not pressed: see the note at its call site — the card itself is the
/// button, and this is the affordance that says so.
class _CardChevron extends StatelessWidget {
  const _CardChevron();

  static const double size = 24;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.chevron_right_rounded,
        size: 17,
        color: Color(0xFF101010),
      ),
    );
  }
}
