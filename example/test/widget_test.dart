import 'dart:math' as math;

import 'package:disintegrate/disintegrate.dart';
import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the snap takes out half the manifest', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DisintegrateDemo());
    await tester.pumpAndSettle();

    expect(find.text('SNAP'), findsOneWidget);
    expect(find.byType(DisintegrateEffect), findsWidgets);

    await tester.tap(find.text('SNAP'));
    // The first pump settles the tap and starts the controller; only the second
    // one advances it. Skipping it samples the animation at zero.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));

    final Iterable<DisintegrateEffect> effects = tester
        .widgetList<DisintegrateEffect>(find.byType(DisintegrateEffect));
    final int going = effects.where((DisintegrateEffect e) => e.progress > 0).length;
    final int staying = effects.where((DisintegrateEffect e) => e.progress == 0).length;

    expect(going, greaterThan(0), reason: 'something has to be leaving');
    expect(
      effects.map((DisintegrateEffect e) => e.progress).reduce(math.max),
      greaterThan(0.2),
      reason: 'and it has to be visibly on its way, not just nudged',
    );
    expect(staying, greaterThan(0), reason: 'and something has to survive');

    await tester.pumpAndSettle();
    expect(find.text('BRING THEM BACK'), findsOneWidget);
  });
}
