import 'package:disintegrate/disintegrate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Centred on purpose: the test root hands down tight constraints, under which
// a SizedBox cannot take its own size and every size assertion would be moot.
Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

void main() {
  group('DisintegrateEffect', () {
    testWidgets('an untouched widget pays for nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const DisintegrateEffect(
            progress: 0,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );

      // No filter, no opacity layer, no extra render object: at rest the widget
      // has to be indistinguishable from not using the package at all.
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('a finished dissolve keeps layout and state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const DisintegrateEffect(
            progress: 1,
            child: SizedBox(width: 40, height: 20),
          ),
        ),
      );

      // The child must still be laid out - removing it would collapse the list
      // row it sits in - but nothing may be painted.
      expect(tester.getSize(find.byType(SizedBox)), const Size(40, 20));
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        0,
      );
    });

    testWidgets('degrades to a fade without a shader', (
      WidgetTester tester,
    ) async {
      // The test binding has no Impeller and no compiled shader asset, which is
      // the same situation as an unsupported backend.
      await tester.pumpWidget(
        _host(
          const DisintegrateEffect(
            progress: 0.25,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );

      expect(find.byType(ImageFiltered), findsNothing);
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        moreOrLessEquals(0.75),
      );
    });
  });

  group('Disintegrate', () {
    testWidgets('dissolving reports back once, when it is over', (
      WidgetTester tester,
    ) async {
      int dissolved = 0;

      Widget build(bool visible) => _host(
        Disintegrate(
          visible: visible,
          duration: const Duration(milliseconds: 300),
          onDissolved: () => dissolved++,
          child: const SizedBox(width: 10, height: 10),
        ),
      );

      await tester.pumpWidget(build(true));
      expect(dissolved, 0);

      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 150));
      expect(dissolved, 0, reason: 'still on its way out');

      await tester.pumpAndSettle();
      expect(dissolved, 1);
    });

    testWidgets('comes back when visible turns true again', (
      WidgetTester tester,
    ) async {
      int restored = 0;

      Widget build(bool visible) => _host(
        Disintegrate(
          visible: visible,
          duration: const Duration(milliseconds: 200),
          onRestored: () => restored++,
          child: const SizedBox(width: 10, height: 10),
        ),
      );

      await tester.pumpWidget(build(true));
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();

      expect(restored, 1);
      expect(find.byType(Opacity), findsNothing, reason: 'back to zero cost');
    });

    testWidgets('disposes cleanly mid-dissolve', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const Disintegrate(
            visible: false,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(_host(const SizedBox()));
      expect(tester.takeException(), isNull);
    });
  });
}
