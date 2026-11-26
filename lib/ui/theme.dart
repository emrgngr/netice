import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'swipe_back.dart';

/// Netice tasarım dili: tek vurgu rengi, anlamlı renkler, sakin yüzeyler.
class NColors {
  static const ink = Color(0xFF0F1B3D); // derin lacivert-mürekkep
  static const emerald = Color(0xFF10B981); // tek vurgu: doğru, onay
  static const ivory = Color(0xFFF6F3EC); // kâğıt beyazı zemin
  static const coral = Color(0xFFE8613C); // yanlış
  static const amber = Color(0xFFF2B33D); // kontrol gerekiyor
  static const gray = Color(0xFF9AA0AE); // boş

  static const darkBg = Color(0xFF0B1430);
  static const darkSurface = Color(0xFF17244D);

  /// Gece modunda dolu düğmelerin zümrüdü: koyu ton, üstünde beyaz yazı.
  static const nightEmerald = Color(0xFF05875F);

  /// Yeşil zeminde yazı ve simge her zaman beyazdır (lacivert kullanılmaz).
  /// Beyaz yazının okunması için dolu düğmelerde biraz koyu zümrüt kullanılır.
  static const onGreen = Colors.white;

  /// Gündüz modunda dolu düğmelerin zümrüdü (üstünde beyaz yazı).
  static const deepEmerald = Color(0xFF059669);

  /// Dolu (zümrüt) düğme zemini ve yazısı: zemin koyu zümrüt, yazı beyaz.
  static Color buttonBg(bool dark) => dark ? nightEmerald : deepEmerald;
  static Color buttonFg(bool dark) => onGreen;

  /// Gece modunda grafiklerde lacivert yerine kullanılan açık lacivert.
  static const nightNavy = Color(0xFF6C7BB5);

  /// Grafik ve çubuklarda "lacivert" veri rengi: gece modunda açık lacivert.
  static Color navy(bool dark) => dark ? nightNavy : ink;

  /// Gece modunda koyu zemin üstündeki yazı için açık "mürekkep".
  static const nightInk = Color(0xFFF1F4FB);

  /// Gece modu kuralı: koyu zemin üstündeki yazı ve simgeler açık renkli olur.
  /// Renk koyu zemine karşı yeterince okunmuyorsa (kontrast < 4.5) tonunu
  /// koruyarak açılır; gündüz modunda renk olduğu gibi kalır.
  static Color readable(Color c, {required bool dark}) {
    if (!dark) return c;
    final opaque = c.withValues(alpha: 1);
    if (_contrast(opaque, darkSurface) >= 4.5) return c;
    var out = opaque;
    for (var t = 0.1; t <= 1.0 && _contrast(out, darkSurface) < 4.5; t += 0.1) {
      out = Color.lerp(opaque, nightInk, t)!;
    }
    return out.withValues(alpha: c.a < 0.6 ? 0.85 : c.a);
  }

  /// [readable] için kısa yol: temanın parlaklığına göre.
  static Color on(BuildContext context, Color c) =>
      readable(c, dark: Theme.of(context).brightness == Brightness.dark);

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }
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

/// Zümrüt gradyan: üstündeki yazı ve simgeler beyazdır.
const emeraldGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF10B981), Color(0xFF047857)],
);

/// Gece modunda grafik çubukları: koyu zeminde seçilebilen açık lacivert.
const nightNavyGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF8391CC), Color(0xFF4E5C99)],
);

/// Gece modunda büyük düğmelerin zümrüt gradyanı: üstünde beyaz yazı okunur.
const nightEmeraldGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0E9F6E), Color(0xFF056A4B)],
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
        onSurface: NColors.nightInk,
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
      onPrimary: Colors.white,
      secondary: NColors.emerald,
      onSecondary: Colors.white,
      tertiary: NColors.amber,
      onTertiary: NColors.ink,
      error: NColors.coral,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      // İkincil yazılar (açıklamalar) gece modunda da açık gri-mavi.
      onSurfaceVariant: isDark ? const Color(0xFFBCC6E3) : onSurface,
      surfaceContainerHighest: isDark ? const Color(0xFF22315F) : const Color(0xFFEDE9DF),
      outline: isDark ? const Color(0xFF6B79A6) : const Color(0xFFB9B3A6),
      outlineVariant: isDark ? const Color(0xFF2F3F70) : const Color(0xFFE2DDD1),
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
        indicatorColor: NColors.buttonBg(isDark),
        iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(color: s.contains(WidgetState.selected) ? NColors.onGreen : onSurface)),
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
          backgroundColor: NColors.buttonBg(isDark),
          foregroundColor: NColors.buttonFg(isDark),
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
      // Telefonda (Android ve iPhone) sayfanın her yerinden soldan sağa
      // kaydırınca önceki sayfaya dönülür.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: SwipeBackPageTransitionsBuilder(),
        TargetPlatform.iOS: SwipeBackPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFFE9ECF5) : NColors.ink,
        contentTextStyle: TextStyle(
            fontFamily: _font, fontWeight: FontWeight.w600, color: isDark ? NColors.ink : Colors.white),
        actionTextColor: NColors.emerald,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 6,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(fontFamily: _font, fontSize: 20, fontWeight: FontWeight.w800, color: onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurface.withValues(alpha: isDark ? 0.85 : 0.75),
        textColor: onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NColors.emerald : null),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? NColors.emerald : scheme.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NColors.emerald : null),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? NColors.buttonBg(isDark) : surface),
          // Yeşil (seçili) zeminde yazı ve simge beyaz.
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? NColors.onGreen : onSurface),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: _font, fontWeight: FontWeight.w600)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: NColors.buttonBg(isDark),
        checkmarkColor: NColors.onGreen,
        side: BorderSide(color: scheme.outlineVariant),
        // Seçili (yeşil) çipte yazı beyaz.
        labelStyle: TextStyle(
            fontFamily: _font,
            fontWeight: FontWeight.w600,
            color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? NColors.onGreen : onSurface)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: NColors.emerald,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: NColors.ink.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontFamily: _font, color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? NColors.emerald : NColors.ink,
          textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textTheme: base.textTheme.apply(bodyColor: onSurface, displayColor: onSurface).copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NColors.emerald, width: 1.6),
        ),
        floatingLabelStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, color: isDark ? NColors.emerald : NColors.ink),
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
