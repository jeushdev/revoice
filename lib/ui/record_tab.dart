import 'dart:async';

import 'package:flutter/material.dart';

import 'live_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Record tab (mockup 3a): quick tips carousel and the big mic orb.
class RecordTab extends StatelessWidget {
  const RecordTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LargeTitle('Welcome'),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, size: 16, color: c.ink2),
              const SizedBox(width: 6),
              Text(
                'Quick tips',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _TipsCarousel(),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MicOrb(onTap: () => openLiveSession(context)),
                    const SizedBox(height: 22),
                    Text(
                      'Start session',
                      style: TextStyle(fontSize: 17, color: c.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipsCarousel extends StatefulWidget {
  const _TipsCarousel();

  @override
  State<_TipsCarousel> createState() => _TipsCarouselState();
}

class _TipsCarouselState extends State<_TipsCarousel> {
  static const _tips = [
    (
      Icons.smartphone_rounded,
      'Place it between speakers',
      'Lay the phone flat, screen up.',
    ),
    (
      Icons.edit_rounded,
      'Tap a name to rename',
      'Named speakers get a profile.',
    ),
    (Icons.wifi_off_rounded, 'Works offline', 'Everything runs on this phone.'),
    (
      Icons.screen_rotation_rounded,
      'Turn sideways for big captions',
      'Or tap full screen while recording.',
    ),
  ];

  final _page = PageController(viewportFraction: 0.94);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_page.hasClients) return;
      final next = (_index + 1) % _tips.length;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return Column(
      children: [
        SizedBox(
          height: 80,
          child: PageView.builder(
            controller: _page,
            padEnds: false,
            itemCount: _tips.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final (icon, title, body) = _tips[i];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Glass(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.pc,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 20, color: c.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            Text(
                              body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: c.ink2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _tips.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _index ? c.primary : c.surf3,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Blue glass orb mic button.
class _MicOrb extends StatelessWidget {
  const _MicOrb({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = context.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'Start session',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 196,
          height: 196,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: dark ? 0.10 : 0.55),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.18 : 0.9),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A5FD6).withValues(alpha: 0.35),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.45),
                radius: 0.95,
                colors: dark
                    ? const [
                        Color(0xFF3F7FE0),
                        Color(0xFF123F9A),
                        Color(0xFF071F55),
                      ]
                    : const [
                        Color(0xFF4F95FF),
                        Color(0xFF0D55C9),
                        Color(0xFF063383),
                      ],
              ),
            ),
            child: const Icon(Icons.mic_rounded, size: 84, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
