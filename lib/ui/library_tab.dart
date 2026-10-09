import 'package:flutter/material.dart';

import '../app/app_state.dart';
import 'theme.dart';
import 'transcript_screen.dart';
import 'widgets.dart';

/// Library tab (mockup 3b): sessions grouped Today / This week / Earlier.
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  static String _group(DateTime t, DateTime now) {
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.rc;
    final now = DateTime.now();
    final groups = <String, List<SavedSession>>{};
    for (final s in app.sessions) {
      groups.putIfAbsent(_group(s.startedAt, now), () => []).add(s);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        const LargeTitle('Library'),
        if (app.sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 120),
            child: Column(
              children: [
                Icon(Icons.library_books_rounded, size: 44, color: c.ink3),
                const SizedBox(height: 12),
                Text(
                  'No sessions yet',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start one from Record.',
                  style: TextStyle(fontSize: 14, color: c.ink2),
                ),
              ],
            ),
          ),
        for (final entry in groups.entries) ...[
          SectionLabel(entry.key),
          Glass(
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 14, color: c.line),
                  ListenableBuilder(
                    listenable: entry.value[i].session,
                    builder: (_, _) =>
                        _SessionRow(saved: entry.value[i], group: entry.key),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.saved, required this.group});
  final SavedSession saved;
  final String group;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String _when(DateTime t) {
    if (group == 'Today') return _time(t);
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (t.year == yesterday.year &&
        t.month == yesterday.month &&
        t.day == yesterday.day) {
      return 'Yesterday, ${_time(t)}';
    }
    return '${_weekdays[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}, ${_time(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final session = saved.session;
    final speakers = session.knownSpeakers;
    final minutes = (saved.duration.inSeconds / 60).ceil().clamp(1, 9999);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => TranscriptScreen(saved: saved)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _when(saved.startedAt),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Text(
                        '$minutes min',
                        style: TextStyle(fontSize: 13, color: c.ink2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (session.finals.isEmpty)
                        Text(
                          'No speech',
                          style: TextStyle(fontSize: 13, color: c.ink2),
                        )
                      else ...[
                        for (final id in speakers.take(4))
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: context.hue(id).dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            speakers.map(session.displayName).join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: c.ink2),
                          ),
                        ),
                      ],
                      if (session.interrupted) ...[
                        const SizedBox(width: 6),
                        Tag('Interrupted', bg: c.warnc, fg: c.warn),
                      ],
                    ],
                  ),
                  ListenableBuilder(
                    listenable: saved.summary,
                    builder: (context, _) {
                      final text = saved.summary.summary;
                      if (text == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6, right: 8),
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            color: c.ink,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.ink3),
          ],
        ),
      ),
    );
  }
}
