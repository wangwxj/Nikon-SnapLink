import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../protocol/nikon_liveview_parser.dart';

/// 摄影专业监看辅助图层 (构图网格、十字对焦点、安全框、对焦框、水平仪)
class MonitorOverlayPainter extends CustomPainter {
  final bool showGrid;
  final bool showCrosshair;
  final bool showSafeArea;
  final List<NikonAfBox>? afBoxes;
  final NikonFocusState focusState;
  final NikonLevelInfo? levelInfo;
  final int wholeWidth;
  final int wholeHeight;

  MonitorOverlayPainter({
    this.showGrid = true,
    this.showCrosshair = true,
    this.showSafeArea = false,
    this.afBoxes,
    this.focusState = NikonFocusState.unknown,
    this.levelInfo,
    this.wholeWidth = 640,
    this.wholeHeight = 424,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. 三分构图网格线
    if (showGrid) {
      final gridPaint = Paint()
        ..color = SnapColors.gridLines
        ..strokeWidth = 1.0;

      final wThird = size.width / 3.0;
      final hThird = size.height / 3.0;

      // 竖线
      canvas.drawLine(Offset(wThird, 0), Offset(wThird, size.height), gridPaint);
      canvas.drawLine(Offset(wThird * 2, 0), Offset(wThird * 2, size.height), gridPaint);

      // 横线
      canvas.drawLine(Offset(0, hThird), Offset(size.width, hThird), gridPaint);
      canvas.drawLine(Offset(0, hThird * 2), Offset(size.width, hThird * 2), gridPaint);
    }

    // 2. 90% 安全框
    if (showSafeArea) {
      final safePaint = Paint()
        ..color = const Color(0x66FFC800)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      final safeRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.9,
        height: size.height * 0.9,
      );
      canvas.drawRect(safeRect, safePaint);
    }

    // 3. 尼康硬件对焦框渲染 (来自 0x9428 / 0x9203 头部对焦包)
    if (afBoxes != null && afBoxes!.isNotEmpty) {
      final baseW = wholeWidth > 0 ? wholeWidth.toDouble() : 640.0;
      final baseH = wholeHeight > 0 ? wholeHeight.toDouble() : 424.0;

      for (final box in afBoxes!) {
        // 归一化坐标转换至当前画布尺寸
        final rect = Rect.fromLTWH(
          (box.x / baseW) * size.width,
          (box.y / baseH) * size.height,
          ((box.width / baseW) * size.width).clamp(20.0, size.width),
          ((box.height / baseH) * size.height).clamp(20.0, size.height),
        );

        Color boxColor;
        switch (focusState) {
          case NikonFocusState.match:
            boxColor = const Color(0xFF00E676); // 合焦绿色
            break;
          case NikonFocusState.deviated:
            boxColor = const Color(0xFFFF5252); // 未合焦红色
            break;
          case NikonFocusState.unknown:
            boxColor = const Color(0xFFFFD600); // 测距黄色
        }

        final afPaint = Paint()
          ..color = boxColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;

        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), afPaint);
      }
    }

    // 4. 中央十字对焦点 (若无硬件对焦点时展示)
    if (showCrosshair && (afBoxes == null || afBoxes!.isEmpty)) {
      final crossPaint = Paint()
        ..color = SnapColors.crosshair
        ..strokeWidth = 1.5;

      final cx = size.width / 2.0;
      final cy = size.height / 2.0;
      const len = 12.0;
      const gap = 4.0;

      canvas.drawLine(Offset(cx - len, cy), Offset(cx - gap, cy), crossPaint);
      canvas.drawLine(Offset(cx + gap, cy), Offset(cx + len, cy), crossPaint);
      canvas.drawLine(Offset(cx, cy - len), Offset(cx, cy - gap), crossPaint);
      canvas.drawLine(Offset(cx, cy + gap), Offset(cx, cy + len), crossPaint);

      // 中心微红点
      canvas.drawCircle(Offset(cx, cy), 1.5, Paint()..color = SnapColors.danger);
    }

    // 5. 电子水平仪指示 (横滚倾角)
    if (levelInfo != null && levelInfo!.rollAngle != 0.0) {
      final cx = size.width / 2.0;
      final cy = size.height / 2.0;
      final rad = levelInfo!.rollAngle * (math.pi / 180.0);
      final isLevel = levelInfo!.rollAngle.abs() < 1.0;
      final levelPaint = Paint()
        ..color = isLevel ? const Color(0xFF00E676) : Colors.white.withAlpha(160)
        ..strokeWidth = 1.5;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(-rad);
      canvas.drawLine(const Offset(-40, 0), const Offset(-15, 0), levelPaint);
      canvas.drawLine(const Offset(15, 0), const Offset(40, 0), levelPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant MonitorOverlayPainter oldDelegate) {
    return oldDelegate.showGrid != showGrid ||
           oldDelegate.showCrosshair != showCrosshair ||
           oldDelegate.showSafeArea != showSafeArea ||
           oldDelegate.afBoxes != afBoxes ||
           oldDelegate.focusState != focusState ||
           oldDelegate.levelInfo != levelInfo;
  }

  /// 纯绘制图层：不参与命中测试，避免盖住下层按钮 (CustomPainter.hitTest 默认 true 会吞点击)
  @override
  bool hitTest(Offset position) => false;
}

/// 实时亮度直方图微组件 (Luminance Histogram)
class HistogramWidget extends StatelessWidget {
  final List<double>? values; // 256 个灰度桶 (0.0 ~ 1.0)
  final double width;
  final double height;

  const HistogramWidget({
    super.key,
    this.values,
    this.width = 110,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: CustomPaint(
        size: Size(width - 8, height - 8),
        painter: _HistogramPainter(values),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<double>? values;

  _HistogramPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SnapColors.histogram
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final fillPaint = Paint()
      ..color = SnapColors.histogram.withAlpha(60)
      ..style = PaintingStyle.fill;

    // 默认示例高斯分布直方图曲线 (当暂无动态数据时优雅展示)
    final bins = values ?? List.generate(32, (i) {
      final x = (i - 16) / 8.0;
      return (1.0 / (1.0 + x * x)) * 0.8;
    });

    final path = Path();
    path.moveTo(0, size.height);

    final stepX = size.width / (bins.length - 1);
    for (var i = 0; i < bins.length; i++) {
      final h = size.height * (1.0 - bins[i].clamp(0.0, 1.0));
      path.lineTo(i * stepX, h);
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) => true;
}
