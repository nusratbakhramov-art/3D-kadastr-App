/// The carousel's open-listing chip shares [GradientSurface] with the home
/// call/chat FABs that float over it. These pin the two things that would
/// silently break that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/theme/app_colors.dart';
import 'package:kadastr/widgets/gradient_surface.dart';

void main() {
  testWidgets('paints the light→base→deep fill at the requested size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: GradientSurface(
              light: AppColors.callGreenLight,
              base: AppColors.callGreen,
              deep: AppColors.callGreenDeep,
              size: 28,
              radius: 9,
              child: Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
      ),
    );

    final body = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(GradientSurface),
            matching: find.byType(Container),
          )
          .first,
    );
    final gradient =
        (body.decoration as BoxDecoration).gradient as LinearGradient;

    expect(gradient.colors, [
      AppColors.callGreenLight,
      AppColors.callGreen,
      AppColors.callGreenDeep,
    ]);
    expect(tester.getSize(find.byType(GradientSurface)), const Size(28, 28));
  });

  // The chip is painted, not pressed: the whole carousel card owns the tap. Its
  // Material/InkWell must therefore stay transparent to hits — if it starts
  // swallowing them, tapping the arrow (the most obvious target on the card)
  // would do nothing at all.
  testWidgets('a tap-less surface does not swallow the card tap', (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(
                color: Colors.black,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(
                    child: GradientSurface(
                      light: AppColors.callGreenLight,
                      base: AppColors.callGreen,
                      deep: AppColors.callGreenDeep,
                      size: 28,
                      radius: 9,
                      child: Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GradientSurface));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('its own onTap still fires when given one', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GradientSurface(
              light: AppColors.callGreenLight,
              base: AppColors.callGreen,
              deep: AppColors.callGreenDeep,
              size: 56,
              radius: 16,
              onTap: () => taps++,
              child: const Icon(Icons.call_rounded),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GradientSurface));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
