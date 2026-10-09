import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../engine/mock_caption_engine.dart';
import 'theme.dart';
import 'widgets.dart';

/// Settings tab (mockup 3c).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.rc;
    final label = TextStyle(fontSize: 16, color: c.ink);
    final value = TextStyle(fontSize: 15, color: c.ink2);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        const LargeTitle('Settings'),
        const SectionLabel('Captions'),
        Glass(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Text size', style: label)),
                    Text('${app.textSize.round()} pt', style: value),
                  ],
                ),
              ),
              TextSizeSlider(
                value: app.textSize,
                onChanged: (v) => app.update(() => app.textSize = v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Thanks for coming in.',
                    style: TextStyle(
                      fontSize: app.textSize,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, indent: 14, color: c.line),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text('Landscape', style: label)),
                    Segmented(
                      options: const ['Dark', 'Light'],
                      index: app.landscapeDark ? 0 : 1,
                      onChanged: (i) =>
                          app.update(() => app.landscapeDark = i == 0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Recording'),
        Glass(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('Ask for names before recording', style: label),
                ),
                Switch(
                  value: app.askNames,
                  onChanged: (v) => app.update(() => app.askNames = v),
                ),
              ],
            ),
          ),
        ),
        const SectionLabel('Data'),
        Glass(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                child: Row(
                  children: [
                    Expanded(child: Text('Sample data', style: label)),
                    Switch(
                      value: app.sampleData,
                      onChanged: (v) => app.update(() => app.sampleData = v),
                    ),
                  ],
                ),
              ),
              if (app.sampleData) ...[
                Divider(height: 1, indent: 14, color: c.line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
                  child: Row(
                    children: [
                      Expanded(child: Text('Sample scenario', style: label)),
                      DropdownButton<MockScenario>(
                        value: app.scenario,
                        underline: const SizedBox.shrink(),
                        style: value,
                        dropdownColor: c.sheet,
                        items: const [
                          DropdownMenuItem(
                            value: MockScenario.meeting,
                            child: Text('Meeting'),
                          ),
                          DropdownMenuItem(
                            value: MockScenario.summaryFailure,
                            child: Text('Summary fails'),
                          ),
                          DropdownMenuItem(
                            value: MockScenario.micInterrupted,
                            child: Text('Mic interrupted'),
                          ),
                          DropdownMenuItem(
                            value: MockScenario.emptySpeech,
                            child: Text('No speech'),
                          ),
                          DropdownMenuItem(
                            value: MockScenario.micDenied,
                            child: Text('Mic denied'),
                          ),
                          DropdownMenuItem(
                            value: MockScenario.modelMissing,
                            child: Text('Model missing'),
                          ),
                        ],
                        onChanged: (v) =>
                            app.update(() => app.scenario = v ?? app.scenario),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SectionLabel('Model'),
        Glass(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: Text('Speech model', style: label)),
                Text(
                  app.sampleData
                      ? 'Sample data'
                      : switch (app.sttReady) {
                          true => 'Installed',
                          false => 'Missing',
                          null => 'Checked on start',
                        },
                  style: value,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
          child: Text(
            'Everything runs on this phone. Nothing is uploaded.',
            style: TextStyle(fontSize: 13, color: c.ink2),
          ),
        ),
      ],
    );
  }
}

/// Small A — slider — large A.
class TextSizeSlider extends StatelessWidget {
  const TextSizeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 18,
    this.max = 44,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Text('A', style: TextStyle(fontSize: 13, color: c.ink)),
          const SizedBox(width: 12),
          Expanded(
            child: Slider(
              min: min,
              max: max,
              value: value.clamp(min, max),
              semanticFormatterCallback: (v) => '${v.round()} point text',
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'A',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS-style segmented control.
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
    this.expand = false,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final dark = context.brightness == Brightness.dark;
    final n = options.length;
    Widget seg(int i) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 14,
                fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                color: c.ink,
              ),
              child: Text(options[i], maxLines: 1, softWrap: false),
            ),
          ),
        ),
      ),
    );
    // Equal-width segments so the thumb can slide between them.
    final row = Stack(
      children: [
        Positioned.fill(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutBack,
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark ? c.surf3 : Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: dark
                      ? null
                      : const [
                          BoxShadow(color: Color(0x1F000000), blurRadius: 4),
                        ],
                ),
              ),
            ),
          ),
        ),
        Row(children: [for (var i = 0; i < n; i++) seg(i)]),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: dark ? c.surf2 : c.surf3.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(11),
      ),
      child: expand ? row : IntrinsicWidth(child: row),
    );
  }
}
