import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../session/session_controller.dart';
import 'theme.dart';

String formatMs(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final first = parts.first.isEmpty ? '?' : parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

/// Page background: tinted base with slowly drifting color blobs, so the
/// glass surfaces on top have something to blur and refract.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.child, this.plain = false});
  final Widget child;

  /// Live captions use a flat background for contrast.
  final bool plain;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "reduce motion" setting.
    if (widget.plain || MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    if (widget.plain) return ColoredBox(color: c.liveBg, child: widget.child);
    final dark = context.brightness == Brightness.dark;
    return ColoredBox(
      color: c.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _BlobPainter(_drift, dark ? _darkBlobs : _lightBlobs),
            ),
          ),
          BackdropGroup(child: widget.child),
        ],
      ),
    );
  }
}

typedef _Blob = ({
  Color color,
  Offset base,
  Offset swing,
  double radius,
  double phase,
});

const _lightBlobs = <_Blob>[
  (
    color: Color(0x997DB7FF),
    base: Offset(.15, .12),
    swing: Offset(.18, .10),
    radius: .75,
    phase: 0,
  ),
  (
    color: Color(0x80A0E6FF),
    base: Offset(.90, .45),
    swing: Offset(.12, .16),
    radius: .70,
    phase: .33,
  ),
  (
    color: Color(0x66B3A6FF),
    base: Offset(.30, .85),
    swing: Offset(.20, .08),
    radius: .80,
    phase: .66,
  ),
];

const _darkBlobs = <_Blob>[
  (
    color: Color(0x991D5BD6),
    base: Offset(.15, .10),
    swing: Offset(.18, .10),
    radius: .80,
    phase: 0,
  ),
  (
    color: Color(0x660E86B8),
    base: Offset(.95, .50),
    swing: Offset(.12, .16),
    radius: .70,
    phase: .33,
  ),
  (
    color: Color(0x664A3BB5),
    base: Offset(.25, .90),
    swing: Offset(.20, .08),
    radius: .85,
    phase: .66,
  ),
];

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.t, this.blobs) : super(repaint: t);
  final Animation<double> t;
  final List<_Blob> blobs;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    for (final b in blobs) {
      final a = 2 * math.pi * (t.value + b.phase);
      final center = Offset(
        (b.base.dx + b.swing.dx * math.sin(a)) * w,
        (b.base.dy + b.swing.dy * math.cos(a)) * size.height,
      );
      final r = b.radius * w;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [b.color, b.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.blobs != blobs;
}

/// Frosted glass surface: backdrop blur, a see-through tint, a light rim
/// and a soft top sheen.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.color,
    this.blur = 22,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final dark = context.brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    final filter = ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    final content = CustomPaint(
      foregroundPainter: _RimPainter(radius: radius, dark: dark),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color ?? c.surf, borderRadius: shape),
        child: Padding(padding: padding, child: child),
      ),
    );
    return ClipRRect(
      borderRadius: shape,
      // Grouped filters share one backdrop read, which is much cheaper when
      // a screen has many glass cards.
      child: BackdropGroup.of(context) == null
          ? BackdropFilter(filter: filter, child: content)
          : BackdropFilter.grouped(filter: filter, child: content),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // Sheen: light falling on the upper part of the glass.
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: dark ? .07 : .28),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.restore();
    // Rim: bright at the top-left edge, fading out, faint at the bottom-right.
    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? .35 : .95),
            Colors.white.withValues(alpha: dark ? .06 : .25),
            Colors.white.withValues(alpha: dark ? .16 : .55),
          ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.dark != dark;
}

/// Shrinks its child slightly while pressed. Uses a Listener, so it never
/// competes with the child's own tap handling.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.enabled && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? .96 : 1,
      duration: Duration(milliseconds: _down ? 90 : 260),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

/// Fades a widget in once when it first appears (new caption lines).
class FadeInOnce extends StatefulWidget {
  const FadeInOnce({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
  });
  final Widget child;
  final Duration duration;

  @override
  State<FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<FadeInOnce>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration)
    ..forward();
  late final _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: widget.child);
}

/// Section label above a grouped card ("Captions", "Today").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.rc.ink2,
      ),
    ),
  );
}

/// Large iOS-style page title.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: context.rc.ink,
    ),
  );
}

/// Colored speaker pill: dot + name (+ "edit" when renamable).
class SpeakerPill extends StatelessWidget {
  const SpeakerPill({
    super.key,
    required this.speakerId,
    required this.name,
    this.onTap,
    this.showEdit = false,
    this.fontSize = 13,
    this.selected = false,
  });

  final int speakerId;
  final String name;
  final VoidCallback? onTap;
  final bool showEdit;
  final double fontSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final h = context.hue(speakerId);
    return Material(
      color: h.bg,
      shape: StadiumBorder(
        side: selected ? BorderSide(color: h.fg, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: h.dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: h.fg,
                ),
              ),
              if (showEdit) ...[
                const SizedBox(width: 6),
                Text(
                  'edit',
                  style: TextStyle(
                    fontSize: fontSize - 2,
                    fontWeight: FontWeight.w600,
                    color: h.fg.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill for a session's speaker, wired to its current display name.
class SessionSpeakerPill extends StatelessWidget {
  const SessionSpeakerPill({
    super.key,
    required this.session,
    required this.speakerId,
    this.onRename,
    this.showEdit = false,
  });

  final SessionController session;
  final int speakerId;
  final void Function(int speakerId)? onRename;
  final bool showEdit;

  @override
  Widget build(BuildContext context) => SpeakerPill(
    speakerId: speakerId,
    name: session.displayName(speakerId),
    showEdit: showEdit && speakerId != 0 && onRename != null,
    onTap: speakerId == 0 || onRename == null
        ? null
        : () => onRename!(speakerId),
  );
}

/// Small rounded tag ("User edited", "Interrupted").
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon, this.bg, this.fg, this.onTap});

  final String text;
  final IconData? icon;
  final Color? bg;
  final Color? fg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final color = fg ?? c.primary;
    return Material(
      color: bg ?? c.pc,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Source evidence chip showing the line's timestamp.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) =>
      Tag(label, icon: Icons.format_quote_rounded, onTap: onTap);
}

/// Filled blue pill button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = color ?? context.rc.primaryFill;
    final enabled = onPressed != null;
    return Pressable(
      enabled: onPressed != null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(base, Colors.white, 0.12)!, base],
            ),
            boxShadow: [
              BoxShadow(
                color: base.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onPressed,
              child: SizedBox(
                height: 52,
                child: _ButtonLabel(
                  label: label,
                  icon: icon,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass pill button (Copy, Pause, Retry).
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      enabled: onPressed != null,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Glass(
          radius: 28,
          color: context.rc.sheet,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                height: 52,
                child: _ButtonLabel(
                  label: label,
                  icon: icon,
                  color: color ?? context.rc.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.label, this.icon, required this.color});
  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Round glass icon button (close, fullscreen, check).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.filled = false,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    final button = Material(
      color: filled ? c.primaryFill : c.sheet,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.5,
            color: filled ? Colors.white : c.ink,
          ),
        ),
      ),
    );
    return Pressable(
      enabled: onPressed != null,
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip, child: button),
    );
  }
}

/// iOS-style navigation header: back link, centered title + subtitle,
/// optional trailing action.
class NavHeader extends StatelessWidget {
  const NavHeader({
    super.key,
    required this.backLabel,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
  });

  final String backLabel;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: c.primary,
                padding: const EdgeInsets.only(left: 4, right: 8),
              ),
              onPressed: onBack ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.chevron_left_rounded, size: 30),
              label: Text(backLabel, style: const TextStyle(fontSize: 16)),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 12, color: c.ink2)),
            ],
          ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}

/// Amber notice ("Mic interrupted at 07:12. Earlier lines are saved.").
class WarnBanner extends StatelessWidget {
  const WarnBanner({super.key, required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.warnc,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_off_rounded, color: c.warn, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.warnInk,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// Centered full-page message: tinted icon, title, body, buttons at the bottom.
class StatusMessage extends StatelessWidget {
  const StatusMessage({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.body,
    this.actions = const [],
    this.below,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? body;
  final List<Widget> actions;

  /// Optional content under the message (e.g. the unnamed speaker list).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 38, color: iconColor),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        body!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: c.ink2),
                      ),
                    ],
                    if (below != null) ...[const SizedBox(height: 28), below!],
                  ],
                ),
              ),
            ),
          ),
          for (final a in actions)
            Padding(padding: const EdgeInsets.only(top: 10), child: a),
        ],
      ),
    );
  }
}
