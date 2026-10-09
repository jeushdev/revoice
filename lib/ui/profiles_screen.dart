import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../crm/crm_card.dart';
import '../session/session_controller.dart';
import 'rename_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Auto-CRM profiles (mockups 3g, 3h, 3m).
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key, required this.saved});
  final SavedSession saved;

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  int? _selected;
  bool _editing = false;

  SessionController get session => widget.saved.session;

  @override
  Widget build(BuildContext context) {
    final crm = widget.saved.crm;
    return ListenableBuilder(
      listenable: Listenable.merge([session, crm]),
      builder: (context, _) {
        final cards = crm.cards.values.toList();
        final selected = cards.isEmpty
            ? null
            : cards.firstWhere(
                (c) => c.speakerId == _selected,
                orElse: () => cards.first,
              );
        return Scaffold(
          body: AmbientBackground(
            child: SafeArea(
              child: Column(
                children: [
                  NavHeader(
                    backLabel: 'Transcript',
                    title: 'Profiles',
                    trailing: selected?.status == CrmStatus.done
                        ? TextButton(
                            onPressed: () =>
                                setState(() => _editing = !_editing),
                            child: Text(_editing ? 'Done' : 'Edit'),
                          )
                        : null,
                  ),
                  Expanded(
                    child: selected == null
                        ? _noNamed(context)
                        : _profile(context, cards, selected),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _noNamed(BuildContext context) {
    final c = context.rc;
    final unnamed = session.knownSpeakers;
    return StatusMessage(
      icon: Icons.person_add_rounded,
      iconColor: c.primary,
      iconBg: c.pc,
      title: 'Name a speaker\nto build a profile',
      below: unnamed.isEmpty
          ? null
          : Glass(
              child: Column(
                children: [
                  for (var i = 0; i < unnamed.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 14, color: c.line),
                    ListTile(
                      title: Align(
                        alignment: Alignment.centerLeft,
                        child: SessionSpeakerPill(
                          session: session,
                          speakerId: unnamed[i],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Name',
                            style: TextStyle(
                              color: c.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.primary),
                        ],
                      ),
                      onTap: () =>
                          showRenameSheet(context, session, unnamed[i]),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _profile(BuildContext context, List<CrmCard> cards, CrmCard card) {
    final c = context.rc;
    final crm = widget.saved.crm;
    final name = session.displayName(card.speakerId);
    final hue = context.hue(card.speakerId);
    final manual =
        session.speakerNames[card.speakerId]?.source == NameSource.manual;
    final subtitle = [
      card.role,
      card.organization,
    ].whereType<String>().join(', ');
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final k in cards)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _StatusChip(
                    card: k,
                    name: session.displayName(k.speakerId),
                    selected: k == card,
                    onTap: () => setState(() {
                      _selected = k.speakerId;
                      _editing = false;
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: hue.bg,
                  child: Text(
                    initials(name),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: hue.fg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: c.ink2),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (manual)
                    const Tag('User supplied', icon: Icons.edit_rounded),
                  if (card.userEdited.isNotEmpty)
                    const Tag('User edited', icon: Icons.edit_rounded),
                  if ([
                        'name',
                        'role',
                        'organization',
                      ].map((k) => card.evidence[k]).nonNulls.firstOrNull
                      case final ids?)
                    SourceChip(
                      label: _time(ids),
                      onTap: () => _showSource(context, ids),
                    ),
                  if (card.truncated)
                    Tag(
                      'Based on recent lines only',
                      icon: Icons.history_rounded,
                      bg: c.warnc,
                      fg: c.warn,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ...switch (card.status) {
                CrmStatus.pending || CrmStatus.generating => [
                  const SizedBox(height: 40),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(
                    'Building profile…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.ink2),
                  ),
                ],
                CrmStatus.failed => [
                  Glass(
                    color: c.sheet,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.error_rounded, color: c.err, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          'CRM generation failed',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your transcript is safe.',
                          style: TextStyle(color: c.ink2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Retry CRM',
                    icon: Icons.refresh_rounded,
                    onPressed: crm.running ? null : crm.retryFailed,
                  ),
                ],
                CrmStatus.done => _fields(context, card),
              },
            ],
          ),
        ),
        if (card.status == CrmStatus.done)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: PrimaryButton(
              label: 'Copy as text',
              icon: Icons.content_copy_rounded,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: card.toPlainText(name)));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Profile copied')));
              },
            ),
          ),
      ],
    );
  }

  String _time(List<String> ids) {
    final byId = {for (final s in session.finals) s.id: s};
    final first = ids.map((id) => byId[id]).whereType<Segment>().firstOrNull;
    return first == null ? 'source' : formatMs(first.tStartMs);
  }

  List<Widget> _fields(BuildContext context, CrmCard card) {
    final rows = <Widget?>[
      _field(
        context,
        card,
        'Contact mentioned',
        'contact_mentioned',
        card.contactMentioned,
        (v) => card.contactMentioned = v,
      ),
      if (_editing) ...[
        _field(context, card, 'Role', 'role', card.role, (v) => card.role = v),
        _field(
          context,
          card,
          'Organization',
          'organization',
          card.organization,
          (v) => card.organization = v,
        ),
      ],
      for (var i = 0; i < card.topics.length; i++)
        _field(
          context,
          card,
          'Topic',
          'topics[$i]',
          card.topics[i],
          (v) => card.topics[i] = v ?? '',
        ),
      for (var i = 0; i < card.commitments.length; i++)
        _field(
          context,
          card,
          'Commitment',
          'commitments[$i].what',
          card.commitments[i].what,
          (v) => card.commitments[i].what = v ?? '',
          detail: card.commitments[i].due == null
              ? null
              : 'Due ${card.commitments[i].due}',
        ),
      _field(
        context,
        card,
        'Follow-up',
        'follow_up',
        card.followUp,
        (v) => card.followUp = v,
      ),
      _field(
        context,
        card,
        'Notes',
        'notes',
        card.notes,
        (v) => card.notes = v,
      ),
    ].whereType<Widget>().toList();
    if (rows.isEmpty) {
      return [
        Text(
          'Nothing stated yet. Fields fill only from what this person said.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.rc.ink2),
        ),
      ];
    }
    return [
      Glass(
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 14, color: context.rc.line),
              rows[i],
            ],
          ],
        ),
      ),
    ];
  }

  Widget? _field(
    BuildContext context,
    CrmCard card,
    String label,
    String path,
    String? value,
    void Function(String?) setValue, {
    String? detail,
  }) {
    if (value == null || value.isEmpty) return null;
    final c = context.rc;
    final ids = card.evidence[path];
    final edited = card.userEdited.contains(path);
    return InkWell(
      onTap: _editing
          ? () => _edit(context, card, label, path, value, setValue)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: c.ink2)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 16, color: c.ink)),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail,
                        style: TextStyle(fontSize: 13, color: c.ink2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (edited)
              const Tag('User edited', icon: Icons.edit_rounded)
            else if (ids != null)
              SourceChip(
                label: _time(ids),
                onTap: () => _showSource(context, ids),
              ),
            if (_editing)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.edit_rounded, size: 18, color: c.primary),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    CrmCard card,
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
    controller.dispose();
    if (result == null || result == value) return;
    setValue(result.trim().isEmpty ? null : result.trim());
    card.markEdited(path);
    widget.saved.crm.cardEdited();
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
                    '[${formatMs(s.tStartMs)}] ${session.displayName(s.speakerId)}: ${s.text}',
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.card,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final CrmCard card;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final hue = context.hue(card.speakerId);
    final failed = card.status == CrmStatus.failed;
    final Widget lead = switch (card.status) {
      CrmStatus.done when selected => Icon(
        Icons.check_rounded,
        size: 16,
        color: c.okFg,
      ),
      CrmStatus.done => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: hue.dot, shape: BoxShape.circle),
      ),
      CrmStatus.failed => Icon(Icons.error_rounded, size: 16, color: c.warn),
      _ => SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
      ),
    };
    final bg = failed
        ? c.warnc
        : selected
        ? c.okBg
        : c.sheet;
    final fg = failed
        ? c.warn
        : selected
        ? c.okFg
        : c.ink;
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              lead,
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
