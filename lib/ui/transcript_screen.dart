import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crm/crm_card.dart';
import '../crm/crm_controller.dart';
import '../session/session_controller.dart';
import 'crm_screen.dart';
import 'speaker_chip.dart';

String formatMs(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class TranscriptScreen extends StatelessWidget {
  const TranscriptScreen({super.key, required this.session, required this.crm});

  final SessionController session;
  final CrmController crm;

  String _plainText() => session.finals
      .map(
        (s) =>
            '[${formatMs(s.tStartMs)}] ${session.displayName(session.speakerOf(s))}: ${s.text}',
      )
      .join('\n');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, crm]),
      builder: (context, _) {
        final lines = session.finals;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Transcript'),
            actions: [
              IconButton(
                tooltip: 'Copy text',
                icon: const Icon(Icons.copy),
                onPressed: lines.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: _plainText()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Transcript copied')),
                        );
                      },
              ),
              // TODO(jairus): Share via share_plus once added.
            ],
          ),
          body: Column(
            children: [
              if (session.interrupted)
                const MaterialBanner(
                  content: Text(
                    'Interrupted: this transcript may be incomplete.',
                  ),
                  actions: [SizedBox.shrink()],
                ),
              if (session.hasSuggestions) _SuggestionBanner(session: session),
              _CrmStrip(session: session, crm: crm),
              Expanded(
                child: lines.isEmpty
                    ? const Center(child: Text('No speech captured'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: lines.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final s = lines[i];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 52,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    formatMs(s.tStartMs),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SpeakerChip(
                                      session: session,
                                      speakerId: session.speakerOf(s),
                                    ),
                                    // Tap the line (not the label) to change who said it.
                                    InkWell(
                                      onTap: () => showLineSpeakerPicker(
                                        context,
                                        session,
                                        s,
                                      ),
                                      child: Text(
                                        s.text,
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shown when Stop could not rely on the audio to tell speakers apart and suggested labels.
class _SuggestionBanner extends StatelessWidget {
  const _SuggestionBanner({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SwitchListTile(
        value: session.useSuggestions,
        onChanged: session.setUseSuggestions,
        title: const Text('Suggested speaker labels'),
        subtitle: const Text(
          'The audio could not tell the voices apart, so these labels come from '
          'turn-taking and names. The original labels are kept. Tap a line to fix one.',
        ),
      ),
    );
  }
}

class _CrmStrip extends StatelessWidget {
  const _CrmStrip({required this.session, required this.crm});

  final SessionController session;
  final CrmController crm;

  @override
  Widget build(BuildContext context) {
    if (session.finals.isEmpty) return const SizedBox.shrink();
    final named = crm.namedSpeakers;
    final cards = crm.cards.values.toList();
    final done = cards.where((c) => c.status == CrmStatus.done).length;
    final failed = cards.where((c) => c.status == CrmStatus.failed).length;

    final String text;
    if (named.isEmpty) {
      text =
          'Name a speaker to build a profile. Tap a label to rename, or tap a line to change its speaker.';
    } else if (crm.running) {
      text = 'Building profiles… $done of ${cards.length}';
    } else {
      text =
          '$done profile${done == 1 ? '' : 's'} ready'
          '${failed > 0 ? ' · $failed failed' : ''}';
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(text)),
              ],
            ),
            if (crm.running) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                if (failed > 0 && !crm.running)
                  TextButton(
                    onPressed: crm.retryFailed,
                    child: const Text('Retry CRM'),
                  ),
                if (cards.isNotEmpty)
                  FilledButton.tonal(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CrmScreen(session: session, crm: crm),
                      ),
                    ),
                    child: const Text('Open CRM cards'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
