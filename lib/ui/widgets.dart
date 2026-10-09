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

/// Page background: tinted base with soft blue glows.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child, this.plain = false});
  final Widget child;

  /// Live captions use a flat background for contrast.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final c = context.rc;
    if (plain) return ColoredBox(color: c.liveBg, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(color: c.bg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.9, -0.9),
            radius: 1.1,
            colors: [c.glowA, c.glowA.withValues(alpha: 0)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1, 0.6),
              radius: 1.0,
              colors: [c.glowB, c.glowB.withValues(alpha: 0)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Frosted glass surface.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.color,
    this.blur = 18,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? c.surf,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.75),
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
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
    return Opacity(
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
    return Opacity(
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
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
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
