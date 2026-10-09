import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revise/app/app_state.dart';
import 'package:revise/engine/mock_caption_engine.dart';
import 'package:revise/summary/summary_controller.dart';

import 'screens_smoke_test.dart' show pumpUntil, startSession;

/// Counts per-line LLM clean-up calls: the UI must never make any.
class CountingMock extends MockCaptionEngine {
  CountingMock()
    : super(
        wordInterval: const Duration(milliseconds: 1),
        turnGap: const Duration(milliseconds: 1),
        llmDelay: const Duration(milliseconds: 1),
      );
  int cleanLineCalls = 0;

  @override
  Future<String> cleanLine({required String text, required String prompt, int maxTokens = 512}) {
    cleanLineCalls++;
    return super.cleanLine(text: text, prompt: prompt, maxTokens: maxTokens);
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearAccessibilityFeaturesTestValue());

  testWidgets('Switch speaker / Auto on the live screen; Clean toggle is rules only', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late CountingMock engine;
    final app = AppState(engineFactory: (_) => engine = CountingMock());
    final saved = await startSession(tester, app);
    final session = saved.session;
    await pumpUntil(tester, () => session.finals.length >= 3);

    expect(session.liveSpeakerOverride, isNull);
    await tester.tap(find.text('Switch speaker'));
    await tester.pump();
    expect(session.liveSpeakerOverride, isNotNull);
    await tester.tap(find.text('Auto'));
    await tester.pump();
    expect(session.liveSpeakerOverride, isNull);

    await pumpUntil(tester, () => session.finals.length == MockCaptionEngine.script.length);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(tester, () => saved.summary.status == SummaryStatus.done);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clean'));
    await tester.pumpAndSettle();
    expect(saved.ai.cleanTurns, isNotEmpty);
    expect(find.text('${saved.ai.cleanTurns.length} turns'), findsOneWidget);
    expect(engine.cleanLineCalls, 0); // his per-line LLM clean never runs
    expect(saved.clean.running, isFalse);
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    expect(find.text('${session.finals.length} lines'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
