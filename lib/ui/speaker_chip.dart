import 'package:flutter/material.dart';

import '../session/session_controller.dart';

const _palette = [
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFE53935),
  Color(0xFF8E24AA),
  Color(0xFFFB8C00),
  Color(0xFF00897B),
];

Color speakerColor(int speakerId) =>
    speakerId == 0 ? Colors.grey : _palette[(speakerId - 1) % _palette.length];

/// Colored label; tap to rename (unknown speakers cannot be renamed).
class SpeakerChip extends StatelessWidget {
  const SpeakerChip({
    super.key,
    required this.session,
    required this.speakerId,
  });

  final SessionController session;
  final int speakerId;

  @override
  Widget build(BuildContext context) {
    final color = speakerColor(speakerId);
    return ActionChip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
      label: Text(
        session.displayName(speakerId),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      onPressed: speakerId == 0
          ? null
          : () => showRenameSheet(context, session, speakerId),
    );
  }
}

Future<void> showRenameSheet(
  BuildContext context,
  SessionController session,
  int speakerId,
) async {
  final controller = TextEditingController(
    text: session.speakerNames[speakerId]?.name ?? '',
  );
  final name = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rename Speaker $speakerId',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (name != null) session.rename(speakerId, name);
}

/// Tap-a-line on the transcript: choose which speaker said this line.
/// Offers every known speaker plus the next free number (up to 4 people).
Future<void> showLineSpeakerPicker(
  BuildContext context,
  SessionController session,
  Segment line,
) {
  final ids = {...session.knownSpeakers, 1, 2};
  final next = ids.reduce((a, b) => a > b ? a : b) + 1;
  if (next <= 4) ids.add(next);
  final options = ids.toList()..sort();
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Who said this line?')),
          for (final id in options)
            ListTile(
              leading: CircleAvatar(
                radius: 8,
                backgroundColor: speakerColor(id),
              ),
              title: Text(session.displayName(id)),
              trailing: session.speakerOf(line) == id
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                session.setLineSpeaker(line.id, id);
                Navigator.pop(sheet);
              },
            ),
        ],
      ),
    ),
  );
}
