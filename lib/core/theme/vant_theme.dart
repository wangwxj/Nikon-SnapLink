import 'package:flutter/material.dart';
import '../constants/colors.dart';


/// SnapLink Vant 摄影混合视觉主题配置。
class VantTheme {
  VantTheme._();

  static ThemeData get darkTheme => _build(
        palette: SnapPalette.dark,
        brightness: Brightness.dark,
      );

  static ThemeData get lightTheme => _build(
        palette: SnapPalette.light,
        brightness: Brightness.light,
      );

  /// 将用户外观模式解析为当前应使用的亮度。
  ///
  /// 刻意不使用 `Theme.of(context).brightness`：MaterialApp 的
  /// `AnimatedTheme` 过渡期间该值仍可能是旧亮度，会让依赖调色板的
  /// 静态语义色停留在上一套主题。
  static Brightness brightnessFor(ThemeMode mode, Brightness platformBrightness) =>
      switch (mode) {
        ThemeMode.dark => Brightness.dark,
        ThemeMode.light => Brightness.light,
        ThemeMode.system => platformBrightness,
      };

  static ThemeData _build({
    required SnapPalette palette,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.textInverse,
      secondary: palette.primaryDark,
      onSecondary: palette.textInverse,
      error: palette.danger,
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.textPrimary,
    );

    final divider = palette.border;
    final textTheme = TextTheme(
      headlineMedium: TextStyle(color: palette.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: palette.textPrimary, fontSize: 14, fontWeight: FontWeight.w400),
      bodyMedium: TextStyle(color: palette.textSecondary, fontSize: 13, fontWeight: FontWeight.w400),
      labelSmall: TextStyle(color: palette.textTertiary, fontSize: 11, fontWeight: FontWeight.w400),
    );

    return ThemeData(
      brightness: brightness,
      primaryColor: palette.primary,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      cardColor: palette.card,
      dividerColor: divider,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: palette.textPrimary, size: 20),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surface,
        selectedItemColor: palette.primary,
        unselectedItemColor: palette.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border, width: 0.8),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        inactiveTrackColor: palette.border,
        thumbColor: palette.primary,
        overlayColor: palette.primary.withAlpha(40),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.textInverse,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.cardElevated,
        labelStyle: TextStyle(color: palette.textSecondary),
        hintStyle: TextStyle(color: palette.textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.primary, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.cardElevated,
        titleTextStyle: TextStyle(color: palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: palette.textSecondary, fontSize: 13),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.cardElevated,
        textStyle: TextStyle(color: palette.textPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? palette.primary : palette.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary.withAlpha(isDark ? 90 : 70)
              : palette.border,
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 0.6, space: 0.6),
      textTheme: textTheme,
    );
  }
}
