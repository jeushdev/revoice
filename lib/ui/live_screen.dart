import 'package:flutter/material.dart';

import '../crm/crm_controller.dart';
import '../engine/engine_events.dart';
import '../session/session_controller.dart';
import 'speaker_chip.dart';
import 'transcript_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.session, required this.demo});

  final SessionController session;
  final bool demo;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  double _textSize = 24;
  final _scroll = ScrollController();
  bool _stopping = false;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.addListener(_autoScroll);
    _begin();
  }

  Future<void> _begin() async {
    await session.init();
    if (session.errorMessage == null) await session.start();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    await session.stop();
    if (!mounted) return;
    final crm = CrmController(session.engine, session);
    // CRM starts automatically after the transcript is flushed and saved.
    crm.generateMissing();
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TranscriptScreen(session: session, crm: crm),
      ),
    );
  }

  @override
  void dispose() {
    session.removeListener(_autoScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final state = session.state;
        final error = session.errorMessage;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Live captions'),
            actions: [
              if (widget.demo)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Chip(label: Text('Demo / Sample data')),
                ),
              _StatusPill(state: state),
              const SizedBox(width: 12),
            ],
          ),
          body: Column(
            children: [
              if (error != null)
                _ErrorBanner(session: session, onRetry: _begin),
              Expanded(child: _captions(context)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.text_fields, size: 18),
                    Expanded(
                      child: Slider(
                        min: 16,
                        max: 44,
                        value: _textSize,
                        label: 'Text size',
                        onChanged: (v) => setState(() => _textSize = v),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                          icon: Icon(
                            state == EngineState.paused
                                ? Icons.play_arrow
                                : Icons.pause,
                          ),
                          label: Text(
                            state == EngineState.paused ? 'Resume' : 'Pause',
                          ),
                          onPressed: switch (state) {
                            EngineState.listening => session.pause,
                            EngineState.paused => session.resume,
                            _ => null,
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                          onPressed:
                              !_stopping &&
                                  (state == EngineState.listening ||
                                      state == EngineState.paused ||
                                      state == EngineState.error)
                              ? _stop
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _captions(BuildContext context) {
    final lines = [...session.finals, ...session.partials];
    if (lines.isEmpty) {
      return Center(
        child: Text(
          session.state == EngineState.listening ? 'Listening…' : '',
          style: TextStyle(fontSize: _textSize, color: Colors.grey),
        ),
      );
    }
    final base = Theme.of(context).colorScheme.onSurface;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final seg = lines[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpeakerChip(session: session, speakerId: seg.speakerId),
              Text(
                seg.text,
                style: TextStyle(
                  fontSize: _textSize,
                  height: 1.3,
                  color: seg.isFinal ? base : base.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});
  final EngineState? state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      EngineState.listening => ('Listening', Colors.green),
      EngineState.paused => ('Paused', Colors.orange),
      EngineState.stopped => ('Stopped', Colors.grey),
      EngineState.error => ('Error', Colors.red),
      _ => ('Starting', Colors.grey),
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 12, color: color),
      label: Text(label),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.session, required this.onRetry});
  final SessionController session;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final code = session.lastErrorCode;
    final title = switch (code) {
      EngineErrorCode.permissionDenied => 'Microphone access is off',
      EngineErrorCode.modelMissing => 'Speech model missing',
      _ when session.interrupted => 'Microphone interrupted',
      _ => 'Something went wrong',
    };
    final hint = code == EngineErrorCode.permissionDenied
        ? 'Allow microphone access in Settings, then retry.'
        : code == EngineErrorCode.modelMissing
        ? 'The native engine is not ready yet. Turn on Demo / Sample data on Home.'
        : 'Finalized lines are kept.';
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      content: Text('$title\n${session.errorMessage ?? ''}\n$hint'),
      actions: [TextButton(onPressed: onRetry, child: const Text('Retry'))],
    );
  }
}
