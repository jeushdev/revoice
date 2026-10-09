import 'package:flutter/material.dart';

/// Design tokens from "ReVise Mockups v3" (iOS liquid glass), light and dark.
@immutable
class ReviseColors extends ThemeExtension<ReviseColors> {
  const ReviseColors({
    required this.bg,
    required this.glowA,
    required this.glowB,
    required this.liveBg,
    required this.surf,
    required this.sheet,
    required this.surf2,
    required this.surf3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.primary,
    required this.primaryFill,
    required this.pc,
    required this.opc,
    required this.err,
    required this.errc,
    required this.errText,
    required this.warn,
    required this.warnc,
    required this.warnInk,
    required this.okBg,
    required this.okFg,
    required this.okDot,
  });

  final Color bg, glowA, glowB, liveBg, surf, sheet, surf2, surf3;
  final Color ink, ink2, ink3, line;
  final Color primary, primaryFill, pc, opc;
  final Color err, errc, errText, warn, warnc, warnInk;
  final Color okBg, okFg, okDot;

  static const light = ReviseColors(
    bg: Color(0xFFEAF5FE),
    glowA: Color(0x5571B7FF),
    glowB: Color(0x40B9E2FF),
    liveBg: Color(0xFFF7FBFF),
    surf: Color(0x9EFFFFFF),
    sheet: Color(0xCCFFFFFF),
    surf2: Color(0xFFF2F2F7),
    surf3: Color(0xFFE5E5EA),
    ink: Color(0xFF0B0B0F),
    ink2: Color(0xFF5E5E66),
    ink3: Color(0xFF6C6C73),
    line: Color(0x2E3C3C43),
    primary: Color(0xFF0A5FD6),
    primaryFill: Color(0xFF0A5FD6),
    pc: Color(0xFFE0ECFF),
    opc: Color(0xFF0B2A5E),
    err: Color(0xFFD70015),
    errc: Color(0xFFFFE1DF),
    errText: Color(0xFFD70015),
    warn: Color(0xFF8A5300),
    warnc: Color(0xFFFFEBCC),
    warnInk: Color(0xFF3D2600),
    okBg: Color(0xFFDDF5E4),
    okFg: Color(0xFF0E5A2A),
    okDot: Color(0xFF1FA34A),
  );

  static const dark = ReviseColors(
    bg: Color(0xFF040A18),
    glowA: Color(0x661A4FA8),
    glowB: Color(0x40103A7A),
    liveBg: Color(0xFF030814),
    surf: Color(0x8C1A2844),
    sheet: Color(0xDB0E182C),
    surf2: Color(0xFF2C2C2E),
    surf3: Color(0xFF3A3A3C),
    ink: Color(0xFFFFFFFF),
    ink2: Color(0xFFAEAEB2),
    ink3: Color(0xFF8E8E93),
    line: Color(0x33FFFFFF),
    primary: Color(0xFF82B6FF),
    primaryFill: Color(0xFF1667E0),
    pc: Color(0xFF152C52),
    opc: Color(0xFFD6E6FF),
    err: Color(0xFFE5332A),
    errc: Color(0xFF3B1412),
    errText: Color(0xFFFF6961),
    warn: Color(0xFFFFB340),
    warnc: Color(0xFF3A2700),
    warnInk: Color(0xFFFFE6C2),
    okBg: Color(0xFF103A20),
    okFg: Color(0xFFB8F0C9),
    okDot: Color(0xFF30D158),
  );

  @override
  ReviseColors copyWith() => this;

  @override
  ReviseColors lerp(ReviseColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Speaker hue set: bg (pill), fg (text), dot (accent, landscape bar).
typedef SpeakerHue = ({Color bg, Color fg, Color dot});

const _lightHues = <SpeakerHue>[
  (bg: Color(0xFFE6E3EC), fg: Color(0xFF4B4757), dot: Color(0xFF8D889A)),
  (bg: Color(0xFFDDEBFB), fg: Color(0xFF1D4E89), dot: Color(0xFF3A7FD5)),
  (bg: Color(0xFFD9F3E6), fg: Color(0xFF0E5A3A), dot: Color(0xFF1E9E63)),
  (bg: Color(0xFFF8E7D3), fg: Color(0xFF6E4410), dot: Color(0xFFC27A1C)),
  (bg: Color(0xFFF9E0EA), fg: Color(0xFF7F1E48), dot: Color(0xFFD2467F)),
];

const _darkHues = <SpeakerHue>[
  (bg: Color(0xFF2D2937), fg: Color(0xFFCFCBD9), dot: Color(0xFF8E899B)),
  (bg: Color(0xFF1E3A5F), fg: Color(0xFFC9DFFF), dot: Color(0xFF6FA8F5)),
  (bg: Color(0xFF18412F), fg: Color(0xFFBDEFD5), dot: Color(0xFF4CC995)),
  (bg: Color(0xFF4A3418), fg: Color(0xFFF6DDB8), dot: Color(0xFFE0A253)),
  (bg: Color(0xFF4D2236), fg: Color(0xFFFCD0E0), dot: Color(0xFFEE84AE)),
];

/// Speaker 0 is unknown (grey); 1-4 are blue, green, amber, pink, then repeat.
SpeakerHue speakerHue(int speakerId, Brightness brightness) {
  final hues = brightness == Brightness.dark ? _darkHues : _lightHues;
  if (speakerId <= 0) return hues[0];
  return hues[1 + (speakerId - 1) % 4];
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? ReviseColors.dark
      : ReviseColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF0A5FD6),
        brightness: brightness,
      ).copyWith(
        primary: c.primaryFill,
        onPrimary: Colors.white,
        error: c.err,
        surface: c.bg,
        onSurface: c.ink,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    sliderTheme: SliderThemeData(
      activeTrackColor: c.primaryFill,
      inactiveTrackColor: c.surf3,
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.okDot : c.surf3,
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

extension ReviseColorsX on BuildContext {
  ReviseColors get rc => Theme.of(this).extension<ReviseColors>()!;
  Brightness get brightness => Theme.of(this).brightness;
  SpeakerHue hue(int speakerId) => speakerHue(speakerId, brightness);
}
