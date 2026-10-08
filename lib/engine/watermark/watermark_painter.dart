import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/utils/exif_helper.dart';
import '../filter/photo_filter.dart';
import 'watermark_template.dart';

/// 画布总尺寸与源图片放置矩形结果
class LayoutMetrics {
  final double totalWidth;
  final double totalHeight;
  final Rect imageRect;

  const LayoutMetrics({
    required this.totalWidth,
    required this.totalHeight,
    required this.imageRect,
  });
}

/// 摄影画廊级水印排版绘制引擎 (全新精编 6 大高质感模板 · 彻底淘汰同质化低质边框)
/// 核心采用基于 1200px 基准的标准动态缩放公式: scale = canvasWidth / 1200.0
class WatermarkCanvasPainter extends CustomPainter {
  final ui.Image? image;
  final PhotoMetadata metadata;
  final WatermarkTemplate template;
  final PhotoFilterType filterType;
  final double filterIntensity;
  final PhotoEditAdjustments adjustments;
  final double spacingScale;
  final bool showDetails;

  /// 边框/卡片底色是否为黑底 (false = 白底)
  final bool cardDark;

  /// 字体颜色是否为黑字 (false = 白字)
  final bool textDark;

  /// 水印字体 (null = 各文字保持模板原生字体)
  final String? fontFamily;

  WatermarkCanvasPainter({
    required this.image,
    required this.metadata,
    required this.template,
    this.filterType = PhotoFilterType.original,
    this.filterIntensity = 1.0,
    this.adjustments = const PhotoEditAdjustments(),
    this.spacingScale = 1.0,
    this.showDetails = true,
    this.cardDark = false,
    this.textDark = false,
    this.fontFamily,
  });

  /// 计算在给定源图尺寸与模板下的目标排版画布尺寸与图片放置位置
  static LayoutMetrics computeLayout(double srcW, double srcH, WatermarkTemplate template, [double spacing = 1.0]) {
    switch (template) {
      case WatermarkTemplate.none: {
        return LayoutMetrics(
          totalWidth: srcW,
          totalHeight: srcH,
          imageRect: Rect.fromLTWH(0, 0, srcW, srcH),
        );
      }
      case WatermarkTemplate.inPhotoOverlay: {
        // 满幅无边框，文字排在照片内部
        return LayoutMetrics(
          totalWidth: srcW,
          totalHeight: srcH,
          imageRect: Rect.fromLTWH(0, 0, srcW, srcH),
        );
      }
      case WatermarkTemplate.bottomBannerBlur: {
        // 周围全幅高斯虚化 + 纯下边框 (图片左右上与卡片齐平，无多余白边)
        final marginX = srcW * 0.07 * spacing;
        final marginY = srcH * 0.07 * spacing;
        final bottomH = srcH * 0.15 * spacing;
        final totalW = srcW + marginX * 2;
        final totalH = srcH + bottomH + marginY * 2;
        return LayoutMetrics(
          totalWidth: totalW,
          totalHeight: totalH,
          imageRect: Rect.fromLTWH(marginX, marginY, srcW, srcH),
        );
      }
      case WatermarkTemplate.topBottomBannerBlur: {
        // 周围全幅高斯虚化 + 上下双边框 (顶部 LIGHT AND SHADOW，底部大师参数)
        final marginX = srcW * 0.07 * spacing;
        final marginY = srcH * 0.07 * spacing;
        final topH = srcH * 0.09 * spacing;
        final bottomH = srcH * 0.15 * spacing;
        final totalW = srcW + marginX * 2;
        final totalH = srcH + topH + bottomH + marginY * 2;
        return LayoutMetrics(
          totalWidth: totalW,
          totalHeight: totalH,
          imageRect: Rect.fromLTWH(marginX, marginY + topH, srcW, srcH),
        );
      }
      case WatermarkTemplate.darkGlassBlur: {
        // 周围暗调虚化 + 悬浮磨砂黑玻质感卡片
        final marginX = srcW * 0.065 * spacing;
        final marginY = srcH * 0.065 * spacing;
        final topH = srcH * 0.05 * spacing;
        final bottomH = srcH * 0.15 * spacing;
        final totalW = srcW + marginX * 2;
        final totalH = srcH + topH + bottomH + marginY * 2;
        return LayoutMetrics(
          totalWidth: totalW,
          totalHeight: totalH,
          imageRect: Rect.fromLTWH(marginX, marginY + topH, srcW, srcH),
        );
      }
      case WatermarkTemplate.polaroidBlur: {
        // 周围全幅高斯虚化 + 浮动复古白卡立体相纸
        final pad = srcW * 0.032 * spacing;
        final marginX = srcW * 0.06 * spacing;
        final marginY = srcH * 0.06 * spacing;
        final bottomH = srcH * 0.16 * spacing;
        final cardW = srcW + pad * 2;
        final cardH = srcH + pad + bottomH;
        final totalW = cardW + marginX * 2;
        final totalH = cardH + marginY * 2;
        return LayoutMetrics(
          totalWidth: totalW,
          totalHeight: totalH,
          imageRect: Rect.fromLTWH(marginX + pad, marginY + pad, srcW, srcH),
        );
      }
      case WatermarkTemplate.flushMasterBar: {
        // 大师画廊 · 纯净直出底栏 (零虚化，满幅照片直接拼接)
        final bottomH = srcH * 0.13 * spacing;
        final totalH = srcH + bottomH;
        return LayoutMetrics(
          totalWidth: srcW,
          totalHeight: totalH,
          imageRect: Rect.fromLTWH(0, 0, srcW, srcH),
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (image != null) {
      _paintFullComposite(canvas, size, image!);
    } else {
      _paintPlaceholderPreview(canvas, size);
    }
  }

  /// 绘制无图时的摄影展签占位画布
  void _paintPlaceholderPreview(Canvas canvas, Size size) {
    final layout = computeLayout(1200, 800, template, spacingScale);
    // contain 适配：按排版比例完整呈现居中，画布外留白保持透明 (所见即所得，不铺任何装饰底)
    final scaleRatio = math.min(size.width / layout.totalWidth, size.height / layout.totalHeight);
    final offsetX = (size.width - layout.totalWidth * scaleRatio) / 2.0;
    final offsetY = (size.height - layout.totalHeight * scaleRatio) / 2.0;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scaleRatio, scaleRatio);

    final fittedCanvasSize = Size(layout.totalWidth, layout.totalHeight);
    _drawTemplateOverlays(canvas, fittedCanvasSize, null, layout.imageRect);
    canvas.restore();
  }

  /// 绘制实际图像与完整水印排版
  void _paintFullComposite(Canvas canvas, Size size, ui.Image img) {
    final layout = computeLayout(img.width.toDouble(), img.height.toDouble(), template, spacingScale);
    // contain 适配：画布与排版比例不一致时整体缩放居中，不裁切、不加装饰底 (所见即所得)
    final scaleRatio = math.min(size.width / layout.totalWidth, size.height / layout.totalHeight);
    final offsetX = (size.width - layout.totalWidth * scaleRatio) / 2.0;
    final offsetY = (size.height - layout.totalHeight * scaleRatio) / 2.0;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scaleRatio, scaleRatio);

    final fittedCanvasSize = Size(layout.totalWidth, layout.totalHeight);
    _drawTemplateOverlays(canvas, fittedCanvasSize, img, layout.imageRect);
    canvas.restore();
  }

  void _drawTemplateOverlays(Canvas canvas, Size size, ui.Image? img, Rect imgRect) {
    switch (template) {
      case WatermarkTemplate.none:
        if (img != null) {
          _drawImageWithFilter(canvas, img, imgRect);
        } else {
          _drawNonePlaceholder(canvas, size);
        }
        break;
      case WatermarkTemplate.inPhotoOverlay:
        _drawInPhotoOverlay(canvas, size, img, imgRect);
        break;
      case WatermarkTemplate.bottomBannerBlur:
        _drawBottomBannerBlur(canvas, size, img, imgRect);
        break;
      case WatermarkTemplate.topBottomBannerBlur:
        _drawTopBottomBannerBlur(canvas, size, img, imgRect);
        break;
      case WatermarkTemplate.darkGlassBlur:
        _drawDarkGlassBlur(canvas, size, img, imgRect);
        break;
      case WatermarkTemplate.polaroidBlur:
        _drawPolaroidBlur(canvas, size, img, imgRect);
        break;
      case WatermarkTemplate.flushMasterBar:
        _drawFlushMasterBar(canvas, size, img, imgRect);
        break;
    }
  }

  /// 绘制带滤镜与 Lightroom 调色参数的位图
  void _drawImageWithFilter(Canvas canvas, ui.Image img, Rect dstRect) {
    final paint = PhotoFilterEngine.createCompositeFilterPaint(
      filterType: filterType,
      filterIntensity: filterIntensity,
      adjustments: adjustments,
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dstRect,
      paint,
    );

    // 绘制暗角
    if (adjustments.vignette.abs() >= 1.0) {
      PhotoFilterEngine.drawVignette(canvas, dstRect, adjustments.vignette);
    }

    // 绘制复古胶片颗粒
    if (adjustments.grain >= 1.0) {
      PhotoFilterEngine.drawGrain(canvas, dstRect, adjustments.grain);
    }
  }

  /// 绘制原图全景高斯虚化背景 (Gaussian Blur Background)
  void _drawGaussianBlurBackground(Canvas canvas, Size size, ui.Image? img, double scale, {double tintOpacity = 0.28}) {
    if (img != null) {
      final bgDst = Rect.fromLTWH(0, 0, size.width, size.height);
      final bgPaint = Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 42.0 * scale,
          sigmaY: 42.0 * scale,
          tileMode: TileMode.clamp,
        );

      final double srcAspect = img.width / img.height;
      final double dstAspect = size.width / size.height;
      Rect bgSrc;
      if (srcAspect > dstAspect) {
        final w = img.height * dstAspect;
        bgSrc = Rect.fromLTWH((img.width - w) / 2, 0, w, img.height.toDouble());
      } else {
        final h = img.width / dstAspect;
        bgSrc = Rect.fromLTWH(0, (img.height - h) / 2, img.width.toDouble(), h);
      }
      canvas.drawImageRect(img, bgSrc, bgDst, bgPaint);

      // 暗调遮罩层，提升悬浮卡片高对比度与空间深度感
      canvas.drawRect(bgDst, Paint()..color = Color.fromRGBO(0, 0, 0, tintOpacity));
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF1E2026));
    }
  }

  /// 绘制悬浮卡片双层多阶真实立体阴影
  void _drawFloatingShadow(Canvas canvas, RRect rrect, double scale, {bool isDark = false}) {
    // 1. 大范围空间漫反射柔和阴影
    canvas.drawRRect(
      rrect.shift(Offset(0, 16 * scale)),
      Paint()
        ..color = isDark ? const Color(0x66000000) : const Color(0x44000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 28 * scale),
    );
    // 2. 近距离实体接触投影 (提升紧致感)
    canvas.drawRRect(
      rrect.shift(Offset(0, 4 * scale)),
      Paint()
        ..color = isDark ? const Color(0x33000000) : const Color(0x22000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * scale),
    );
  }

  /// 照片绘制或占位符
  void _drawPhotoOrPlaceholder(Canvas canvas, ui.Image? img, Rect imgRect, double scale, {RRect? clipRRect}) {
    if (img != null) {
      if (clipRRect != null) {
        canvas.save();
        canvas.clipRRect(clipRRect);
        _drawImageWithFilter(canvas, img, imgRect);
        canvas.restore();
      } else {
        _drawImageWithFilter(canvas, img, imgRect);
      }
    } else {
      final phPaint = Paint()..color = const Color(0xFF1B1D24);
      if (clipRRect != null) {
        canvas.drawRRect(clipRRect, phPaint);
      } else {
        canvas.drawRect(imgRect, phPaint);
      }

      final phText = TextPainter(
        text: TextSpan(
          text: 'P H O T O   P R E V I E W',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 20 * scale,
            fontWeight: FontWeight.bold,
            letterSpacing: 4 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      phText.paint(
        canvas,
        Offset(imgRect.left + (imgRect.width - phText.width) / 2, imgRect.top + (imgRect.height - phText.height) / 2),
      );
    }
  }

  void _drawNonePlaceholder(Canvas canvas, Size size) {
    final scale = size.width / 1200.0;
    final bgPaint = Paint()..color = const Color(0xFF16181D);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final titleP = TextPainter(
      text: TextSpan(
        text: '纯滤镜调色模式 (无水印)',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 22 * scale,
          fontWeight: FontWeight.bold,
          letterSpacing: 2 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, titleP, Offset((size.width - titleP.width) / 2, size.height * 0.45));

    final subP = TextPainter(
      text: TextSpan(
        text: '保持原始画幅比例 · 仅导出胶片色彩 · 零额外水印',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 13 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    subP.paint(canvas, Offset((size.width - subP.width) / 2, size.height * 0.45 + 34 * scale));
  }

  /// 模板: 照片内嵌 · 参数入画 (满幅无边框，机型与曝光参数直接排在照片内部)
  void _drawInPhotoOverlay(Canvas canvas, Size size, ui.Image? img, Rect imgRect) {
    final scale = size.width / 1200.0;

    // 1. 满幅照片 (无边框无虚化)
    _drawPhotoOrPlaceholder(canvas, img, imgRect, scale);

    // 2. 文字配色与投影 (反色投影保证任意照片上可读)
    final baseColor = textDark ? Colors.black : Colors.white;
    final subColor = textDark ? Colors.black.withAlpha(175) : Colors.white.withAlpha(215);
    final shadowColor = textDark ? Colors.white.withAlpha(150) : Colors.black.withAlpha(170);
    final shadows = [
      Shadow(color: shadowColor, offset: Offset(0, 1.5 * scale), blurRadius: 6 * scale),
    ];

    final padX = size.width * 0.045 * spacingScale;
    final padY = size.height * 0.06 * spacingScale;
    final lineGap = 4 * scale;
    final maxTextW = size.width * 0.5;

    // 3. 左下: 机型 (大字) + 镜头 (样式层注入字体，保留 maxWidth 截断)
    final titleP = TextPainter(
      text: TextSpan(
        text: metadata.titleText,
        style: _fontStyle(TextStyle(
          color: baseColor,
          fontSize: 38 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5 * scale,
          shadows: shadows,
        )),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxTextW);

    TextPainter? lensP;
    if (metadata.lensModel.isNotEmpty) {
      lensP = TextPainter(
        text: TextSpan(
          text: metadata.lensModel,
          style: _fontStyle(TextStyle(
            color: subColor,
            fontSize: 17 * scale,
            letterSpacing: 0.3 * scale,
            shadows: shadows,
          )),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxTextW);
    }

    // 4. 右下: 曝光参数 + 拍摄日期
    final expoP = TextPainter(
      text: TextSpan(
        text: metadata.exposureSummary,
        style: _fontStyle(TextStyle(
          color: baseColor,
          fontSize: 21 * scale,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2 * scale,
          shadows: shadows,
        )),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxTextW);

    TextPainter? dateP;
    if (showDetails && metadata.capturedDate.isNotEmpty) {
      final dateStr = metadata.capturedDate.length > 10
          ? metadata.capturedDate.substring(0, 10).replaceAll('-', '.')
          : metadata.capturedDate;
      dateP = TextPainter(
        text: TextSpan(
          text: dateStr,
          style: _fontStyle(TextStyle(
            color: subColor,
            fontSize: 15 * scale,
            letterSpacing: 0.3 * scale,
            shadows: shadows,
          )),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: maxTextW);
    }

    // 5. 底部内侧两列底对齐排布
    final bottomY = size.height - padY;
    final leftBlockH = titleP.height + (lensP != null ? lineGap + lensP.height : 0);
    final rightBlockH = expoP.height + (dateP != null ? lineGap + dateP.height : 0);

    var leftY = bottomY - leftBlockH;
    titleP.paint(canvas, Offset(padX, leftY));
    if (lensP != null) {
      leftY += titleP.height + lineGap;
      lensP.paint(canvas, Offset(padX, leftY));
    }

    var rightY = bottomY - rightBlockH;
    expoP.paint(canvas, Offset(size.width - padX - expoP.width, rightY));
    if (dateP != null) {
      rightY += expoP.height + lineGap;
      dateP.paint(canvas, Offset(size.width - padX - dateP.width, rightY));
    }
  }

  /// 样式层注入所选字体 (null 保持原生)
  TextStyle _fontStyle(TextStyle style) {
    final fam = fontFamily;
    return fam == null ? style : style.copyWith(fontFamily: fam);
  }

  // =========================================================================
  // 模板 1: 高斯虚化 · 纯下边框 (Bottom Banner Blur)
  // 用户强推核心款：图片左右上无多余白边，仅带纯白下边框，周围全幅高斯虚化 + 悬浮阴影
  // 对标实拍设计: media_1791281238085.jpg, media_1791281238135.jpg, media_1791281248682.jpg
  // =========================================================================
  void _drawBottomBannerBlur(Canvas canvas, Size size, ui.Image? img, Rect imgRect) {
    final scale = size.width / 1200.0;
    final cardFill = cardDark ? const Color(0xFF0C0D10) : Colors.white;
    final strongText = textDark ? const Color(0xFF1E1E1E) : Colors.white;
    final mutedText = textDark ? const Color(0xFF757575) : const Color(0xFFB3B3B3);
    final bottomH = imgRect.height * 0.15 * spacingScale;
    final cardRect = Rect.fromLTRB(imgRect.left, imgRect.top, imgRect.right, imgRect.bottom + bottomH);
    final cardRadius = Radius.circular(16 * scale);
    final cardRRect = RRect.fromRectAndRadius(cardRect, cardRadius);

    // 1. 周围全幅原图高斯虚化背景
    _drawGaussianBlurBackground(canvas, size, img, scale, tintOpacity: 0.24);

    // 2. 悬浮立体阴影
    _drawFloatingShadow(canvas, cardRRect, scale, isDark: cardDark);

    // 3. 悬浮卡片底层 (边框颜色黑白可选)
    canvas.drawRRect(cardRRect, Paint()..color = cardFill);

    // 4. 照片绘制 (图片左右上完全贴合卡片，顶部带匹配圆角裁切，底部无缝衔接下边框)
    final photoRRect = RRect.fromRectAndCorners(
      imgRect,
      topLeft: cardRadius,
      topRight: cardRadius,
    );
    _drawPhotoOrPlaceholder(canvas, img, imgRect, scale, clipRRect: photoRRect);

    // 微弱边框，防止纯白天空与白卡融色
    canvas.drawRRect(
      photoRRect,
      Paint()
        ..color = const Color(0x0A000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale,
    );

    // 5. 纯下边框信息区 (尼康金标双行双列精致排版 + 大师参数)
    final paddingX = cardRect.left + 28 * scale;
    final rightMarginX = cardRect.right - 28 * scale;
    final line1Y = imgRect.bottom + bottomH * 0.38;
    final line2Y = imgRect.bottom + bottomH * 0.72;

    // 左侧第一行: 尼康金标亮色方标 + 相机型号
    final badgeW = 34 * scale;
    final badgeH = 20 * scale;
    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(paddingX, line1Y - badgeH * 0.75, badgeW, badgeH),
      Radius.circular(4 * scale),
    );
    canvas.drawRRect(badgeRRect, Paint()..color = const Color(0xFFFFD100));

    final badgeText = TextPainter(
      text: TextSpan(
        text: 'Nikon',
        style: TextStyle(
          color: Colors.black,
          fontSize: 10 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badgeText.paint(
      canvas,
      Offset(
        paddingX + (badgeW - badgeText.width) / 2,
        line1Y - badgeH * 0.75 + (badgeH - badgeText.height) / 2,
      ),
    );

    final modelName = metadata.titleText.replaceAll(RegExp(r'^Nikon\s+', caseSensitive: false), '');
    final titleP = TextPainter(
      text: TextSpan(
        text: modelName.isNotEmpty ? modelName : metadata.titleText,
        style: TextStyle(
          color: strongText,
          fontSize: 24 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, titleP, Offset(paddingX + badgeW + 12 * scale, line1Y - titleP.height * 0.65));

    // 左侧第二行: 镜头型号
    if (metadata.lensModel.isNotEmpty) {
      final lensP = TextPainter(
        text: TextSpan(
          text: metadata.lensModel,
          style: TextStyle(
            color: mutedText,
            fontSize: 14 * scale,
            fontWeight: FontWeight.normal,
            letterSpacing: 0.3 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, lensP, Offset(paddingX, line2Y - lensP.height * 0.5));
    }

    // 右侧第一行: 曝光四要素
    final expoP = TextPainter(
      text: TextSpan(
        text: metadata.exposureSummary,
        style: TextStyle(
          color: strongText,
          fontSize: 20 * scale,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, expoP, Offset(rightMarginX - expoP.width, line1Y - expoP.height * 0.65));

    // 右侧第二行: 拍摄时间
    if (showDetails && metadata.capturedDate.isNotEmpty) {
      final dateText = metadata.capturedDate.length > 10 ? metadata.capturedDate.substring(0, 10).replaceAll('-', '.') : metadata.capturedDate;
      final dateP = TextPainter(
        text: TextSpan(
          text: dateText,
          style: TextStyle(
            color: mutedText,
            fontSize: 14 * scale,
            fontWeight: FontWeight.normal,
            letterSpacing: 0.3 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, dateP, Offset(rightMarginX - dateP.width, line2Y - dateP.height * 0.5));
    }
  }

  // =========================================================================
  // 模板 2: 高斯虚化 · 上下双边框 (Top Bottom Banner Blur)
  // 用户强推核心款：图片带精致上下留白边框，顶部艺术光影标，底部大师参数，周围全幅高斯虚化 + 阴影
  // 对标实拍设计: media_1791281238081.jpg, media_1791281238119.jpg
  // =========================================================================
  void _drawTopBottomBannerBlur(Canvas canvas, Size size, ui.Image? img, Rect imgRect) {
    final scale = size.width / 1200.0;
    final cardFill = cardDark ? const Color(0xFF0C0D10) : const Color(0xFFF5F4F0);
    final strongText = textDark ? const Color(0xFF1E1E1E) : Colors.white;
    final lensText = textDark ? const Color(0xFF757575) : Colors.white.withAlpha(165);
    final expoText = textDark ? const Color(0xFF1E1E1E) : Colors.white.withAlpha(235);
    final dateText = textDark ? const Color(0xFF757575) : Colors.white.withAlpha(140);
    final topLabelText = textDark ? const Color(0xFF555555) : Colors.white.withAlpha(225);
    final topH = imgRect.height * 0.09 * spacingScale;
    final bottomH = imgRect.height * 0.15 * spacingScale;
    final cardRect = Rect.fromLTRB(imgRect.left, imgRect.top - topH, imgRect.right, imgRect.bottom + bottomH);
    final cardRadius = Radius.circular(16 * scale);
    final cardRRect = RRect.fromRectAndRadius(cardRect, cardRadius);

    // 1. 周围全幅高斯虚化背景 (加深遮罩以衬托深邃黑金卡片)
    _drawGaussianBlurBackground(canvas, size, img, scale, tintOpacity: 0.38);

    // 2. 悬浮立体阴影
    _drawFloatingShadow(canvas, cardRRect, scale, isDark: cardDark);

    // 3. 悬浮卡片底板 (边框颜色黑白可选)
    canvas.drawRRect(cardRRect, Paint()..color = cardFill);

    // 4. 顶部艺术微标: "L I G H T   A N D   S H A D O W"
    final topCenterY = cardRect.top + topH / 2.0;
    final topP = TextPainter(
      text: TextSpan(
        text: 'L I G H T   A N D   S H A D O W',
        style: TextStyle(
          color: topLabelText,
          fontSize: 13 * scale,
          letterSpacing: 6.5 * scale,
          fontWeight: FontWeight.w300,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    topP.paint(canvas, Offset(cardRect.left + (cardRect.width - topP.width) / 2, topCenterY - topP.height / 2));

    // 5. 居中照片 (左右与卡片边缘齐平)
    _drawPhotoOrPlaceholder(canvas, img, imgRect, scale);

    // 6. 底部双行双列银白信息排版
    final paddingX = cardRect.left + 28 * scale;
    final rightMarginX = cardRect.right - 28 * scale;
    final line1Y = imgRect.bottom + bottomH * 0.38;
    final line2Y = imgRect.bottom + bottomH * 0.72;

    // 左侧第一行: 相机型号 (高反差加粗)
    final titleP = TextPainter(
      text: TextSpan(
        text: metadata.titleText,
        style: TextStyle(
          color: strongText,
          fontSize: 22 * scale,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, titleP, Offset(paddingX, line1Y - titleP.height * 0.65));

    // 左侧第二行: 镜头型号
    if (metadata.lensModel.isNotEmpty) {
      final lensP = TextPainter(
        text: TextSpan(
          text: metadata.lensModel,
          style: TextStyle(
            color: lensText,
            fontSize: 13 * scale,
            fontWeight: FontWeight.normal,
            letterSpacing: 0.3 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, lensP, Offset(paddingX, line2Y - lensP.height * 0.5));
    }

    // 右侧第一行: 等宽曝光参数
    final expoP = TextPainter(
      text: TextSpan(
        text: metadata.exposureSummary,
        style: TextStyle(
          color: expoText,
          fontSize: 19 * scale,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, expoP, Offset(rightMarginX - expoP.width, line1Y - expoP.height * 0.65));

    // 右侧第二行: 拍摄时间
    if (showDetails && metadata.capturedDate.isNotEmpty) {
      final dateStr = metadata.capturedDate.length > 10 ? metadata.capturedDate.substring(0, 10).replaceAll('-', '.') : metadata.capturedDate;
      final dateP = TextPainter(
        text: TextSpan(
          text: dateStr,
          style: TextStyle(
            color: dateText,
            fontSize: 13 * scale,
            fontWeight: FontWeight.normal,
            letterSpacing: 0.3 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, dateP, Offset(rightMarginX - dateP.width, line2Y - dateP.height * 0.5));
    }
  }

  // =========================================================================
  // 模板 3: 高斯虚化 · 极光暗黑黑玻 (Dark Glass Blur)
  // 周围暗调虚化氛围 · 悬浮磨砂黑玻质感卡片 · 顶部微标与高反差银白参数
  // =========================================================================
  void _drawDarkGlassBlur(Canvas canvas, Size size, ui.Image? img, Rect imgRect) {
    final scale = size.width / 1200.0;
    final cardFill = cardDark ? const Color(0xDE13151B) : const Color(0xFFF2F1ED);
    final cardStroke = cardDark ? const Color(0x28FFFFFF) : const Color(0x22000000);
    final strongText = textDark ? const Color(0xFF1B1D24) : Colors.white;
    final lensText = textDark ? const Color(0xFF757575) : Colors.white.withAlpha(150);
    final expoText = textDark ? const Color(0xFF1E1E1E) : Colors.white.withAlpha(230);
    final dateText = textDark ? const Color(0xFF757575) : Colors.white.withAlpha(130);
    final topH = imgRect.height * 0.05 * spacingScale;
    final bottomH = imgRect.height * 0.15 * spacingScale;
    final cardRect = Rect.fromLTRB(imgRect.left, imgRect.top - topH, imgRect.right, imgRect.bottom + bottomH);
    final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(16 * scale));

    // 1. 周围暗调高斯虚化
    _drawGaussianBlurBackground(canvas, size, img, scale, tintOpacity: 0.45);

    // 2. 悬浮立体阴影
    _drawFloatingShadow(canvas, cardRRect, scale, isDark: cardDark);

    // 3. 悬浮磨砂底板 + 微光高光边框 (边框颜色黑白可选)
    canvas.drawRRect(cardRRect, Paint()..color = cardFill);
    canvas.drawRRect(
      cardRRect,
      Paint()
        ..color = cardStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * scale,
    );

    // 4. 居中照片
    _drawPhotoOrPlaceholder(canvas, img, imgRect, scale);

    // 5. 底部信息排版
    final paddingX = cardRect.left + 26 * scale;
    final rightMarginX = cardRect.right - 26 * scale;
    final line1Y = imgRect.bottom + bottomH * 0.38;
    final line2Y = imgRect.bottom + bottomH * 0.72;

    // 左侧第一行: 尼康金标方标 + 相机型号
    final badgeW = 32 * scale;
    final badgeH = 18 * scale;
    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(paddingX, line1Y - badgeH * 0.75, badgeW, badgeH),
      Radius.circular(3 * scale),
    );
    canvas.drawRRect(badgeRRect, Paint()..color = const Color(0xFFFFD100));

    final badgeText = TextPainter(
      text: TextSpan(
        text: 'Nikon',
        style: TextStyle(
          color: Colors.black,
          fontSize: 9.5 * scale,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badgeText.paint(
      canvas,
      Offset(paddingX + (badgeW - badgeText.width) / 2, line1Y - badgeH * 0.75 + (badgeH - badgeText.height) / 2),
    );

    final modelName = metadata.titleText.replaceAll(RegExp(r'^Nikon\s+', caseSensitive: false), '');
    final titleP = TextPainter(
      text: TextSpan(
        text: modelName.isNotEmpty ? modelName : metadata.titleText,
        style: TextStyle(
          color: strongText,
          fontSize: 22 * scale,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, titleP, Offset(paddingX + badgeW + 10 * scale, line1Y - titleP.height * 0.65));

    // 左侧第二行: 镜头型号
    if (metadata.lensModel.isNotEmpty) {
      final lensP = TextPainter(
        text: TextSpan(
          text: metadata.lensModel,
          style: TextStyle(
            color: lensText,
            fontSize: 13 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, lensP, Offset(paddingX, line2Y - lensP.height * 0.5));
    }

    // 右侧第一行: 曝光参数
    final expoP = TextPainter(
      text: TextSpan(
        text: metadata.exposureSummary,
        style: TextStyle(
          color: expoText,
          fontSize: 19 * scale,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, expoP, Offset(rightMarginX - expoP.width, line1Y - expoP.height * 0.65));

    // 右侧第二行: 拍摄时间
    if (showDetails && metadata.capturedDate.isNotEmpty) {
      final dateStr = metadata.capturedDate.length > 10 ? metadata.capturedDate.substring(0, 10).replaceAll('-', '.') : metadata.capturedDate;
      final dateP = TextPainter(
        text: TextSpan(
          text: dateStr,
          style: TextStyle(
            color: dateText,
            fontSize: 13 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, dateP, Offset(rightMarginX - dateP.width, line2Y - dateP.height * 0.5));
    }
  }

  // =========================================================================
  // 模板 4: 高斯虚化 · 拍立得相纸 (Polaroid Blur)
  // 周围全幅高斯虚化 · 浮动复古白卡立体相纸 · 四周留白与经典宽厚底标
  // =========================================================================
  void _drawPolaroidBlur(Canvas canvas, Size size, ui.Image? img, Rect imgRect) {
    final scale = size.width / 1200.0;
    final cardFill = cardDark ? const Color(0xFF17181C) : const Color(0xFFFAF9F6);
    final strongText = textDark ? const Color(0xFF2B2B2B) : const Color(0xFFF0F0F0);
    final mutedText = textDark ? const Color(0xFF7A7A7A) : const Color(0xFFAAAAAA);
    final expoText = textDark ? const Color(0xFF333333) : const Color(0xFFEDEDED);
    final photoStroke = cardDark ? const Color(0x18FFFFFF) : const Color(0x0F000000);
    final pad = imgRect.width * 0.032 * spacingScale;
    final bottomH = imgRect.height * 0.16 * spacingScale;
    final cardRect = Rect.fromLTRB(imgRect.left - pad, imgRect.top - pad, imgRect.right + pad, imgRect.bottom + bottomH);
    final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(8 * scale));

    // 1. 周围全幅高斯虚化背景
    _drawGaussianBlurBackground(canvas, size, img, scale, tintOpacity: 0.22);

    // 2. 悬浮真实纸质阴影
    _drawFloatingShadow(canvas, cardRRect, scale, isDark: cardDark);

    // 3. 相纸底层 (边框颜色黑白可选)
    canvas.drawRRect(cardRRect, Paint()..color = cardFill);

    // 4. 照片居中放置
    _drawPhotoOrPlaceholder(canvas, img, imgRect, scale);

    // 微弱边框，衬托相纸反差
    canvas.drawRect(
      imgRect,
      Paint()
        ..color = photoStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale,
    );

    // 5. 拍立得宽厚底边信息栏
    final paddingX = cardRect.left + 24 * scale;
    final rightMarginX = cardRect.right - 24 * scale;
    final line1Y = imgRect.bottom + bottomH * 0.40;
    final line2Y = imgRect.bottom + bottomH * 0.72;

    // 左侧第一行: 机型型号
    final titleP = TextPainter(
      text: TextSpan(
        text: metadata.titleText,
        style: TextStyle(
          color: strongText,
          fontSize: 22 * scale,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, titleP, Offset(paddingX, line1Y - titleP.height * 0.65));

    // 左侧第二行: 镜头
    if (metadata.lensModel.isNotEmpty) {
      final lensP = TextPainter(
        text: TextSpan(
          text: metadata.lensModel,
          style: TextStyle(
            color: mutedText,
            fontSize: 13 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, lensP, Offset(paddingX, line2Y - lensP.height * 0.5));
    }

    // 右侧第一行: 曝光参数
    final expoP = TextPainter(
      text: TextSpan(
        text: metadata.exposureSummary,
        style: TextStyle(
          color: expoText,
          fontSize: 18 * scale,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, expoP, Offset(rightMarginX - expoP.width, line1Y - expoP.height * 0.65));

    // 右侧第二行: 时间
    if (showDetails && metadata.capturedDate.isNotEmpty) {
      final dateStr = metadata.capturedDate.length > 10 ? metadata.capturedDate.substring(0, 10).replaceAll('-', '.') : metadata.capturedDate;
      final dateP = TextPainter(
        text: TextSpan(
          text: dateStr,
          style: TextStyle(
            color: mutedText,
            fontSize: 13 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, dateP, Offset(rightMarginX - dateP.width, line2Y - dateP.height * 0.5));
    }
  }

  // =========================================================================
  // 模板 5: 大师画廊 · 纯净直出底栏 (Flush Master Bar)
  // 满幅照片直接拼接 · 无周围虚化背景 · 底部追加德味大师信息条 · 保留照片最大展示面积
  // =========================================================================
  void _drawFlushMasterBar(Canvas canvas, Size size, ui.Image? img, Rect imgRect) {
    final scale = size.width / 1200.0;
    final barFill = cardDark ? const Color(0xFF0E0F12) : Colors.white;
    final strongText = textDark ? const Color(0xFF111111) : Colors.white;
    final divColor = textDark ? const Color(0xFFCCCCCC) : const Color(0xFF444444);
    final lensColor = textDark ? const Color(0xFF666666) : const Color(0xFFAAAAAA);

    // 1. 照片直出满幅填充
    _drawPhotoOrPlaceholder(canvas, img, imgRect, scale);

    // 2. 底部大师底栏 (边框颜色黑白可选)
    final bottomTop = imgRect.bottom;
    final bottomH = size.height - bottomTop;
    final padding = 32 * scale;

    canvas.drawRect(Rect.fromLTWH(0, bottomTop, size.width, bottomH), Paint()..color = barFill);

    final centerY = bottomTop + bottomH / 2.0;

    // 左侧: 经典尼康金标印记圆标 + 机型
    final badgeRadius = 14 * scale;
    final badgePaint = Paint()..color = const Color(0xFFFFD100);
    canvas.drawCircle(Offset(padding + badgeRadius, centerY), badgeRadius, badgePaint);

    final badgeText = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.black, fontSize: 13 * scale, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badgeText.paint(canvas, Offset(padding + badgeRadius - badgeText.width / 2, centerY - badgeText.height / 2));

    final titleP = TextPainter(
      text: TextSpan(
        text: metadata.titleText,
        style: TextStyle(
          color: strongText,
          fontSize: 22 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final titleX = padding + badgeRadius * 2 + 12 * scale;
    _paintText(canvas, titleP, Offset(titleX, centerY - titleP.height / 2));

    // 中间细分割竖线
    final divX = titleX + titleP.width + 24 * scale;
    final divPaint = Paint()
      ..color = divColor
      ..strokeWidth = 1.5 * scale;
    canvas.drawLine(Offset(divX, centerY - 14 * scale), Offset(divX, centerY + 14 * scale), divPaint);

    // 镜头名称
    if (metadata.lensModel.isNotEmpty) {
      final lensP = TextPainter(
        text: TextSpan(
          text: metadata.lensModel,
          style: TextStyle(
            color: lensColor,
            fontSize: 16 * scale,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _paintText(canvas, lensP, Offset(divX + 20 * scale, centerY - lensP.height / 2));
    }

    // 右侧: 等宽曝光参数
    final expoP = TextPainter(
      text: TextSpan(
        text: metadata.exposureSummary,
        style: TextStyle(
          color: strongText,
          fontSize: 20 * scale,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintText(canvas, expoP, Offset(size.width - padding - expoP.width, centerY - expoP.height / 2));
  }

  @override
  bool shouldRepaint(covariant WatermarkCanvasPainter old) {
    return old.image != image ||
           old.metadata != metadata ||
           old.template != template ||
           old.filterType != filterType ||
           old.filterIntensity != filterIntensity ||
           old.adjustments != adjustments ||
           old.spacingScale != spacingScale ||
           old.showDetails != showDetails ||
           old.cardDark != cardDark ||
           old.textDark != textDark ||
           old.fontFamily != fontFamily;
  }

  /// 统一文字绘制出口：用户选择字体时覆盖字体族，null 保持模板原生字体
  void _paintText(Canvas canvas, TextPainter tp, Offset at) {
    final fam = fontFamily;
    final span = tp.text;
    if (fam != null && span is TextSpan) {
      tp.text = TextSpan(
        text: span.text,
        children: span.children,
        style: span.style?.copyWith(fontFamily: fam),
        recognizer: span.recognizer,
      );
      tp.layout();
    }
    tp.paint(canvas, at);
  }
}
