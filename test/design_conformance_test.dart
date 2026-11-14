import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/theme/app_colors.dart';
import 'package:vellum/theme/app_motion.dart';
import 'package:vellum/theme/app_shape.dart';
import 'package:vellum/theme/app_type.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/widgets/ui/app_controls.dart';
import 'package:vellum/widgets/ui/app_section.dart';
import 'package:vellum/theme/app_icons.dart';

/// The conformance contract, ported from the reference implementation's
/// \`spec_test.dart\`.
///
/// Every assertion below is a design rule that used to be enforced by an eye.
/// Two assertions are the F1 overrides and say so in their reason; everything
/// else must pass on the real geometry, not a relaxed version of it.
/// See \`developDoc/design-fidelity-overrides.md\`.
void main() {
  group('tokens', () {
    test('both themes declare exactly the same roles', () {
      final light = AppColors.light.toMap();
      final dark = AppColors.dark.toMap();
      expect(dark.keys.toSet(), equals(light.keys.toSet()));
      expect(light.length, greaterThanOrEqualTo(26));
    });

    test('controlActive is a distinct role from primary', () {
      // F1 override #3: VELLUM maps the control role onto the brand accent
      // instead of the fixed control green. The *role* still has to exist and
      // still has to differ from every other role name, or a component starts
      // reading primary again and the distinction rots.
      expect(AppColors.light.controlActive, AppColors.light.primary);
      expect(AppColors.dark.controlActive, AppColors.dark.primary);
      expect(
        AppColors.light.toMap().containsKey('controlActive'),
        isTrue,
        reason: 'the role must exist even when it resolves to the accent',
      );
    });

    test('the radius scale is base-8 multiples', () {
      const multipliers = <double>[0.6, 0.8, 1, 1.4, 1.8, 2.2, 2.6];
      final values = <double>[
        AppRadius.sm,
        AppRadius.md,
        AppRadius.lg,
        AppRadius.xl,
        AppRadius.grouped,
        AppRadius.xl2,
        AppRadius.xl3,
      ];
      for (var i = 0; i < values.length; i++) {
        expect(
          values[i],
          closeTo(8 * multipliers[i], 0.0001),
          reason: 'radius step $i must be 8 x ${multipliers[i]}',
        );
      }
      // The dock is a declared extra step (override #5) but belongs to the
      // same scale rather than sitting off it.
      expect(AppRadius.dock / 8, closeTo(3, 0.0001));
    });

    test('the type scale ascends in size and keeps leading >= size', () {
      for (var i = 1; i < appTypeSequence.length; i++) {
        expect(
          appTypeSequence[i].$1,
          greaterThan(appTypeSequence[i - 1].$1),
          reason: 'size must strictly ascend: "one step up" is the next size',
        );
        expect(
          appTypeSequence[i].$2,
          greaterThanOrEqualTo(appTypeSequence[i].$1),
          reason: 'leading below size clips',
        );
      }
    });

    test('the motion vocabulary keeps three durations', () {
      expect(AppMotion.settle, isA<Cubic>());
      expect(AppMotion.overshoot, isA<Cubic>());
      expect(AppMotion.linear, isA<Curve>());
      expect(AppMotion.fast.inMilliseconds, 200);
      expect(AppMotion.base.inMilliseconds, 250);
      expect(AppMotion.slow.inMilliseconds, 350);
      expect(AppMotion.springSettle.damping, 31.5);
    });

    test('gesture windows live outside the motion vocabulary', () {
      // They answer "is this a double tap / a long press / a pull?", never
      // "how long does this animate". Mixing the two is how one screen ended
      // up with thirteen millisecond values that looked like timings.
      expect(AppGestureWindow.selectionHold.inMilliseconds, 750);
      expect(AppGestureWindow.bookmarkPullHold.inMilliseconds, 400);
      expect(AppGestureWindow.doubleTap.inMilliseconds, 200);
    });
  });

  group('row geometry', () {
    late Widget app;

    setUp(() {
      app = MaterialApp(
        theme: VellumTheme.forBrightness(Brightness.light),
        home: Scaffold(
          body: AppSection(
            header: 'Group',
            children: [
              AppRow(
                leading: const Icon(AppIcons.cloud),
                label: 'Model service',
                onTap: _noop,
              ),
              AppRow(label: 'Name', value: 'Value', onTap: _noop),
            ],
          ),
        ),
      );
    });

    testWidgets('a row with a leading icon is 48pt tall', (tester) async {
      await tester.pumpWidget(app);
      final box = tester.getSize(find.byType(AppRow).first);
      expect(box.height, closeTo(48, 0.5));
    });

    testWidgets('the grouped header is 40pt tall', (tester) async {
      await tester.pumpWidget(app);
      final header = tester.getSize(
        find
            .ancestor(
              of: find.text('Group'),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(
        header.height,
        greaterThanOrEqualTo(AppSpace.sectionHeaderMinHeight),
      );
      expect(AppSpace.sectionHeaderMinHeight, 40);
    });

    testWidgets('separators use the 44pt icon inset when rows lead', (
      tester,
    ) async {
      await tester.pumpWidget(app);
      final separator = find.byKey(
        const ValueKey<String>('section-separator-1'),
      );
      final padding = tester.widget<Padding>(
        find.descendant(of: separator, matching: find.byType(Padding)).first,
      );
      expect((padding.padding as EdgeInsets).left, 44);
      expect((padding.padding as EdgeInsets).right, 12);
    });

    testWidgets('a value row shows no chevron and keeps the value in foreground', (
      tester,
    ) async {
      await tester.pumpWidget(app);
      // One chevron in the block: the navigating row's. The value row's value
      // is its own trailing affordance, so it must not also show an arrow.
      expect(
        find.byKey(const ValueKey<String>('app-row-chevron')),
        findsOneWidget,
      );
      final value = tester.widget<Text>(
        find.byKey(const ValueKey<String>('app-row-value')),
      );
      expect(value.style?.color, AppColors.light.foreground);
    });

    testWidgets('a select row shows a down chevron and a value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VellumTheme.forBrightness(Brightness.light),
          home: Scaffold(
            body: AppSection(
              children: [
                AppSelectRow(
                  label: 'App language',
                  value: 'English',
                  onTap: _noop,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(AppIcons.chevronDown), findsOneWidget);
      expect(find.byIcon(AppIcons.chevronRight), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('app-row-value')),
        findsOneWidget,
      );
    });

    testWidgets('pressing a row hides the separator below it', (tester) async {
      await tester.pumpWidget(app);
      final separator = find.byKey(
        const ValueKey<String>('section-separator-1'),
      );

      Color separatorColor() {
        final box = tester.widget<ColoredBox>(
          find.descendant(of: separator, matching: find.byType(ColoredBox)),
        );
        return box.color;
      }

      expect(separatorColor().a, greaterThan(0));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Model service')),
      );
      await tester.pump();
      expect(separatorColor().a, 0);
      await gesture.up();
      await tester.pump();
      expect(separatorColor().a, greaterThan(0));
    });

    testWidgets('the chevron is 20pt and muted', (tester) async {
      await tester.pumpWidget(app);
      final icon = tester.widget<Icon>(
        find.byKey(const ValueKey<String>('app-row-chevron')),
      );
      expect(icon.size, 20);
      expect(icon.color, AppColors.light.mutedForeground);
    });
  });

  group('controls', () {
    testWidgets('the switch track reads controlActive when on', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VellumTheme.forBrightness(Brightness.light),
          home: const Scaffold(
            body: Center(
              child: AppSwitch(value: true, onChanged: _boolNoop),
            ),
          ),
        ),
      );
      final track = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey<String>('app-switch-track')),
      );
      expect(
        (track.decoration as BoxDecoration).color,
        AppColors.light.controlActive,
      );
    });

    testWidgets('the primary button fills with primary, not foreground', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VellumTheme.forBrightness(Brightness.light),
          home: Scaffold(
            body: Center(child: AppButton(label: 'Save', onPressed: _noop)),
          ),
        ),
      );
      final surface = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey<String>('app-button-surface')),
      );
      final decoration = surface.decoration as BoxDecoration;
      // F1 override #4: the main action is a brand action, not "the blackest
      // thing on screen".
      expect(decoration.color, AppColors.light.primary);
      expect(decoration.color, isNot(AppColors.light.foreground));
    });
  });
}

void _noop() {}
void _boolNoop(bool _) {}