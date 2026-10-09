import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revise/app/app_state.dart';
import 'package:revise/engine/mock_caption_engine.dart';
import 'package:revise/main.dart';
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

Future<SavedSession> startSession(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(ReviseApp(app: app));
  await tester.tap(find.bySemanticsLabel('Start session').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return tester.widget<LiveScreen>(find.byType(LiveScreen)).saved;
}

void main() {
  testWidgets('record, stop, transcript and profiles with mock data', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = fastApp();
    final saved = await startSession(tester, app);
    await pumpUntil(
      tester,
      () => saved.session.finals.length == MockCaptionEngine.script.length,
    );
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Demo · Sample data'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await pumpUntil(
      tester,
      () => !saved.crm.running && saved.crm.cards.isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('4 profiles ready'), findsOneWidget);
    expect(app.sessions, [saved]);

    await tester.tap(find.text('4 profiles ready'));
    await tester.pumpAndSettle();
    expect(find.text('Profiles'), findsOneWidget);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    expect(find.text('send the deck'), findsOneWidget);
    expect(find.text('Due Friday morning'), findsOneWidget);
    expect(find.text('Copy as text'), findsOneWidget);
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
    // Leaving mid-session stops it; let the automatic CRM run finish.
    await pumpUntil(
      tester,
      () => !saved.crm.running && saved.crm.cards.isNotEmpty,
    );
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
