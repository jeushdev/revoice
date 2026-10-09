import 'package:flutter/widgets.dart';

import '../ai/meeting_ai_controller.dart';
import '../engine/caption_engine.dart';
import '../engine/mock_caption_engine.dart';
import '../engine/platform_caption_engine.dart';
import '../session/clean_transcript.dart';
import '../session/session_controller.dart';
import '../summary/summary_controller.dart';

/// One recorded session in the Library.
class SavedSession {
  SavedSession(this.session, this.summary)
    : clean = CleanTranscript(session.engine, session, lock: summary.lock),
      ai = MeetingAiController(
        session.engine,
        session,
        autoRun: false,
        lock: summary.lock,
      );
  final SessionController session;
  final SummaryController summary;
  /// Per-line LLM clean-up. Kept in code but NOT reachable from the UI (too slow on the phone).
  final CleanTranscript clean;

  /// Clean transcript (merge rules, no model) and the rest of the meeting AI logic.
  final MeetingAiController ai;

  DateTime get startedAt => session.startedAt ?? DateTime.now();
  Duration get duration => session.elapsed;

  /// Releases everything this session holds (transcript, summary, answers, engine). Sessions are
  /// kept in memory only, so after this no trace of it is left on the phone.
  void dispose() {
    summary.dispose();
    ai.dispose();
    clean.dispose();
    session.dispose();
  }
}

/// App-wide settings and the session Library.
// TODO(jairus): persist sessions and settings in app-private storage (PRD F2).
class AppState extends ChangeNotifier {
  AppState({this.engineFactory});

  /// Test hook: overrides how engines are created.
  final CaptionEngine Function(AppState app)? engineFactory;

  /// Portrait caption size (Settings and the live slider share it).
  double textSize = 28;

  /// Landscape caption size (A- / A+ in the landscape controls).
  double landscapeTextSize = 56;

  /// Landscape captions: white on black when true.
  bool landscapeDark = true;

  /// Show the optional "Who's in this conversation?" sheet before recording.
  bool askNames = true;

  /// Replays a scripted conversation instead of the native engine. On by
  /// default until Moonshine is wired in on both platforms.
  bool sampleData = true;
  MockScenario scenario = MockScenario.meeting;

  /// From the last `init`; null until a session has started once.
  bool? sttReady;

  final List<SavedSession> sessions = [];

  /// Selected bottom tab: 0 Library, 1 Record, 2 Settings.
  int tab = 1;

  CaptionEngine createEngine() =>
      engineFactory?.call(this) ??
      (sampleData
          ? MockCaptionEngine(scenario: scenario)
          : PlatformCaptionEngine());

  SavedSession newSession() {
    final session = SessionController(createEngine());
    return SavedSession(session, SummaryController(session.engine, session));
  }

  /// Names from recent sessions (entered or heard), newest first.
  List<String> get recentNames {
    final seen = <String>{};
    final out = <String>[];
    for (final s in sessions) {
      final names = [
        ...s.session.expectedNames,
        ...s.session.speakerNames.values.map((n) => n.name),
      ];
      for (final n in names) {
        if (seen.add(n.toLowerCase())) out.add(n);
      }
    }
    return out.take(8).toList();
  }

  void save(SavedSession s) {
    if (!sessions.contains(s)) sessions.insert(0, s);
    notifyListeners();
  }

  /// Removes a session and frees all of its data. The screens that showed it are rebuilt first;
  /// the controllers are disposed after that frame so nothing listens to a disposed object.
  void delete(SavedSession s) {
    sessions.remove(s);
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => s.dispose());
  }

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child})
    : super(notifier: app);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
