import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// SnapLink Vant 摄影混合视觉主题配置
class VantTheme {
  VantTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: SnapColors.primary,
      scaffoldBackgroundColor: SnapColors.background,
      canvasColor: SnapColors.surface,
      cardColor: SnapColors.card,
      dividerColor: SnapColors.border,

      colorScheme: const ColorScheme.dark(
        primary: SnapColors.primary,
        onPrimary: SnapColors.textInverse,
        surface: SnapColors.surface,
        onSurface: SnapColors.textPrimary,
        error: SnapColors.danger,
        onError: Colors.white,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: SnapColors.surface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: SnapColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(
          color: SnapColors.textPrimary,
          size: 20,
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: SnapColors.surface,
        selectedItemColor: SnapColors.primary,
        unselectedItemColor: SnapColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
      ),

      cardTheme: CardThemeData(
        color: SnapColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: SnapColors.border, width: 0.8),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: SnapColors.primary,
        inactiveTrackColor: SnapColors.border,
        thumbColor: SnapColors.primary,
        overlayColor: SnapColors.primary.withAlpha(40),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SnapColors.primary,
          foregroundColor: SnapColors.textInverse,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: SnapColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: SnapColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: SnapColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(color: SnapColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w400),
        labelSmall: TextStyle(color: SnapColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w400),
      ),
    );
  }
}
