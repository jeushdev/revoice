import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crm/crm_card.dart';
import '../crm/crm_controller.dart';
import '../session/session_controller.dart';
import 'speaker_chip.dart';
import 'transcript_screen.dart' show formatMs;

class CrmScreen extends StatelessWidget {
  const CrmScreen({super.key, required this.session, required this.crm});

  final SessionController session;
  final CrmController crm;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, crm]),
      builder: (context, _) {
        final cards = crm.cards.values.toList();
        return Scaffold(
          appBar: AppBar(title: const Text('CRM cards')),
          body: cards.isEmpty
              ? const Center(child: Text('Name a speaker to build a profile.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final c in cards)
                      _CardView(session: session, crm: crm, card: c),
                  ],
                ),
        );
      },
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({
    required this.session,
    required this.crm,
    required this.card,
  });

  final SessionController session;
  final CrmController crm;
  final CrmCard card;

  String get _name => session.displayName(card.speakerId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manualName =
        session.speakerNames[card.speakerId]?.source == NameSource.manual;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: speakerColor(card.speakerId),
                  child: Text(
                    _name[0],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_name, style: theme.textTheme.titleLarge)),
                if (card.status == CrmStatus.done)
                  IconButton(
                    tooltip: 'Copy as text',
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: card.toPlainText(_name)),
                    ),
                  ),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                if (manualName) const _Tag('User supplied'),
                if (card.truncated) const _Tag('Based on recent lines only'),
              ],
            ),
            const SizedBox(height: 8),
            ...switch (card.status) {
              CrmStatus.pending || CrmStatus.generating => [
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Building profile…'),
              ],
              CrmStatus.failed => [
                Text(
                  'CRM generation failed',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                if (card.error != null)
                  Text(card.error!, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: crm.running ? null : crm.retryFailed,
                  child: const Text('Retry CRM'),
                ),
              ],
              CrmStatus.done => _fields(context),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _fields(BuildContext context) {
    final rows = <Widget>[
      _field(context, 'Role', 'role', card.role, (v) => card.role = v),
      _field(
        context,
        'Organization',
        'organization',
        card.organization,
        (v) => card.organization = v,
      ),
      _field(
        context,
        'Contact',
        'contact_mentioned',
        card.contactMentioned,
        (v) => card.contactMentioned = v,
      ),
      for (var i = 0; i < card.topics.length; i++)
        _field(
          context,
          'Topic',
          'topics[$i]',
          card.topics[i],
          (v) => card.topics[i] = v ?? '',
        ),
      for (var i = 0; i < card.commitments.length; i++) ...[
        _field(
          context,
          'Commitment',
          'commitments[$i].what',
          card.commitments[i].what,
          (v) => card.commitments[i].what = v ?? '',
        ),
        if (card.commitments[i].due != null)
          _field(
            context,
            '  Due',
            'commitments[$i].due',
            card.commitments[i].due,
            (v) => card.commitments[i].due = v,
          ),
      ],
      _field(
        context,
        'Follow-up',
        'follow_up',
        card.followUp,
        (v) => card.followUp = v,
      ),
      _field(context, 'Notes', 'notes', card.notes, (v) => card.notes = v),
    ].whereType<Widget>().toList();
    if (card.commitments.isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('No commitments stated.'),
        ),
      );
    }
    return rows;
  }

  Widget _field(
    BuildContext context,
    String label,
    String path,
    String? value,
    void Function(String?) setValue,
  ) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final ids = card.evidence[path];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      onTap: () => _edit(context, label, path, value, setValue),
      trailing: card.userEdited.contains(path)
          ? const _Tag('User edited')
          : ids == null
          ? null
          : TextButton(
              onPressed: () => _showSource(context, ids),
              child: const Text('source'),
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    String label,
    String path,
    String value,
    void Function(String?) setValue,
  ) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result == value) return;
    setValue(result.trim().isEmpty ? null : result.trim());
    card.markEdited(path);
    crm.cardEdited();
  }

  void _showSource(BuildContext context, List<String> ids) {
    final byId = {for (final s in session.finals) s.id: s};
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Source lines'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final id in ids)
              if (byId[id] case final s?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '[${formatMs(s.tStartMs)}] ${session.displayName(session.speakerOf(s))}: ${s.text}',
                  ),
                ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    label: Text(text, style: const TextStyle(fontSize: 12)),
  );
}
