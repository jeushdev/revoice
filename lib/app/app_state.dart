import 'package:flutter/widgets.dart';

import '../crm/crm_controller.dart';
import '../engine/caption_engine.dart';
import '../engine/mock_caption_engine.dart';
import '../engine/platform_caption_engine.dart';
import '../session/clean_transcript.dart';
import '../session/session_controller.dart';

/// One recorded session in the Library.
class SavedSession {
  SavedSession(this.session, this.crm)
    : clean = CleanTranscript(session.engine, session, lock: crm.lock);
  final SessionController session;
  final CrmController crm;
  final CleanTranscript clean;

  DateTime get startedAt => session.startedAt ?? DateTime.now();
  Duration get duration => session.elapsed;
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
    return SavedSession(session, CrmController(session.engine, session));
  }

  void save(SavedSession s) {
    if (!sessions.contains(s)) sessions.insert(0, s);
    notifyListeners();
  }

  void delete(SavedSession s) {
    sessions.remove(s);
    notifyListeners();
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
