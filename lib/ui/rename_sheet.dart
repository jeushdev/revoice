import 'package:flutter/material.dart';

import '../session/name_rules.dart';
import '../session/session_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// Names heard in the conversation that are not yet anyone's name.
List<String> heardNames(SessionController session) {
  final taken = {for (final n in session.speakerNames.values) n.name};
  final heard = <String>{};
  for (final s in session.finals) {
    for (final n in [selfIntroName(s.text), calledName(s.text)]) {
      if (n != null && !taken.contains(n)) heard.add(n);
    }
  }
  return heard.toList();
}

/// Rename sheet (mockup 3e). Manual names always win over detected ones.
Future<void> showRenameSheet(
  BuildContext context,
  SessionController session,
  int speakerId,
) async {
  final name = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 420),
      reverseDuration: Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    ),
    builder: (_) => _RenameSheet(session: session, speakerId: speakerId),
  );
  if (name != null) session.rename(speakerId, name);
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.session, required this.speakerId});
  final SessionController session;
  final int speakerId;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _text = TextEditingController(
    text: widget.session.speakerNames[widget.speakerId]?.name ?? '',
  );
  late final _heard = heardNames(widget.session);

  /// Names entered before recording that no speaker has yet.
  late final _expected = widget.session.expectedNames
      .where(
        (n) =>
            !_heard.contains(n) &&
            !widget.session.speakerNames.values.any(
              (s) => s.name.toLowerCase() == n.toLowerCase(),
            ),
      )
      .toList();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _text.text);

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final current = 'Speaker ${widget.speakerId}';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Glass(
        radius: 32,
        color: c.sheet,
        blur: 30,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: c.surf3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                children: [
                  CircleIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Rename',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  CircleIconButton(
                    icon: Icons.check_rounded,
                    tooltip: 'Save',
                    filled: true,
                    onPressed: _save,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ValueListenableBuilder(
                valueListenable: _text,
                builder: (context, value, _) => Row(
                  children: [
                    SpeakerPill(speakerId: widget.speakerId, name: current),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: c.ink3,
                      ),
                    ),
                    Flexible(
                      child: SpeakerPill(
                        speakerId: widget.speakerId,
                        name: value.text.trim().isEmpty
                            ? '…'
                            : value.text.trim(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: TextStyle(fontSize: 17, color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Name',
                  filled: true,
                  fillColor: c.surf2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Clear',
                    icon: Icon(Icons.cancel_rounded, color: c.ink3),
                    onPressed: _text.clear,
                  ),
                ),
              ),
              if (_heard.isNotEmpty || _expected.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in _heard)
                      ActionChip(
                        backgroundColor: c.surf2,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        label: Text(
                          'hearing $n',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        onPressed: () => _text.text = n,
                      ),
                    for (final n in _expected)
                      ActionChip(
                        backgroundColor: c.surf2,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        label: Text(
                          n,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        onPressed: () => _text.text = n,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
