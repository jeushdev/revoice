import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Optional "Who's in this conversation?" sheet shown before recording.
/// Returns the names (empty for Skip), or null if dismissed (no recording).
Future<List<String>?> showNamesSheet(
  BuildContext context, {
  List<String> recent = const [],
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: const AnimationStyle(
    duration: Duration(milliseconds: 420),
    reverseDuration: Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  ),
  builder: (_) => _NamesSheet(recent: recent),
);

class _NamesSheet extends StatefulWidget {
  const _NamesSheet({required this.recent});
  final List<String> recent;

  @override
  State<_NamesSheet> createState() => _NamesSheetState();
}

class _NamesSheetState extends State<_NamesSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<String> _names = [];

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _has(String n) => _names.any((x) => x.toLowerCase() == n.toLowerCase());

  void _add(String raw) {
    // Accept "Zairus, Jeush" in one go.
    final parts = raw
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_has(p));
    setState(() => _names.addAll(parts));
    _text.clear();
  }

  void _start() {
    if (_text.text.trim().isNotEmpty) _add(_text.text);
    Navigator.pop(context, List<String>.unmodifiable(_names));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final recent = widget.recent.where((n) => !_has(n)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Glass(
        radius: 32,
        color: c.sheet,
        blur: 30,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: c.surf3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.pc,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.group_rounded,
                      size: 22,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Who's in this conversation?",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Optional. Names help ReVoice tell speakers apart afterwards. '
                'They stay on this phone.',
                style: TextStyle(fontSize: 15, height: 1.3, color: c.ink2),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                focusNode: _focus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onSubmitted: (v) {
                  _add(v);
                  _focus.requestFocus();
                },
                style: TextStyle(fontSize: 17, color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Add a name',
                  filled: true,
                  fillColor: c.surf2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: ValueListenableBuilder(
                    valueListenable: _text,
                    builder: (context, v, _) => IconButton(
                      tooltip: 'Add',
                      icon: Icon(
                        Icons.add_circle_rounded,
                        color: v.text.trim().isEmpty ? c.ink3 : c.primary,
                      ),
                      onPressed: v.text.trim().isEmpty
                          ? null
                          : () => _add(_text.text),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _names.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, n) in _names.indexed)
                              FadeInOnce(
                                key: ValueKey(n),
                                child: InputChip(
                                  label: Text(n),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: context.hue(i + 1).fg,
                                  ),
                                  backgroundColor: context.hue(i + 1).bg,
                                  side: BorderSide.none,
                                  shape: const StadiumBorder(),
                                  deleteIconColor: context.hue(i + 1).fg,
                                  onDeleted: () =>
                                      setState(() => _names.remove(n)),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Recent',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.ink2,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in recent)
                      ActionChip(
                        avatar: Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: c.ink2,
                        ),
                        label: Text(n),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                        backgroundColor: c.surf2,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        onPressed: () => _add(n),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Start recording',
                icon: Icons.mic_rounded,
                onPressed: _start,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context, const <String>[]),
                child: Text(
                  'Skip',
                  style: TextStyle(fontSize: 16, color: c.ink2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
