import 'dart:convert';

import '../session/session_controller.dart';

enum CrmStatus { pending, generating, done, failed }

class Commitment {
  Commitment(this.what, this.due);
  String what;
  String? due;
}

/// One Auto-CRM card per named speaker (PRD section 8). Stored under the
/// speaker ID; the display name comes from the session's speaker mapping.
class CrmCard {
  CrmCard({required this.speakerId});

  final int speakerId;
  CrmStatus status = CrmStatus.pending;
  String? error;

  /// Input was cut to the most recent lines ("Based on recent lines only").
  bool truncated = false;

  String? role;
  String? organization;
  String? contactMentioned;
  List<String> topics = [];
  List<Commitment> commitments = [];
  String? followUp;
  String? notes;

  /// Field path -> supporting final segment IDs.
  Map<String, List<String>> evidence = {};

  /// Field paths the user edited ("User edited"; evidence claim cleared).
  final Set<String> userEdited = {};

  void markEdited(String path) {
    userEdited.add(path);
    evidence.remove(path);
  }

  String toPlainText(String name) {
    final b = StringBuffer('$name\n');
    void line(String label, String? v) {
      if (v != null && v.isNotEmpty) b.writeln('$label: $v');
    }

    line('Role', role);
    line('Organization', organization);
    line('Contact', contactMentioned);
    if (topics.isNotEmpty) b.writeln('Topics: ${topics.join(', ')}');
    for (final c in commitments) {
      b.writeln(
        'Commitment: ${c.what}${c.due == null ? '' : ' (due ${c.due})'}',
      );
    }
    line('Follow-up', followUp);
    line('Notes', notes);
    return b.toString().trimRight();
  }

  /// Parses raw model output and keeps only values backed by evidence from
  /// this speaker's final lines. Throws [FormatException] when the output is
  /// not usable at all, which triggers a retry.
  void applyModelOutput(String raw, Map<String, Segment> speakerLines) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('No JSON object');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map) throw const FormatException('Not an object');
    final src = decoded['source_segments'];
    if (src is! Map) throw const FormatException('Missing source_segments');

    final ev = <String, List<String>>{};
    src.forEach((k, v) {
      if (k is! String || v is! List) return;
      final ids = v.whereType<String>().toList();
      if (ids.isNotEmpty && ids.every(speakerLines.containsKey)) ev[k] = ids;
    });

    String? scalar(String key) {
      final v = decoded[key];
      if (v is! String || v.trim().isEmpty || !ev.containsKey(key)) return null;
      return v.trim();
    }

    final keptEvidence = <String, List<String>>{};
    void keep(String from, String to) {
      final ids = ev[from];
      if (ids != null) keptEvidence[to] = ids;
    }

    role = scalar('role');
    organization = scalar('organization');
    contactMentioned = scalar('contact_mentioned');
    followUp = scalar('follow_up');
    notes = scalar('notes');
    for (final k in [
      'role',
      'organization',
      'contact_mentioned',
      'follow_up',
      'notes',
    ]) {
      if (decoded[k] is String && ev.containsKey(k)) keep(k, k);
    }

    topics = [];
    final rawTopics = decoded['topics'];
    if (rawTopics is List) {
      for (var i = 0; i < rawTopics.length; i++) {
        final t = rawTopics[i];
        if (t is String &&
            t.trim().isNotEmpty &&
            ev.containsKey('topics[$i]')) {
          keep('topics[$i]', 'topics[${topics.length}]');
          topics.add(t.trim());
        }
      }
    }

    commitments = [];
    final rawCommitments = decoded['commitments'];
    if (rawCommitments is List) {
      for (var i = 0; i < rawCommitments.length; i++) {
        final c = rawCommitments[i];
        if (c is! Map) continue;
        final what = c['what'];
        if (what is! String || !ev.containsKey('commitments[$i].what')) {
          continue;
        }
        final n = commitments.length;
        keep('commitments[$i].what', 'commitments[$n].what');
        final due = c['due'];
        final dueOk = due is String && ev.containsKey('commitments[$i].due');
        if (dueOk) keep('commitments[$i].due', 'commitments[$n].due');
        commitments.add(Commitment(what.trim(), dueOk ? due.trim() : null));
      }
    }

    keep('name', 'name');
    evidence = keptEvidence;
  }
}
