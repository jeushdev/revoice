import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revise/app/app_state.dart';
import 'package:revise/engine/mock_caption_engine.dart';
import 'package:revise/main.dart';
import 'package:revise/summary/summary_controller.dart';
import 'package:revise/ui/live_screen.dart';

AppState fastApp([MockScenario scenario = MockScenario.meeting]) => AppState(
  engineFactory: (_) => MockCaptionEngine(
    scenario: scenario,
    wordInterval: const Duration(milliseconds: 1),
    turnGap: const Duration(milliseconds: 1),
    llmDelay: const Duration(milliseconds: 1),
  ),
);

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

/// Taps the mic, fills the optional names sheet (or skips it), starts.
Future<SavedSession> startSession(
  WidgetTester tester,
  AppState app, {
  String? names,
}) async {
  await tester.pumpWidget(ReviseApp(app: app));
  await tester.tap(find.bySemanticsLabel('Start session').first);
  await tester.pumpAndSettle();
  expect(find.text("Who's in this conversation?"), findsOneWidget);
  if (names == null) {
    await tester.tap(find.text('Skip'));
  } else {
    await tester.enterText(find.byType(TextField), names);
    await tester.tap(find.text('Start recording'));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return tester.widget<LiveScreen>(find.byType(LiveScreen)).saved;
}

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

  testWidgets('names, record, stop, summary, ask a question', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = fastApp();
    final saved = await startSession(tester, app, names: 'Sam, Zairus');
    expect(saved.session.expectedNames, ['Sam', 'Zairus']);
    await pumpUntil(
      tester,
      () => saved.session.finals.length == MockCaptionEngine.script.length,
    );
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Expecting: Sam, Zairus'), findsOneWidget);
    expect(find.text('Demo · Sample data'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Summarizing on this phone'), findsOneWidget);
    await pumpUntil(tester, () => saved.summary.status == SummaryStatus.done);
    await tester.pumpAndSettle();
    expect(app.sessions, [saved]);
    expect(find.textContaining('A LarpCode team check-in'), findsOneWidget);
    expect(find.text('Suggested questions'), findsOneWidget);

    await tester.tap(find.text('What are the deadlines?'));
    await pumpUntil(
      tester,
      () => saved.summary.asked.first.status == QuestionStatus.answered,
    );
    await tester.pumpAndSettle();
    expect(find.text('Sam: demo deck by Friday morning'), findsOneWidget);

    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
    expect(find.textContaining("Hi everyone, I'm Zairus"), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape shows the last lines in large text', (tester) async {
    tester.view
      ..physicalSize = const Size(2532, 1170)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = fastApp();
    final saved = await startSession(tester, app);
    await pumpUntil(tester, () => saved.session.finals.length >= 5);
    expect(find.text('Demo · Sample data'), findsOneWidget);
    expect(find.textContaining('Sam: I can email'), findsOneWidget);
    expect(find.textContaining("Hi everyone, I'm Zairus"), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mic denied and empty session screens', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final denied = fastApp(MockScenario.micDenied);
    await startSession(tester, denied);
    await tester.pumpAndSettle();
    expect(find.text('Microphone access is off'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    final empty = fastApp(MockScenario.emptySpeech);
    final saved = await startSession(tester, empty);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(saved.session.finals, isEmpty);
    expect(find.text('No speech captured'), findsOneWidget);
    expect(find.text('Delete session'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
