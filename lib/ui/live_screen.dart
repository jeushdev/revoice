import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../engine/engine_events.dart';
import '../session/session_controller.dart';
import 'landscape_captions.dart';
import 'names_sheet.dart';
import 'rename_sheet.dart';
import 'settings_tab.dart';
import 'theme.dart';
import 'transcript_screen.dart';
import 'widgets.dart';

/// Asks for names (optional, Settings can turn it off), then starts a new
/// session and opens Live captions.
Future<void> openLiveSession(BuildContext context) async {
  final app = AppScope.read(context);
  var names = const <String>[];
  if (app.askNames) {
    final picked = await showNamesSheet(context, recent: app.recentNames);
    if (picked == null || !context.mounted) return; // dismissed
    names = picked;
  }
  final saved = app.newSession()..session.expectedNames = names;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => LiveScreen(saved: saved)),
  );
}

/// Live captions (mockup 3d). Rotating the phone, or the full screen button,
/// switches to the landscape caption view (3n-3r).
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.saved});
  final SavedSession saved;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final _scroll = ScrollController();
  Timer? _ticker;
  bool _stopping = false;
  bool _starting = true;

  SessionController get session => widget.saved.session;

  @override
  void initState() {
    super.initState();
    // Only this screen rotates; the rest of the app is portrait.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    session.addListener(_autoScroll);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && session.state == EngineState.listening) setState(() {});
    });
    _begin();
  }

  Future<void> _begin() async {
    setState(() => _starting = true);
    final app = AppScope.read(context);
    await session.init();
    if (!mounted) return;
    app.update(() => app.sttReady = session.initResult?.sttReady);
    if (session.errorMessage == null) await session.start();
    if (mounted) setState(() => _starting = false);
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    final app = AppScope.read(context);
    await session.stop();
    if (!mounted) return;
    // Saved on Stop; the on-device summary starts right away.
    app
      ..save(widget.saved)
      ..update(() => app.tab = 0);
    unawaited(widget.saved.summary.run());
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TranscriptScreen(saved: widget.saved),
      ),
    );
  }

  void _rename(int id) => showRenameSheet(context, session, id);

  Future<void> _enterFullScreen() => SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
  );

  Future<void> _exitFullScreen() => SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp],
  );

  @override
  void dispose() {
    _ticker?.cancel();
    session.removeListener(_autoScroll);
    _scroll.dispose();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    // A session closed before it started has nothing to keep.
    if (!_stopping) {
      final state = session.state;
      if (state == EngineState.listening || state == EngineState.paused) {
        unawaited(session.stop());
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final code = session.lastErrorCode;
        if (!_starting && code == EngineErrorCode.permissionDenied) {
          return _page(
            StatusMessage(
              icon: Icons.mic_off_rounded,
              iconColor: context.rc.err,
              iconBg: context.rc.errc,
              title: 'Microphone access is off',
              body: 'ReVise needs the microphone to caption.',
              actions: [
                PrimaryButton(
                  label: 'Open Settings',
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Open Settings > ReVise > Microphone, then tap Retry.',
                      ),
                    ),
                  ),
                ),
                GlassButton(label: 'Retry', onPressed: _begin),
              ],
            ),
          );
        }
        if (!_starting && code == EngineErrorCode.modelMissing) {
          return _page(
            StatusMessage(
              icon: Icons.warning_amber_rounded,
              iconColor: context.rc.warn,
              iconBg: context.rc.warnc,
              title: 'Speech model missing',
              body: "Captions can't start until it's restored.",
              actions: [
                PrimaryButton(
                  label: 'Check again',
                  icon: Icons.refresh_rounded,
                  onPressed: _begin,
                ),
              ],
            ),
          );
        }
        if (!_starting &&
            session.state != EngineState.listening &&
            session.state != EngineState.paused &&
            session.state != EngineState.error &&
            session.errorMessage != null) {
          return _page(
            StatusMessage(
              icon: Icons.error_outline_rounded,
              iconColor: context.rc.err,
              iconBg: context.rc.errc,
              title: "Captions couldn't start",
              body: session.errorMessage,
              actions: [
                PrimaryButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onPressed: _begin,
                ),
              ],
            ),
          );
        }
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        if (landscape) {
          return LandscapeCaptions(
            session: session,
            demo: AppScope.of(context).sampleData,
            onStop: _stop,
            onExit: _exitFullScreen,
          );
        }
        return _portrait(context);
      },
    );
  }

  Widget _page(Widget child) => Scaffold(
    body: AmbientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CircleIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );

  Widget _portrait(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.rc;
    final state = session.state;
    final paused = state == EngineState.paused;
    final canStop =
        !_stopping &&
        (state == EngineState.listening ||
            paused ||
            state == EngineState.error);
    return Scaffold(
      body: AmbientBackground(
        plain: true,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    _StatePill(state: state),
                    const SizedBox(width: 12),
                    Text(
                      formatMs(session.elapsed.inMilliseconds),
                      style: TextStyle(
                        fontSize: 16,
                        color: c.ink2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: app.sampleData
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Tag(
                                'Demo · Sample data',
                                icon: Icons.science_rounded,
                                bg: c.surf2,
                                fg: c.ink2,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    CircleIconButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: 'Full screen',
                      onPressed: _enterFullScreen,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Glass(
                  color: c.surf2.withValues(alpha: 0.8),
                  child: TextSizeSlider(
                    value: app.textSize,
                    onChanged: (v) => app.update(() => app.textSize = v),
                  ),
                ),
              ),
              if (session.expectedNames.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Row(
                    children: [
                      Icon(Icons.group_rounded, size: 16, color: c.ink3),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Expecting: ${session.expectedNames.join(', ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
              if (session.interrupted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: WarnBanner(
                    text:
                        'Mic interrupted at ${formatMs(session.interruptedAtMs ?? 0)}. '
                        'Earlier lines are saved.',
                  ),
                ),
              Expanded(child: _captions(context, app.textSize)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: paused ? 'Resume' : 'Pause',
                        icon: paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        color: c.ink,
                        onPressed: switch (state) {
                          EngineState.listening => session.pause,
                          EngineState.paused => session.resume,
                          _ => null,
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Stop',
                        icon: Icons.stop_rounded,
                        color: c.err,
                        onPressed: canStop ? _stop : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _captions(BuildContext context, double size) {
    final c = context.rc;
    final lines = [...session.finals, ...session.partials];
    if (lines.isEmpty) {
      return Center(
        child: Text(
          _starting
              ? 'Starting…'
              : session.state == EngineState.listening
              ? 'Listening…'
              : '',
          style: TextStyle(fontSize: size, color: c.ink3),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final seg = lines[i];
        return FadeInOnce(
          key: ValueKey(seg.id),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SessionSpeakerPill(
                      session: session,
                      speakerId: seg.speakerId,
                      onRename: _rename,
                      showEdit: true,
                    ),
                    const Spacer(),
                    Text(
                      formatMs(seg.tStartMs),
                      style: TextStyle(fontSize: 13, color: c.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CaptionText(
                  text: seg.text,
                  partial: !seg.isFinal,
                  style: TextStyle(
                    fontSize: size,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                  cursorColor: c.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Caption text; partial lines are dimmed and end with a cursor.
class CaptionText extends StatelessWidget {
  const CaptionText({
    super.key,
    required this.text,
    required this.partial,
    required this.style,
    required this.cursorColor,
    this.prefix,
  });

  final String text;
  final bool partial;
  final TextStyle style;
  final Color cursorColor;
  final InlineSpan? prefix;

  @override
  Widget build(BuildContext context) {
    final color = style.color!;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: partial ? 0.55 : 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, alpha, _) => Text.rich(
        TextSpan(
          style: style.copyWith(color: color.withValues(alpha: alpha)),
          children: [
            ?prefix,
            TextSpan(text: text),
            if (partial)
              TextSpan(
                text: '|',
                style: TextStyle(
                  color: cursorColor,
                  fontWeight: FontWeight.w300,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});
  final EngineState? state;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final (label, bg, fg, dot) = switch (state) {
      EngineState.listening => ('Listening', c.okBg, c.okFg, c.okDot),
      EngineState.paused => ('Paused', c.warnc, c.warnInk, c.warn),
      EngineState.error => ('Interrupted', c.errc, c.errText, c.err),
      EngineState.stopped => ('Stopped', c.surf2, c.ink2, c.ink3),
      _ => ('Starting', c.surf2, c.ink2, c.ink3),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                label,
                key: ValueKey(label),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
