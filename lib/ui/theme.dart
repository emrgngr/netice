import 'package:material_ui/material_ui.dart';

/// Netice tasarım dili: tek vurgu rengi, anlamlı renkler, sakin yüzeyler.
class NColors {
  static const ink = Color(0xFF0F1B3D); // derin lacivert-mürekkep
  static const emerald = Color(0xFF10B981); // tek vurgu: doğru, onay
  static const ivory = Color(0xFFF6F3EC); // kâğıt beyazı zemin
  static const coral = Color(0xFFE8613C); // yanlış
  static const amber = Color(0xFFF2B33D); // kontrol gerekiyor
  static const gray = Color(0xFF9AA0AE); // boş

  static const darkBg = Color(0xFF0A1229);
  static const darkSurface = Color(0xFF142147);
}

/// Rakamlar için eş genişlikli (tabular) yazı.
const tabular = [FontFeature.tabularFigures()];

/// Uygulama simgesindeki derin lacivert gradyan; "kahraman" panellerde kullanılır.
const inkGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1E2E60), Color(0xFF0F1B3D), Color(0xFF080F26)],
  stops: [0, 0.55, 1],
);

const emeraldGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF34D399), Color(0xFF059669)],
);

class NTheme {
  static const _font = 'PlusJakartaSans';

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: NColors.ivory,
        surface: Colors.white,
        onSurface: NColors.ink,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: NColors.darkBg,
        surface: NColors.darkSurface,
        onSurface: const Color(0xFFE9ECF5),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color onSurface,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? NColors.emerald : NColors.ink,
      onPrimary: isDark ? NColors.ink : Colors.white,
      secondary: NColors.emerald,
      onSecondary: NColors.ink,
      tertiary: NColors.amber,
      onTertiary: NColors.ink,
      error: NColors.coral,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: isDark ? const Color(0xFF1C2A55) : const Color(0xFFEDE9DF),
      outline: isDark ? const Color(0xFF52608C) : const Color(0xFFB9B3A6),
      outlineVariant: isDark ? const Color(0xFF2A3967) : const Color(0xFFE2DDD1),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: _font,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamily: _font, fontSize: 20, fontWeight: FontWeight.w700, color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: isDark ? 0 : 6,
        shadowColor: NColors.ink.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isDark ? scheme.outlineVariant : Colors.white),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: NColors.emerald.withValues(alpha: isDark ? 0.25 : 0.16),
        elevation: 8,
        shadowColor: NColors.ink.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600, color: onSurface)),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: NColors.emerald,
        labelColor: onSurface,
        unselectedLabelColor: onSurface.withValues(alpha: 0.55),
        labelStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NColors.emerald,
          foregroundColor: NColors.ink,
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
