import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../app/app_state.dart';
import 'library_tab.dart';
import 'record_tab.dart';
import 'settings_tab.dart';
import 'theme.dart';
import 'widgets.dart';

/// Library · Record · Settings with the floating liquid-glass tab bar.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _tabs = [LibraryTab(), RecordTab(), SettingsTab()];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      extendBody: true,
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          // Cross-fade between tabs; every tab keeps its state.
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                IgnorePointer(
                  ignoring: i != app.tab,
                  child: ExcludeSemantics(
                    excluding: i != app.tab,
                    child: AnimatedOpacity(
                      opacity: i == app.tab ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: AnimatedSlide(
                        offset: Offset(0, i == app.tab ? 0 : .015),
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        // Inside the fade so the outgoing tab can still fade
                        // out; pauses the hidden tab's own animations.
                        child: TickerMode(
                          enabled: i == app.tab,
                          child: _tabs[i],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: _TabBar(
            index: app.tab,
            onTap: (i) => app.update(() => app.tab = i),
          ),
        ),
      ),
    );
  }
}

/// Liquid glass on Impeller (iOS, Android); falls back to frosted glass
/// elsewhere. The selected-tab bubble slides with a little overshoot.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.library_books_rounded, 'Library'),
    (Icons.mic_rounded, 'Record'),
    (Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final dark = context.brightness == Brightness.dark;
    return LiquidStretch(
      stretch: .3,
      interactionScale: 1.03,
      child: LiquidGlass.withOwnLayer(
        settings: liquidSettings(dark),
        shape: const LiquidRoundedSuperellipse(borderRadius: 34),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Stack(
              children: [
                AnimatedAlign(
                  alignment: Alignment(-1 + index * 1.0, 0),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  child: FractionallySizedBox(
                    widthFactor: 1 / _items.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: .12)
                            : Colors.white.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: dark ? .18 : .9,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == index,
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onTap(i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedScale(
                                  scale: i == index ? 1.08 : 1,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutBack,
                                  child: Icon(
                                    _items[i].$1,
                                    size: 24,
                                    color: i == index ? c.primary : c.ink2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: i == index ? c.primary : c.ink2,
                                  ),
                                  child: Text(_items[i].$2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
