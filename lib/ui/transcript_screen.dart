import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_state.dart';
import '../session/session_controller.dart';
import '../summary/summary_controller.dart';
import 'live_screen.dart';
import 'rename_sheet.dart';
import 'settings_tab.dart' show Segmented;
import 'summary_view.dart';
import 'theme.dart';
import 'widgets.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String sessionSubtitle(SavedSession s) {
  final t = s.startedAt;
  final secs = s.duration.inSeconds;
  final length = secs < 60
      ? formatMs(secs * 1000).replaceFirst(RegExp('^0'), '')
      : '${(secs / 60).round()} min';
  return '${_months[t.month - 1]} ${t.day} · $length';
}

/// A saved session: the on-device Summary (default) and the Transcript.
class TranscriptScreen extends StatefulWidget {
  const TranscriptScreen({super.key, required this.saved});
  final SavedSession saved;

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  /// 0 Summary, 1 Transcript.
  int _tab = 0;

  /// Original is the default: it is authoritative and needs no model.
  bool _clean = false;

  /// Lines a summary answer pointed to; tinted briefly in the transcript.
  Set<String> _highlight = const {};
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _lineKeys = {};

  SavedSession get saved => widget.saved;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  String _plainText() {
    final s = saved.session;
    if (_tab == 0 && saved.summary.status == SummaryStatus.done) {
      return saved.summary.plainText();
    }
    return s.finals
        .map(
          (l) =>
              '[${formatMs(l.tStartMs)}] ${s.displayName(l.speakerId)}: '
              '${_clean ? saved.clean.textFor(l) : l.text}',
        )
        .join('\n');
  }

  void _maybeClean() {
    final clean = saved.clean;
    if (_clean &&
        !saved.summary.running &&
        !clean.running &&
        clean.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => clean.run());
    }
  }

  void _showSource(List<String> ids) {
    setState(() {
      _tab = 1;
      _highlight = ids.toSet();
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlight = const {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _lineKeys[ids.first]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = saved.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session, saved.summary, saved.clean]),
      builder: (context, _) {
        _maybeClean();
        final lines = session.finals;
        return Scaffold(
          body: AmbientBackground(
            child: SafeArea(
              child: Column(
                children: [
                  NavHeader(
                    backLabel: 'Library',
                    title: 'Session',
                    subtitle: sessionSubtitle(saved),
                  ),
                  if (lines.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Segmented(
                        options: const ['Summary', 'Transcript'],
                        index: _tab,
                        expand: true,
                        onChanged: (i) => setState(() => _tab = i),
                      ),
                    ),
                  Expanded(
                    child: lines.isEmpty
                        ? _empty(context)
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            child: _tab == 0
                                ? SummaryView(
                                    key: const ValueKey('summary'),
                                    saved: saved,
                                    onSkip: () => setState(() => _tab = 1),
                                    onShowSource: _showSource,
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('transcript'),
                                    child: _transcript(context, lines),
                                  ),
                          ),
                  ),
                  if (lines.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: GlassButton(
                              label: 'Copy',
                              icon: Icons.content_copy_rounded,
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: _plainText()),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _tab == 0 &&
                                              saved.summary.status ==
                                                  SummaryStatus.done
                                          ? 'Summary copied'
                                          : 'Transcript copied',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PrimaryButton(
                              label: 'Share text',
                              icon: Icons.ios_share_rounded,
                              onPressed: () => SharePlus.instance.share(
                                ShareParams(text: _plainText()),
                              ),
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
      },
    );
  }

  Widget _transcript(BuildContext context, List<Segment> lines) {
    final c = context.rc;
    final session = saved.session;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (session.interrupted) ...[
          WarnBanner(
            text:
                'Mic interrupted at ${formatMs(session.interruptedAtMs ?? 0)}. '
                'Earlier lines are saved.',
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                _clean && (saved.summary.running || saved.clean.running)
                    ? saved.summary.running
                          ? 'Cleaning starts after the summary.'
                          : 'Cleaning lines…'
                    : '${lines.length} lines',
                style: TextStyle(fontSize: 13, color: c.ink2),
              ),
            ),
            Segmented(
              options: const ['Clean', 'Original'],
              index: _clean ? 0 : 1,
              onChanged: (i) => setState(() => _clean = i == 0),
            ),
          ],
        ),
        for (final l in lines) _line(context, l),
        if (session.interrupted)
          _InterruptDivider(atMs: session.interruptedAtMs ?? 0),
      ],
    );
  }

  Widget _line(BuildContext context, Segment l) {
    final c = context.rc;
    final session = saved.session;
    final lit = _highlight.contains(l.id);
    return AnimatedContainer(
      key: _lineKeys.putIfAbsent(l.id, GlobalKey.new),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: lit ? c.pc.withValues(alpha: .9) : c.pc.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SessionSpeakerPill(
                session: session,
                speakerId: l.speakerId,
                onRename: (id) => showRenameSheet(context, session, id),
              ),
              const SizedBox(width: 10),
              Text(
                formatMs(l.tStartMs),
                style: TextStyle(fontSize: 13, color: c.ink3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _clean ? saved.clean.textFor(l) : l.text,
            style: TextStyle(fontSize: 17, height: 1.35, color: c.ink),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.rc;
    final app = AppScope.read(context);
    return StatusMessage(
      icon: Icons.voice_over_off_rounded,
      iconColor: c.ink2,
      iconBg: c.surf3,
      title: 'No speech captured',
      body: 'Move the phone closer and try again.',
      actions: [
        PrimaryButton(
          label: 'Start new session',
          icon: Icons.mic_rounded,
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            openLiveSession(nav.context);
          },
        ),
        GlassButton(
          label: 'Delete session',
          color: c.errText,
          onPressed: () {
            app.delete(saved);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class _InterruptDivider extends StatelessWidget {
  const _InterruptDivider({required this.atMs});
  final int atMs;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.warn)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.mic_off_rounded, size: 16, color: c.warn),
                const SizedBox(width: 4),
                Text(
                  'Interrupted · ${formatMs(atMs)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.warn,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Divider(color: c.warn)),
        ],
      ),
    );
  }
}
