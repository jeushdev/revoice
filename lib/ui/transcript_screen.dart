import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_state.dart';
import '../crm/crm_card.dart';
import '../session/session_controller.dart';
import 'live_screen.dart';
import 'profiles_screen.dart';
import 'rename_sheet.dart';
import 'settings_tab.dart' show Segmented;
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

/// Final transcript (mockups 3f, 3k, 3l).
class TranscriptScreen extends StatefulWidget {
  const TranscriptScreen({super.key, required this.saved});
  final SavedSession saved;

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  /// Original is the default: it is authoritative and needs no model.
  bool _clean = false;

  SavedSession get saved => widget.saved;

  String _plainText() {
    final s = saved.session;
    return s.finals
        .map(
          (l) =>
              '[${formatMs(l.tStartMs)}] ${s.displayName(l.speakerId)}: '
              '${_clean ? saved.clean.textFor(l) : l.text}',
        )
        .join('\n');
  }

  void _maybeClean() {
    final crm = saved.crm;
    final clean = saved.clean;
    if (_clean && !crm.running && !clean.running && clean.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => clean.run());
    }
  }

  void _openProfiles() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ProfilesScreen(saved: saved)),
  );

  @override
  Widget build(BuildContext context) {
    final session = saved.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session, saved.crm, saved.clean]),
      builder: (context, _) {
        _maybeClean();
        final c = context.rc;
        final lines = session.finals;
        return Scaffold(
          body: AmbientBackground(
            child: SafeArea(
              child: Column(
                children: [
                  NavHeader(
                    backLabel: 'Library',
                    title: 'Transcript',
                    subtitle: sessionSubtitle(saved),
                  ),
                  Expanded(
                    child: lines.isEmpty
                        ? _empty(context)
                        : ListView(
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
                              _ProfilesCard(
                                saved: saved,
                                onOpen: _openProfiles,
                              ),
                              const SizedBox(height: 12),
                              Segmented(
                                options: const ['Clean', 'Original'],
                                index: _clean ? 0 : 1,
                                expand: true,
                                onChanged: (i) =>
                                    setState(() => _clean = i == 0),
                              ),
                              if (_clean &&
                                  (saved.crm.running || saved.clean.running))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    saved.crm.running
                                        ? 'Cleaning starts after profiles are built. Showing original lines.'
                                        : 'Cleaning lines…',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.ink2,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              for (final l in lines) _line(context, l),
                              if (session.interrupted)
                                _InterruptDivider(
                                  atMs: session.interruptedAtMs ?? 0,
                                ),
                            ],
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
                                  const SnackBar(
                                    content: Text('Transcript copied'),
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

  Widget _line(BuildContext context, Segment l) {
    final c = context.rc;
    final session = saved.session;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
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

class _ProfilesCard extends StatelessWidget {
  const _ProfilesCard({required this.saved, required this.onOpen});
  final SavedSession saved;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final crm = saved.crm;
    final cards = crm.cards.values.toList();
    final done = cards.where((x) => x.status == CrmStatus.done).length;
    final failed = cards.where((x) => x.status == CrmStatus.failed).length;
    final String text;
    if (crm.namedSpeakers.isEmpty) {
      text = 'Name a speaker to build a profile';
    } else if (crm.running) {
      text = 'Building profiles… $done of ${cards.length}';
    } else {
      text =
          '$done profile${done == 1 ? '' : 's'} ready'
          '${failed > 0 ? ' · $failed failed' : ''}';
    }
    return Glass(
      color: c.pc.withValues(alpha: 0.85),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.opc,
                      ),
                    ),
                  ),
                  if (failed > 0 && !crm.running)
                    TextButton(
                      onPressed: crm.retryFailed,
                      child: const Text('Retry CRM'),
                    ),
                  Icon(Icons.chevron_right_rounded, color: c.opc),
                ],
              ),
              if (crm.running) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: cards.isEmpty ? null : done / cards.length,
                    minHeight: 5,
                    color: c.primaryFill,
                    backgroundColor: c.surf,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
