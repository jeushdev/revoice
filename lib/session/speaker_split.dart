/// Automatic repair of a MERGED speaker after Stop: Moonshine sometimes puts two voices under
/// one speaker id. Text clues decide who said each line; nothing here asks the user to do
/// anything, and the original labels are never overwritten (see `Segment.autoSpeakerId`).
///
/// A merged speaker is detected when (a) one speaker id introduces itself with two different
/// names ("I'm Mark" ... "I'm Anna"), or (b) names were entered before recording and fewer
/// speakers were detected than names. The lines of that speaker are then labelled with the
/// candidate names by a small dynamic program (Viterbi) over these clues:
///   - "I'm Anna" is said by Anna (hard clue);
///   - a line that uses a name ("Thanks, Anna", "So Anna, ...") is said by someone else (strong clue);
///   - the line after a question, and a short reply ("Yes", "That works", "Sure"), come from the
///     other person;
///   - a pause of 0.9 s or more between lines slightly favours a turn change, and lines that
///     follow within 0.6 s are usually the same person.
/// Without at least one name clue nothing is changed ("don't guess").
library;

import 'name_rules.dart';

class SplitLine {
  const SplitLine(this.id, this.text, this.speakerId, this.tStartMs, this.tEndMs);
  final String id;
  final String text;

  /// The speaker id the line currently has (Moonshine's, or the user's own choice).
  final int speakerId;
  final int tStartMs;
  final int tEndMs;
}

class SplitResult {
  const SplitResult(this.lineSpeaker, this.names);

  /// New speaker id for every line of the split speaker.
  final Map<String, int> lineSpeaker;

  /// Name for each speaker id involved (the original id keeps one of the names).
  final Map<int, String> names;
}

final _replyStart = RegExp(
  r"^\s*(?:yes|yeah|yep|yup|no|nope|sure|okay|ok|right|exactly|absolutely|of course|thanks|thank you|"
  r"sounds good|got it|i see|no problem|sorry|oh|wow|really|great|good|perfect|awesome|cool|alright|"
  r"that(?:'s|’s| is| was| works| sounds| seems)|i understand)\b",
  caseSensitive: false,
);

String _title(String name) {
  final t = name.trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1).toLowerCase();
}

bool _mentions(String text, String name) =>
    RegExp('\\b${RegExp.escape(name)}\\b', caseSensitive: false).hasMatch(text);

int _words(String text) => text.trim().split(RegExp(r'\s+')).length;

/// Returns a split for the first merged speaker found, or null when nothing needs fixing.
SplitResult? splitMergedSpeaker(List<SplitLine> lines, List<String> expectedNames) {
  final expected = [for (final n in expectedNames) _title(n)].where((n) => n.isNotEmpty).toList();
  final bySpeaker = <int, List<SplitLine>>{};
  for (final l in lines) {
    if (l.speakerId != 0) bySpeaker.putIfAbsent(l.speakerId, () => []).add(l);
  }
  if (bySpeaker.isEmpty) return null;

  // Names each detected speaker introduces itself with.
  final intros = <int, Set<String>>{
    for (final e in bySpeaker.entries)
      e.key: {
        for (final l in e.value)
          if (selfIntroName(l.text) case final n?) n,
      },
  };

  // (a) a speaker with two different self-introductions.
  for (final e in intros.entries) {
    if (e.value.length >= 2) {
      final result = _label(bySpeaker[e.key]!, e.value.take(4).toList(), e.key, bySpeaker.keys);
      if (result != null) return result;
    }
  }

  // (b) fewer speakers than names entered: split the speaker with the most lines, using the
  // names that no OTHER speaker introduced itself with.
  if (expected.length >= 2 && bySpeaker.length < expected.length) {
    final biggest = bySpeaker.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);
    final claimedElsewhere = {
      for (final e in intros.entries)
        if (e.key != biggest.key) ...e.value,
    };
    final names = [for (final n in expected) if (!claimedElsewhere.contains(n)) n].take(4).toList();
    if (names.length >= 2) return _label(biggest.value, names, biggest.key, bySpeaker.keys);
  }
  return null;
}

SplitResult? _label(List<SplitLine> lines, List<String> names, int speakerId, Iterable<int> usedIds) {
  final n = names.length;
  if (n < 2 || lines.length < 2) return null;

  // Unary cost of line i being said by names[k].
  var anchors = 0;
  final unary = List.generate(lines.length, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < lines.length; i++) {
    final intro = selfIntroName(lines[i].text);
    final introIdx = intro == null ? -1 : names.indexOf(intro);
    if (introIdx >= 0) {
      anchors++;
      for (var k = 0; k < n; k++) {
        if (k != introIdx) unary[i][k] += 100; // "I'm Anna" is Anna
      }
    }
    for (var k = 0; k < n; k++) {
      if (k == introIdx) continue;
      if (_mentions(lines[i].text, names[k])) {
        anchors++;
        unary[i][k] += 8; // addressing a name: said by someone else
      }
    }
  }
  if (anchors == 0) return null; // no evidence for who is who: leave the labels alone

  // Cost of line i-1 -> line i being the same person (or a different one).
  double same(int i) {
    final prev = lines[i - 1];
    final cur = lines[i];
    final gap = cur.tStartMs - prev.tEndMs;
    var cost = 0.0;
    if (gap >= 900) cost += 1.5; // lines end after about 1 s of silence, so a pause is the norm
    if (prev.text.trimRight().endsWith('?')) cost += 4;
    if (_replyStart.hasMatch(cur.text) && _words(cur.text) <= 7) cost += 4;
    return cost;
  }

  double different(int i) {
    final gap = lines[i].tStartMs - lines[i - 1].tEndMs;
    var cost = 1.0; // people usually keep talking
    if (gap >= 900) cost -= 1.0;
    if (gap < 600) cost += 2.0;
    return cost;
  }

  // Viterbi over the lines.
  final best = List.generate(lines.length, (_) => List<double>.filled(n, 0));
  final from = List.generate(lines.length, (_) => List<int>.filled(n, 0));
  for (var k = 0; k < n; k++) {
    best[0][k] = unary[0][k];
  }
  for (var i = 1; i < lines.length; i++) {
    final s = same(i);
    final d = different(i);
    for (var k = 0; k < n; k++) {
      var bestCost = double.infinity;
      var bestPrev = 0;
      for (var j = 0; j < n; j++) {
        final c = best[i - 1][j] + (j == k ? s : d);
        if (c < bestCost) {
          bestCost = c;
          bestPrev = j;
        }
      }
      best[i][k] = bestCost + unary[i][k];
      from[i][k] = bestPrev;
    }
  }
  var k = 0;
  for (var j = 1; j < n; j++) {
    if (best[lines.length - 1][j] < best[lines.length - 1][k]) k = j;
  }
  final labels = List<int>.filled(lines.length, 0);
  for (var i = lines.length - 1; i >= 0; i--) {
    labels[i] = k;
    k = from[i][k];
  }

  // Every name must get at least one line, or the split is not credible.
  final counts = List<int>.filled(n, 0);
  for (final l in labels) {
    counts[l]++;
  }
  if (counts.any((c) => c == 0)) return null;

  // The name with the most lines keeps the original speaker id; the others get new ids.
  final order = List.generate(n, (i) => i)..sort((a, b) => counts[b].compareTo(counts[a]));
  var nextId = usedIds.fold<int>(0, (m, id) => id > m ? id : m) + 1;
  final idOfName = <int, int>{};
  for (final nameIdx in order) {
    idOfName[nameIdx] = nameIdx == order.first ? speakerId : nextId++;
  }
  return SplitResult(
    {for (var i = 0; i < lines.length; i++) lines[i].id: idOfName[labels[i]]!},
    {for (final e in idOfName.entries) e.value: names[e.key]},
  );
}
