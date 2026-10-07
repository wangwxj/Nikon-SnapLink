import 'package:flutter/material.dart';

/// SnapLink 专业摄影与 Vant 混合设计风格调色板
class SnapColors {
  SnapColors._();

  // 基础背景色 (专业摄影暗黑模式)
  static const Color background = Color(0xFF121214);
  static const Color surface = Color(0xFF1A1A1E);
  static const Color card = Color(0xFF222228);
  static const Color cardElevated = Color(0xFF2A2A32);
  static const Color border = Color(0xFF2E2E38);
  static const Color borderLight = Color(0xFF3E3E4C);

  // 品牌色：尼康金与高亮黄色
  static const Color nikonYellow = Color(0xFFFFC800);
  static const Color nikonGold = Color(0xFFE6A23C);
  static const Color primary = Color(0xFFFFC800);
  static const Color primaryDark = Color(0xFFCC9F00);

  // 文本色彩
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFA0A0AB);
  static const Color textTertiary = Color(0xFF6E6E7A);
  static const Color textInverse = Color(0xFF141416);

  // 状态与指示色
  static const Color success = Color(0xFF07C160); // Vant Success
  static const Color warning = Color(0xFFFF976A); // Vant Warning
  static const Color danger = Color(0xFFEE0A24);  // Vant Danger
  static const Color info = Color(0xFF1989FA);    // Vant Primary Blue

  // 监看取景专用颜色
  static const Color zebraPattern = Color(0x99FF5252); // 斑马纹警告红
  static const Color focusPeaking = Color(0xFF00E676); // 峰值对焦绿
  static const Color gridLines = Color(0x4DFFFFFF);   // 三分线半透白
  static const Color crosshair = Color(0xCCFFFFFF);   // 准星白
  static const Color histogram = Color(0xCCFFFFFF);   // 直方图

  // Vant UI 浅色卡片备用配色 (用于特定导出卡片)
  static const Color vantLightBg = Color(0xFFF7F8FA);
  static const Color vantLightCard = Color(0xFFFFFFFF);
  static const Color vantLightBorder = Color(0xFFEBEDF0);
  static const Color vantLightText = Color(0xFF323233);
  static const Color vantLightSubText = Color(0xFF969799);
}
