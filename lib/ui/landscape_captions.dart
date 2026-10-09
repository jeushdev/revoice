import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../engine/engine_events.dart';
import '../session/session_controller.dart';
import 'live_screen.dart' show CaptionText;
import 'theme.dart';
import 'widgets.dart';

/// Landscape personal captions (mockups 3n-3r): the last few lines in very
/// large text. Tap to show controls; they hide after 3 seconds.
class LandscapeCaptions extends StatefulWidget {
  const LandscapeCaptions({
    super.key,
    required this.session,
    required this.demo,
    required this.onStop,
    required this.onExit,
  });

  final SessionController session;
  final bool demo;
  final VoidCallback onStop;
  final VoidCallback onExit;

  @override
  State<LandscapeCaptions> createState() => _LandscapeCaptionsState();
}

class _LandscapeCaptionsState extends State<LandscapeCaptions> {
  bool _controls = false;
  Timer? _hide;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _hide?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showControls() {
    _hide?.cancel();
    setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final dark = app.landscapeDark;
    final bg = dark ? Colors.black : Colors.white;
    final ink = dark ? Colors.white : const Color(0xFF0B0B0F);
    final brightness = dark ? Brightness.dark : Brightness.light;
    final state = session.state;
    final lines = [...session.finals, ...session.partials];
    final shown = lines.length > 3 ? lines.sublist(lines.length - 3) : lines;
    final size = app.landscapeTextSize;
    // Panels follow the caption contrast, not the system theme.
    return Theme(
      data: buildTheme(brightness),
      child: Builder(
        builder: (context) {
          final c = context.rc;
          return Scaffold(
            backgroundColor: bg,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showControls,
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 12, 64, 16),
                        child: shown.isEmpty
                            ? Center(
                                child: Text(
                                  state == EngineState.listening
                                      ? 'Listening…'
                                      : '',
                                  style: TextStyle(
                                    fontSize: size * 0.75,
                                    fontWeight: FontWeight.w700,
                                    color: ink.withValues(alpha: 0.6),
                                  ),
                                ),
                              )
                            : ClipRect(
                                child: OverflowBox(
                                  alignment: Alignment.bottomLeft,
                                  maxHeight: double.infinity,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (var i = 0; i < shown.length; i++)
                                        _line(
                                          shown[i],
                                          age: shown.length - 1 - i,
                                          size: size,
                                          ink: ink,
                                          brightness: brightness,
                                          cursor: c.primary,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                    if (widget.demo)
                      Positioned(
                        left: 24,
                        top: 8,
                        child: Tag(
                          'Demo · Sample data',
                          icon: Icons.science_rounded,
                          bg: c.surf2,
                          fg: c.ink2,
                        ),
                      ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _StatusDot(state: state),
                    ),
                    if (session.interrupted)
                      Positioned(
                        left: 24,
                        right: 24,
                        top: 8,
                        child: WarnBanner(
                          text:
                              'Microphone interrupted at ${formatMs(session.interruptedAtMs ?? 0)}. '
                              'Captions so far are saved.',
                          action: _BlackButton(
                            label: 'Save',
                            onPressed: widget.onStop,
                          ),
                        ),
                      )
                    else if (state == EngineState.paused && !_controls)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(child: _pausedPill(c)),
                      ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 380),
                      curve: _controls
                          ? Curves.easeOutBack
                          : Curves.easeInCubic,
                      top: _controls ? 8 : -80,
                      left: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 240),
                        opacity: _controls ? 1 : 0,
                        child: Center(child: _controlsPill(app, c)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _line(
    Segment seg, {
    required int age,
    required double size,
    required Color ink,
    required Brightness brightness,
    required Color cursor,
  }) {
    final hue = speakerHue(seg.speakerId, brightness);
    final opacity = switch (age) {
      0 => 1.0,
      1 => 0.7,
      _ => 0.4,
    };
    final nameColor = brightness == Brightness.dark ? hue.dot : hue.fg;
    return FadeInOnce(
      key: ValueKey(seg.id),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        opacity: opacity,
        child: Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: hue.dot, width: 5)),
          ),
          child: CaptionText(
            text: seg.text,
            partial: !seg.isFinal,
            cursorColor: cursor,
            prefix: TextSpan(
              text: '${session.displayName(seg.speakerId)}: ',
              style: TextStyle(color: nameColor),
            ),
            style: TextStyle(
              fontSize: size,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pausedPill(ReviseColors c) => Glass(
    radius: 30,
    color: c.sheet,
    padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.pause_circle_rounded, color: c.warn),
        const SizedBox(width: 8),
        Text(
          'Paused',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(width: 12),
        _BlackButton(
          label: 'Resume',
          icon: Icons.play_arrow_rounded,
          onPressed: session.resume,
        ),
      ],
    ),
  );

  Widget _controlsPill(AppState app, ReviseColors c) {
    final paused = session.state == EngineState.paused;
    Widget icon(IconData i, String tip, VoidCallback? onTap, {Color? color}) =>
        IconButton(
          tooltip: tip,
          onPressed: onTap == null
              ? null
              : () {
                  onTap();
                  _showControls();
                },
          icon: Icon(i, color: color ?? c.ink),
        );
    return Glass(
      radius: 32,
      color: c.sheet,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon(
            Icons.text_decrease_rounded,
            'Smaller text',
            () => app.update(
              () => app.landscapeTextSize = (app.landscapeTextSize - 4).clamp(
                32,
                96,
              ),
            ),
          ),
          Text(
            '${app.landscapeTextSize.round()}',
            style: TextStyle(fontSize: 13, color: c.ink2),
          ),
          icon(
            Icons.text_increase_rounded,
            'Larger text',
            () => app.update(
              () => app.landscapeTextSize = (app.landscapeTextSize + 4).clamp(
                32,
                96,
              ),
            ),
          ),
          icon(
            Icons.contrast_rounded,
            'Contrast',
            () => app.update(() => app.landscapeDark = !app.landscapeDark),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: c.ink),
            onPressed: switch (session.state) {
              EngineState.listening => session.pause,
              EngineState.paused => session.resume,
              _ => null,
            },
            icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            label: Text(paused ? 'Resume' : 'Pause'),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.err,
              foregroundColor: Colors.white,
            ),
            onPressed: widget.onStop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Stop'),
          ),
          icon(
            Icons.fullscreen_exit_rounded,
            'Exit full screen',
            widget.onExit,
          ),
        ],
      ),
    );
  }
}

class _BlackButton extends StatelessWidget {
  const _BlackButton({required this.label, this.icon, this.onPressed});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF0B0B0F),
      foregroundColor: Colors.white,
      shape: const StadiumBorder(),
    ),
    onPressed: onPressed,
    icon: icon == null ? null : Icon(icon, size: 20),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state});
  final EngineState? state;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final child = switch (state) {
      EngineState.listening => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c.okDot, shape: BoxShape.circle),
      ),
      EngineState.paused => Icon(
        Icons.pause_circle_rounded,
        size: 20,
        color: c.warn,
      ),
      EngineState.error => Icon(Icons.mic_off_rounded, size: 18, color: c.warn),
      _ => const SizedBox.shrink(),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surf2, shape: BoxShape.circle),
      child: child,
    );
  }
}
