import 'package:flutter/material.dart';

/// SnapLink 专业摄影与 Vant 混合设计风格调色板。
///
/// [SnapColors] 的语义 getter 会随当前 MaterialApp 亮度切换；
/// 网格、斑马纹等画布叠加色保持固定，避免浅色主题影响取景判断。
class SnapColors {
  SnapColors._();

  static SnapPalette _current = SnapPalette.dark;

  static void use(Brightness brightness) {
    _current = brightness == Brightness.dark ? SnapPalette.dark : SnapPalette.light;
  }

  static Color get background => _current.background;
  static Color get surface => _current.surface;
  static Color get card => _current.card;
  static Color get cardElevated => _current.cardElevated;
  static Color get border => _current.border;
  static Color get borderLight => _current.borderLight;
  static Color get primary => _current.primary;
  static Color get primaryDark => _current.primaryDark;
  static Color get textPrimary => _current.textPrimary;
  static Color get textSecondary => _current.textSecondary;
  static Color get textTertiary => _current.textTertiary;
  static Color get textInverse => _current.textInverse;
  static Color get success => _current.success;
  static Color get warning => _current.warning;
  static Color get danger => _current.danger;

  // 固定品牌色
  static const Color nikonYellow = Color(0xFFFFC800);
  static const Color nikonGold = Color(0xFFE6A23C);
  static const Color info = Color(0xFF1989FA);

  // 监看取景专用颜色：始终叠加在相机画面之上
  static const Color zebraPattern = Color(0x99FF5252);
  static const Color focusPeaking = Color(0xFF00E676);
  static const Color gridLines = Color(0x4DFFFFFF);
  static const Color crosshair = Color(0xCCFFFFFF);
  static const Color histogram = Color(0xCCFFFFFF);

  // Vant UI 浅色卡片备用配色 (用于特定导出卡片)
  static const Color vantLightBg = Color(0xFFF7F8FA);
  static const Color vantLightCard = Color(0xFFFFFFFF);
  static const Color vantLightBorder = Color(0xFFEBEDF0);
  static const Color vantLightText = Color(0xFF323233);
  static const Color vantLightSubText = Color(0xFF969799);
}

/// 一套完整的主题语义色。
class SnapPalette {
  final Color background;
  final Color surface;
  final Color card;
  final Color cardElevated;
  final Color border;
  final Color borderLight;
  final Color primary;
  final Color primaryDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color success;
  final Color warning;
  final Color danger;

  const SnapPalette({
    required this.background,
    required this.surface,
    required this.card,
    required this.cardElevated,
    required this.border,
    required this.borderLight,
    required this.primary,
    required this.primaryDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const dark = SnapPalette(
    background: Color(0xFF121214),
    surface: Color(0xFF1A1A1E),
    card: Color(0xFF222228),
    cardElevated: Color(0xFF2A2A32),
    border: Color(0xFF2E2E38),
    borderLight: Color(0xFF3E3E4C),
    primary: Color(0xFFFFC800),
    primaryDark: Color(0xFFCC9F00),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFA0A0AB),
    textTertiary: Color(0xFF6E6E7A),
    textInverse: Color(0xFF141416),
    success: Color(0xFF07C160),
    warning: Color(0xFFFF976A),
    danger: Color(0xFFEE0A24),
  );

  /// 白底黄点缀：暖白页面、纯白卡片、深琥珀强调色。
  static const light = SnapPalette(
    background: Color(0xFFFFFDF5),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFFFF7DF),
    border: Color(0xFFE8DFC1),
    borderLight: Color(0xFFD6C99F),
    primary: Color(0xFFA66F00),
    primaryDark: Color(0xFF7A5200),
    textPrimary: Color(0xFF29251C),
    textSecondary: Color(0xFF6F6757),
    textTertiary: Color(0xFF9A8F77),
    textInverse: Color(0xFFFFFFFF),
    success: Color(0xFF087F3E),
    warning: Color(0xFFB45309),
    danger: Color(0xFFC62828),
  );
}
