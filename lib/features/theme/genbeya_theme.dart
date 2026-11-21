import 'package:material_ui/material_ui.dart';

/// Genbeya's colour tokens (`src/client/styles/tokens.css` in Genbeya), so the
/// app looks like the desktop in both themes.
class GenbeyaTokens {
  const GenbeyaTokens({
    required this.app,
    required this.panel,
    required this.raised,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentText,
    required this.border,
  });

  final Color app;
  final Color panel;
  final Color raised;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentText;
  final Color border;

  static const dark = GenbeyaTokens(
    app: Color(0xFF0F1012),
    panel: Color(0xFF16171A),
    raised: Color(0xFF1C1D21),
    text: Color(0xFFE8E8EA),
    muted: Color(0xFFA1A2AA),
    accent: Color(0xFF7C7FF2),
    accentText: Color(0xFFA9ABFF),
    border: Color(0x14FFFFFF),
  );

  static const light = GenbeyaTokens(
    app: Color(0xFFF3F3F5),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    text: Color(0xFF1C1D21),
    muted: Color(0xFF5F6068),
    accent: Color(0xFF5B5FE0),
    accentText: Color(0xFF4B4FD4),
    border: Color(0x1A141428),
  );
}

class GenbeyaTheme {
  static ThemeData dark() => _theme(GenbeyaTokens.dark, Brightness.dark);
  static ThemeData light() => _theme(GenbeyaTokens.light, Brightness.light);

  static ThemeData _theme(GenbeyaTokens t, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: brightness,
        ).copyWith(
          primary: t.accent,
          surface: t.panel,
          onSurface: t.text,
          outlineVariant: t.border,
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: t.app,
      appBarTheme: AppBarTheme(
        backgroundColor: t.app,
        foregroundColor: t.text,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: t.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: t.border),
        ),
      ),
      dividerColor: t.border,
    );
  }
}
