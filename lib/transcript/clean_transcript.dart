/// Pure logic for the "clean transcript": merging fragment lines into turns and the guard that
/// decides whether an LLM-punctuated turn may replace the original words. No Flutter, no engine.
library;

/// One finished line as the merger sees it (decoupled from the session's `Segment` so the logic
/// is easy to test).
class MergeLine {
  const MergeLine({
    required this.id,
    required this.speakerId,
    required this.text,
    required this.tStartMs,
    required this.tEndMs,
  });

  final String id;
  final int speakerId;
  final String text;
  final int tStartMs;
  final int tEndMs;
}

enum TurnStatus {
  /// Merged but not punctuated yet (or the model was not available).
  raw,

  /// The model's punctuated version passed the word guard and is shown.
  polished,

  /// The model changed words (or failed); the merged original words are kept.
  kept,
}

/// Several consecutive lines of one speaker merged into one readable turn.
class Turn {
  Turn({
    required this.speakerId,
    required this.segmentIds,
    required this.rawText,
    required this.tStartMs,
    required this.tEndMs,
  }) : text = rawText;

  /// Id of the first line. Stable while the merge does not change; used as the citation id.
  String get id => segmentIds.first;

  final int speakerId;

  /// Every original segment ID that went into this turn, in order.
  final List<String> segmentIds;

  /// The merged original words (lines joined with a space), never rewritten.
  final String rawText;

  /// What to show in the Clean view: [rawText] until polished, then the punctuated text.
  String text;
  TurnStatus status = TurnStatus.raw;
  final int tStartMs;
  final int tEndMs;
}

/// Two lines are one thought when the gap is short and the first one is unfinished (no . ? !),
/// or the next one clearly continues it (lowercase start, or and/so/but/because/or).
const maxMergeGapMs = 1500;

final _continuers = RegExp(r'^(and|so|but|because|or)\b', caseSensitive: false);
final _sentenceEnd = RegExp(r'''[.?!]["')\]]*$''');

bool endsSentence(String text) {
  final t = text.trimRight();
  if (t.endsWith('...') || t.endsWith('…')) return false; // trailing off is not finished
  return _sentenceEnd.hasMatch(t);
}

bool _startsLowercase(String text) {
  final t = text.trimLeft();
  if (t.isEmpty) return false;
  final c = t[0];
  return c.toLowerCase() == c && c.toUpperCase() != c; // a letter, and not uppercase
}

bool shouldMerge(MergeLine prev, MergeLine next) {
  if (prev.speakerId != next.speakerId) return false;
  final gap = next.tStartMs - prev.tEndMs;
  if (gap >= maxMergeGapMs) return false;
  return !endsSentence(prev.text) ||
      _startsLowercase(next.text) ||
      _continuers.hasMatch(next.text.trimLeft());
}

/// Joins consecutive same-speaker fragments into turns. [lines] must be in time order.
List<Turn> mergeFragments(List<MergeLine> lines) {
  final turns = <Turn>[];
  MergeLine? previous;
  for (final line in lines) {
    final text = line.text.trim();
    if (text.isEmpty) continue;
    final current = MergeLine(
      id: line.id,
      speakerId: line.speakerId,
      text: text,
      tStartMs: line.tStartMs,
      tEndMs: line.tEndMs,
    );
    if (previous != null && turns.isNotEmpty && shouldMerge(previous, current)) {
      final last = turns.removeLast();
      turns.add(
        Turn(
          speakerId: last.speakerId,
          segmentIds: [...last.segmentIds, current.id],
          rawText: '${last.rawText} ${current.text}',
          tStartMs: last.tStartMs,
          tEndMs: current.tEndMs,
        ),
      );
    } else {
      turns.add(
        Turn(
          speakerId: current.speakerId,
          segmentIds: [current.id],
          rawText: current.text,
          tStartMs: current.tStartMs,
          tEndMs: current.tEndMs,
        ),
      );
    }
    previous = current;
  }
  return turns;
}

// --- punctuation pass --------------------------------------------------------------------

/// Only these may disappear in the punctuation pass.
final _fillers = RegExp(r'^(um+|uh+|uhm+)$');

/// The words of [text] with punctuation, case and fillers stripped. Two texts that differ only in
/// punctuation, capitals and fillers give the same list.
List<String> guardWords(String text) {
  final cleaned = text
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ') // punctuation and hyphens become spaces
      .replaceAll(RegExp(r"(^|\s)'+|'+(?=\s|$)"), ' '); // quotes around words, not apostrophes inside
  return [
    for (final w in cleaned.split(RegExp(r'\s+')))
      if (w.isNotEmpty && !_fillers.hasMatch(w)) w,
  ];
}

/// True when [candidate] has exactly the same words as [original] (ignoring punctuation, case,
/// and um/uh). Anything else (a changed, added or dropped word) means reject.
bool passesWordGuard(String original, String candidate) {
  final a = guardWords(original);
  final b = guardWords(candidate);
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Instruction first, text last, so the llama.cpp prompt cache keeps the shared start.
String buildPolishPrompt(String text) =>
    '''
Rewrite the spoken text below as correctly punctuated written English.
Rules:
- Fix punctuation, capital letters and sentence breaks.
- Remove only the filler words "um" and "uh".
- Do not add, remove, replace or reorder any other word. Do not fix grammar or wording.
- Reply with the rewritten text only, nothing else.

Text: $text''';

/// Model replies sometimes wrap the text in quotes or add a label. Returns just the text.
String sanitizeModelText(String raw) {
  var t = raw.trim();
  t = t.replaceFirst(RegExp(r'^(text|rewritten text|output)\s*:\s*', caseSensitive: false), '');
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith('“') && t.endsWith('”')))) {
    t = t.substring(1, t.length - 1);
  }
  return stripDashes(t.replaceAll(RegExp(r'\s*\n+\s*'), ' ').trim());
}

/// User-facing text never contains em or en dashes.
String stripDashes(String t) => t
    .replaceAll(RegExp(r'\s*—\s*'), ', ')
    .replaceAll(RegExp(r'\s*–\s*'), '-');

/// Splits a long turn at word boundaries so each model call stays small. Short text is returned
/// as one chunk.
List<String> chunkForPolish(String text, {int maxChars = 600}) {
  if (text.length <= maxChars) return [text];
  final chunks = <String>[];
  var current = StringBuffer();
  for (final word in text.split(RegExp(r'\s+'))) {
    if (current.length + word.length + 1 > maxChars && current.isNotEmpty) {
      chunks.add(current.toString());
      current = StringBuffer();
    }
    if (current.isNotEmpty) current.write(' ');
    current.write(word);
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
}

/// No model needed for very short turns: capitalise and close the sentence.
String simplePolish(String text) {
  var t = text.trim();
  if (t.isEmpty) return t;
  t = t[0].toUpperCase() + t.substring(1);
  return endsSentence(t) ? t : (t.endsWith('...') ? t : '$t.');
}
