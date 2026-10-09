import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revise/app/app_state.dart';
import 'package:revise/main.dart';

void main() {
  // The background drift and mic pulse loop forever; the system "reduce
  // motion" setting stops them so pumpAndSettle can settle.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  });
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue(),
  );

  testWidgets('tabs: Record, Library and Settings render', (tester) async {
    await tester.pumpWidget(ReviseApp(app: AppState()));
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Start session'), findsOneWidget);
    expect(find.text('Place it between speakers'), findsOneWidget);

    // Tabs cross-fade, so the page title and the tab bar label both match;
    // the tab bar is painted last.
    await tester.tap(find.text('Library').last);
    await tester.pump();
    expect(find.text('No sessions yet'), findsOneWidget);

    await tester.tap(find.text('Settings').last);
    await tester.pump();
    expect(find.text('Sample data'), findsWidgets);
    expect(find.text('Thanks for coming in.'), findsOneWidget);
    expect(find.text('Ask for names before recording'), findsOneWidget);
    final footer = find.text(
      'Everything runs on this phone. Nothing is uploaded.',
    );
    await tester.scrollUntilVisible(
      footer,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(footer, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
