import 'package:flutter/material.dart';

import '../engine/caption_engine.dart';
import '../engine/mock_caption_engine.dart';
import '../engine/platform_caption_engine.dart';
import '../session/session_controller.dart';
import 'live_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Default to demo data until the native engines are wired in.
  bool _demo = true;
  MockScenario _scenario = MockScenario.meeting;

  // TODO(jairus): persist sessions in app-private storage (PRD F2).
  final List<SessionController> _past = [];

  Future<void> _startSession() async {
    final CaptionEngine engine = _demo
        ? MockCaptionEngine(scenario: _scenario)
        : PlatformCaptionEngine();
    final session = SessionController(engine);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LiveScreen(session: session, demo: _demo),
      ),
    );
    if (session.finals.isNotEmpty) setState(() => _past.insert(0, session));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ReVise'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Chip(
              avatar: Icon(Icons.airplanemode_active, size: 18),
              label: Text('Offline · On-device'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
            ),
            icon: const Icon(Icons.mic),
            label: const Text('Start session', style: TextStyle(fontSize: 20)),
            onPressed: _startSession,
          ),
          const SizedBox(height: 12),
          Text(
            "Let everyone know you're recording. Processing stays on this phone; sharing is your choice.",
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Demo / Sample data'),
            subtitle: const Text('Scripted conversation, no microphone'),
            value: _demo,
            onChanged: (v) => setState(() => _demo = v),
          ),
          if (_demo)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<MockScenario>(
                value: _scenario,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: MockScenario.meeting,
                    child: Text('4-person meeting'),
                  ),
                  DropdownMenuItem(
                    value: MockScenario.emptySpeech,
                    child: Text('No speech'),
                  ),
                  DropdownMenuItem(
                    value: MockScenario.crmFailure,
                    child: Text('CRM failure for one card'),
                  ),
                ],
                onChanged: (v) => setState(() => _scenario = v ?? _scenario),
              ),
            ),
          const Divider(height: 32),
          Text('Past sessions', style: theme.textTheme.titleMedium),
          if (_past.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No sessions yet.'),
            ),
          for (final s in _past)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(s.knownSpeakers.map(s.displayName).join(', ')),
              subtitle: Text('${s.finals.length} lines'),
            ),
        ],
      ),
    );
  }
}
