import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../session/session_controller.dart';
import '../summary/summary_controller.dart';
import 'rename_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Summary tab of a saved session: processing steps while the on-device
/// model works, then the summary, speakers and suggested questions.
class SummaryView extends StatelessWidget {
  const SummaryView({
    super.key,
    required this.saved,
    required this.onSkip,
    required this.onShowSource,
  });

  final SavedSession saved;
  final VoidCallback onSkip;
  final void Function(List<String> segmentIds) onShowSource;

  @override
  Widget build(BuildContext context) {
    final summary = saved.summary;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      child: switch (summary.status) {
        SummaryStatus.done => _Done(
          key: const ValueKey('done'),
          saved: saved,
          onShowSource: onShowSource,
        ),
        SummaryStatus.failed => _Failed(
          key: const ValueKey('failed'),
          summary: summary,
          onSkip: onSkip,
        ),
        _ => _Processing(
          key: const ValueKey('processing'),
          summary: summary,
          onSkip: onSkip,
        ),
      },
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({super.key, required this.summary, required this.onSkip});
  final SummaryController summary;
  final VoidCallback onSkip;

  static const _labels = {
    SummaryStep.reading: 'Reading the transcript',
    SummaryStep.matching: 'Matching speakers to names',
    SummaryStep.summarizing: 'Writing the summary',
    SummaryStep.suggesting: 'Suggesting questions',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      children: [
        Center(child: _ThinkingOrb(color: c.primary)),
        const SizedBox(height: 20),
        Text(
          'Summarizing on this phone',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Offline. Nothing leaves this phone.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: c.ink2),
        ),
        const SizedBox(height: 22),
        Glass(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (final step in SummaryStep.values)
                _StepRow(label: _labels[step]!, status: summary.steps[step]!),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: onSkip,
            child: Text(
              'Skip to transcript',
              style: TextStyle(fontSize: 16, color: c.primary),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.status});
  final String label;
  final StepStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final Widget icon = switch (status) {
      StepStatus.running => SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary),
      ),
      StepStatus.done => Icon(
        Icons.check_circle_rounded,
        size: 22,
        color: c.okDot,
      ),
      StepStatus.skipped => Icon(
        Icons.remove_circle_outline_rounded,
        size: 22,
        color: c.ink3,
      ),
      StepStatus.failed => Icon(
        Icons.error_outline_rounded,
        size: 22,
        color: c.warn,
      ),
      StepStatus.pending => Icon(
        Icons.circle_outlined,
        size: 22,
        color: c.ink3,
      ),
    };
    final muted = status == StepStatus.pending || status == StepStatus.skipped;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: KeyedSubtree(key: ValueKey(status), child: icon),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              style: TextStyle(
                fontSize: 16,
                fontWeight: status == StepStatus.running
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: muted ? c.ink3 : c.ink,
              ),
              child: Text(label),
            ),
          ),
          if (status == StepStatus.skipped)
            Text('No names', style: TextStyle(fontSize: 13, color: c.ink3)),
        ],
      ),
    );
  }
}

/// Soft breathing glow with a sparkle, shown while the model works.
class _ThinkingOrb extends StatefulWidget {
  const _ThinkingOrb({required this.color});
  final Color color;

  @override
  State<_ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<_ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: v,
      builder: (context, child) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              widget.color.withValues(alpha: .35 + .25 * v.value),
              widget.color.withValues(alpha: 0),
            ],
          ),
        ),
        child: Transform.scale(scale: .92 + .12 * v.value, child: child),
      ),
      child: Icon(Icons.auto_awesome_rounded, size: 44, color: widget.color),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({super.key, required this.summary, required this.onSkip});
  final SummaryController summary;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return StatusMessage(
      icon: Icons.auto_awesome_rounded,
      iconColor: c.warn,
      iconBg: c.warnc,
      title: "Couldn't finish the summary",
      body:
          'Your transcript is saved. '
          '${summary.error ?? 'The on-device model stopped.'}',
      actions: [
        PrimaryButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          onPressed: summary.run,
        ),
        GlassButton(label: 'Open transcript', onPressed: onSkip),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({super.key, required this.saved, required this.onShowSource});
  final SavedSession saved;
  final void Function(List<String> segmentIds) onShowSource;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final summary = saved.summary;
    final session = saved.session;
    final idle = summary.questions
        .where((q) => q.status == QuestionStatus.idle)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        FadeInOnce(
          child: Glass(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: c.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Summary',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.primary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'On this phone',
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  summary.summary ?? '',
                  style: TextStyle(fontSize: 17, height: 1.4, color: c.ink),
                ),
                if (summary.truncated) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Long session: the summary covers the most recent part.',
                    style: TextStyle(fontSize: 13, color: c.ink2),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (session.knownSpeakers.isNotEmpty) ...[
          const SectionLabel('Speakers'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in session.knownSpeakers)
                _SpeakerChip(session: session, speakerId: id),
            ],
          ),
        ],
        const SectionLabel('Suggested questions'),
        for (final q in summary.asked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AnswerCard(
              key: ObjectKey(q),
              question: q,
              session: session,
              onRetry: () => summary.ask(q),
              onClose: () => summary.dismiss(q),
              onShowSource: onShowSource,
            ),
          ),
        if (idle.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in idle)
                Pressable(
                  child: ActionChip(
                    avatar: Icon(
                      Icons.help_outline_rounded,
                      size: 18,
                      color: c.primary,
                    ),
                    label: Text(q.text),
                    labelStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                    backgroundColor: c.surf,
                    side: BorderSide(color: c.line),
                    shape: const StadiumBorder(),
                    onPressed: () => summary.ask(q),
                  ),
                ),
            ],
          )
        else if (summary.asked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'All suggested questions answered.',
              style: TextStyle(fontSize: 13, color: c.ink2),
            ),
          ),
      ],
    );
  }
}

class _SpeakerChip extends StatelessWidget {
  const _SpeakerChip({required this.session, required this.speakerId});
  final SessionController session;
  final int speakerId;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final suggested =
        session.speakerNames[speakerId]?.source == NameSource.suggested;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SessionSpeakerPill(
          session: session,
          speakerId: speakerId,
          onRename: (id) => showRenameSheet(context, session, id),
        ),
        if (suggested) ...[
          const SizedBox(width: 4),
          Tag(
            'Suggested',
            icon: Icons.auto_awesome_rounded,
            bg: c.pc,
            fg: c.primary,
            onTap: () => showRenameSheet(context, session, speakerId),
          ),
        ],
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    super.key,
    required this.question,
    required this.session,
    required this.onRetry,
    required this.onClose,
    required this.onShowSource,
  });

  final SuggestedQuestion question;
  final SessionController session;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final void Function(List<String> segmentIds) onShowSource;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final q = question;
    final Widget body = switch (q.status) {
      QuestionStatus.loading => Row(
        key: const ValueKey('loading'),
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
          ),
          const SizedBox(width: 10),
          Text(
            'Thinking on this phone…',
            style: TextStyle(fontSize: 15, color: c.ink2),
          ),
        ],
      ),
      QuestionStatus.failed => Row(
        key: const ValueKey('failed'),
        children: [
          Expanded(
            child: Text(
              "Couldn't answer this one.",
              style: TextStyle(fontSize: 15, color: c.errText),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
      _ when !q.found => Text(
        'Not mentioned in this conversation.',
        key: const ValueKey('none'),
        style: TextStyle(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          color: c.ink2,
        ),
      ),
      _ => _Answer(
        key: const ValueKey('answer'),
        question: q,
        session: session,
        onShowSource: onShowSource,
      ),
    };
    return FadeInOnce(
      child: Glass(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    q.text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 20, color: c.ink3),
                  onPressed: q.status == QuestionStatus.loading
                      ? null
                      : onClose,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({
    super.key,
    required this.question,
    required this.session,
    required this.onShowSource,
  });

  final SuggestedQuestion question;
  final SessionController session;
  final void Function(List<String> segmentIds) onShowSource;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final lines = question.answer!
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty);
    final style = TextStyle(fontSize: 16, height: 1.35, color: c.ink);
    final byId = {for (final s in session.finals) s.id: s};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          if (l.startsWith('- '))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text(l.substring(2), style: style)),
                ],
              ),
            )
          else
            Text(l, style: style),
        if (question.sources.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in question.sources)
                if (byId[id] case final seg?)
                  SourceChip(
                    label: formatMs(seg.tStartMs),
                    onTap: () => onShowSource([id]),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
