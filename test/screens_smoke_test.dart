import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revise/crm/crm_controller.dart';
import 'package:revise/engine/mock_caption_engine.dart';
import 'package:revise/session/session_controller.dart';
import 'package:revise/ui/crm_screen.dart';
import 'package:revise/ui/live_screen.dart';
import 'package:revise/ui/transcript_screen.dart';

void main() {
  testWidgets('live, transcript and CRM screens render mock data', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = SessionController(
      MockCaptionEngine(
        wordInterval: const Duration(milliseconds: 1),
        turnGap: const Duration(milliseconds: 1),
        llmDelay: const Duration(milliseconds: 1),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: LiveScreen(session: session, demo: true)),
    );
    for (var i = 0; i < 400 && session.finals.length < 8; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('Zairus'), findsWidgets);
    expect(find.text('Demo / Sample data'), findsOneWidget);

    final crm = CrmController(session.engine, session);
    final stopped = session.stop();
    await tester.pump(const Duration(milliseconds: 10));
    await stopped;
    final generated = crm.generateMissing();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await generated;
    await tester.pumpWidget(
      MaterialApp(
        home: TranscriptScreen(session: session, crm: crm),
      ),
    );
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('4 profiles ready'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: CrmScreen(session: session, crm: crm),
      ),
    );
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('send the deck'), findsOneWidget);
    expect(find.text('source'), findsWidgets);
  });
}
