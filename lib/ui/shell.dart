import 'package:flutter/material.dart';

import '../app/app_state.dart';
import 'library_tab.dart';
import 'record_tab.dart';
import 'settings_tab.dart';
import 'theme.dart';
import 'widgets.dart';

/// Library · Record · Settings with the floating glass tab bar.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      extendBody: true,
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: app.tab,
            children: const [LibraryTab(), RecordTab(), SettingsTab()],
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
    return Glass(
      radius: 34,
      color: c.sheet,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 56,
                    decoration: BoxDecoration(
                      color: i == index ? c.surf : Colors.transparent,
                      borderRadius: BorderRadius.circular(30),
                      border: i == index ? Border.all(color: c.line) : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _items[i].$1,
                          size: 24,
                          color: i == index ? c.primary : c.ink2,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _items[i].$2,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: i == index ? c.primary : c.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
