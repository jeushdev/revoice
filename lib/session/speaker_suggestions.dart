/// Post-Stop speaker suggestions from turn-taking cues and names (PRD F3 safety net).
///
/// Used only when the audio gave NO speakers at all (every line Unknown). If Moonshine
/// labelled even one line, its labels are kept: a phone test showed that overriding a mix of
/// Unknown + real labels made things worse. It is a heuristic for 2-person conversations, not
/// a model: it is shown as "suggested", the original labels are kept, and the user can
/// switch it off or fix single lines. (A 1.5B on-device LLM was tried for this and scored
/// at chance level, so it is not used.)
library;

import 'name_rules.dart';

class SuggestionLine {
  const SuggestionLine(this.id, this.text, this.speakerId);
  final String id;
  final String text;

  /// The speaker the app currently shows for this line (0 = unknown).
  final int speakerId;
}

class SpeakerSuggestion {
  const SpeakerSuggestion(this.speakers, this.names);

  /// Suggested speaker (1 or 2) for every line id.
  final Map<String, int> speakers;

  /// Names said in the conversation, per suggested speaker.
  final Map<int, String> names;
}

/// Words that start an answer, a reaction, or a closing: usually said by the OTHER person.
final _replyCue = RegExp(
  r"^\s*(?:yes|yeah|yep|yup|no|nope|sure|okay|ok|right|exactly|absolutely|of course|thanks|thank you|"
  r"sounds good|got it|i see|no problem|sorry|oh|wow|really|hi|hello|hey|good morning|good afternoon|"
  r"nice to meet you|pleasure|likewise|me too|same here|great|good|perfect|awesome|cool|"
  r"that(?:'s|’s| is| was| sounds| seems)|i understand)\b",
  caseSensitive: false,
);

/// "Hi David," / "Thanks, John." / "Sure David": the name belongs to the person being spoken TO.
final _greeted = RegExp(
  r"\b(?:hi|hello|hey|thanks|thank you|bye|goodbye|sure|okay|ok|right|yes|no problem|welcome|sorry),?\s+([a-z][a-z'’\-]*)",
  caseSensitive: false,
);

String? _greetedName(String text) {
  // Reuse the self-intro name filter by asking name_rules to validate the token.
  for (final m in _greeted.allMatches(text)) {
    final token = m.group(1)!;
    final asName = selfIntroName("I'm $token");
    if (asName != null) return asName;
  }
  return null;
}

/// True if [text] mentions [name] (or a nickname such as "johnny" for "John") without being the
/// person introducing themselves. Mentioning someone means talking to or about them.
bool _addressesSpeaker(String text, String? name, String? selfIntro) {
  if (name == null || name.length < 3) return false;
  if (selfIntro != null && selfIntro.toLowerCase() == name.toLowerCase()) return false;
  final lower = name.toLowerCase();
  for (final m in RegExp(r"[a-z][a-z'’\-]*", caseSensitive: false).allMatches(text)) {
    final word = m.group(0)!.toLowerCase();
    if (word == lower || (word.startsWith(lower) && word.length <= lower.length + 3)) return true;
  }
  return false;
}

/// Returns suggestions, or null when there is nothing to suggest (the voices were already
/// separated, too few lines, or not a conversation this heuristic can describe).
SpeakerSuggestion? suggestSpeakers(List<SuggestionLine> lines) {
  if (lines.length < 4) return null;
  // Any real label from Moonshine (or the user) means we leave the audio's answer alone.
  if (lines.any((l) => l.speakerId != 0)) return null;

  final speakers = <String, int>{};
  final intro = <int, String>{}; // speaker -> name they said about themselves
  final addressed = <int, String>{}; // speaker -> name they were greeted/thanked as
  var current = 1;

  for (var i = 0; i < lines.length; i++) {
    final text = lines[i].text.trim();
    if (i > 0) {
      final previous = lines[i - 1].text.trim();
      var change = false;
      if (previous.endsWith('?')) change = true; // a question is answered by someone else
      if (_replyCue.hasMatch(text)) change = true; // "Sure", "Thanks", "Hi David"...

      // Name constraints beat the generic cues.
      final self = selfIntroName(text);
      if (self != null) {
        final known = intro[current];
        if (known != null && known.toLowerCase() != self.toLowerCase()) change = true;
        if (known != null && known.toLowerCase() == self.toLowerCase()) change = false;
      }
      if (change) current = current == 1 ? 2 : 1;
      // A line that talks TO a person ("Yo what's up johnny", "Thanks, John") is not said by that
      // person. This beats every other cue.
      if (_addressesSpeaker(text, intro[current], self)) current = current == 1 ? 2 : 1;
    }
    speakers[lines[i].id] = current;

    final self = selfIntroName(text);
    if (self != null) intro.putIfAbsent(current, () => self);
    final to = _greetedName(text);
    if (to != null) addressed.putIfAbsent(current == 1 ? 2 : 1, () => to);
  }

  // Only worth suggesting if it actually found two voices.
  if (speakers.values.toSet().length < 2) return null;

  // Names: what each person said about themselves wins; else the name they were addressed by.
  final names = <int, String>{...addressed, ...intro};
  return SpeakerSuggestion(speakers, names);
}
