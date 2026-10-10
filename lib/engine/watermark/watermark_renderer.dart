import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/exif_helper.dart';
import '../filter/photo_filter.dart';
import '../transfer/export_history_manager.dart';
import 'watermark_painter.dart';
import 'watermark_template.dart';

/// 渲染导出的文件与元数据结果
class ExportResult {
  final File file;
  final int width;
  final int height;
  final int byteLength;

  const ExportResult({
    required this.file,
    required this.width,
    required this.height,
    required this.byteLength,
  });
}

/// 水印与胶片调色高清离线光栅化导出引擎
class WatermarkRenderer {
  WatermarkRenderer._();

  /// 在后台利用 PictureRecorder 离线无损合成高清带水印图片并保存至本地文件
  static Future<ExportResult> exportWatermarkedPhoto({
    required ui.Image sourceImage,
    required PhotoMetadata metadata,
    required WatermarkTemplate template,
    PhotoFilterType filterType = PhotoFilterType.original,
    double filterIntensity = 1.0,
    PhotoEditAdjustments adjustments = const PhotoEditAdjustments(),
    double spacingScale = 1.0,
    bool showDetails = true,
    bool cardDark = false,
    bool textDark = false,
    String? fontFamily,
    int quarterTurns = 0,
    bool mirrorX = false,
  }) async {
    final rotated = quarterTurns % 2 != 0;
    final srcW = rotated ? sourceImage.height.toDouble() : sourceImage.width.toDouble();
    final srcH = rotated ? sourceImage.width.toDouble() : sourceImage.height.toDouble();

    // 1. 精确计算目标排版物理像素总宽高 (含边框与展签留白)
    final layout = WatermarkCanvasPainter.computeLayout(srcW, srcH, template, spacingScale);
    final targetW = layout.totalWidth.round();
    final targetH = layout.totalHeight.round();

    // 2. 离线 Canvas 高保真光栅化记录
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, layout.totalWidth, layout.totalHeight));

    final painter = WatermarkCanvasPainter(
      image: sourceImage,
      metadata: metadata,
      template: template,
      filterType: filterType,
      filterIntensity: filterIntensity,
      adjustments: adjustments,
      spacingScale: spacingScale,
      showDetails: showDetails,
      cardDark: cardDark,
      textDark: textDark,
      fontFamily: fontFamily,
      quarterTurns: quarterTurns,
      mirrorX: mirrorX,
    );

    // 绘制完整合成图
    painter.paint(canvas, Size(layout.totalWidth, layout.totalHeight));

    final picture = recorder.endRecording();
    final renderedImage = await picture.toImage(targetW, targetH);
    
    // 转为 PNG 格式无损字节
    final byteData = await renderedImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('水印图片光栅化编码失败');
    }

    final bytes = byteData.buffer.asUint8List();

    // 3. 写入应用相册缓存目录或 Pictures 目录
    Directory saveDir;
    try {
      final picturesDir = Directory('/storage/emulated/0/Pictures/SnapLink');
      if (await picturesDir.exists() || (await picturesDir.create(recursive: true)).existsSync()) {
        saveDir = picturesDir;
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      saveDir = await getApplicationDocumentsDirectory();
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'SnapLink_${metadata.cameraModel.replaceAll(' ', '_')}_$timestamp.png';
    final outFile = File('${saveDir.path}/$fileName');
    await outFile.writeAsBytes(bytes, flush: true);
    ExportHistoryManager().registerExported(fileName, outFile);

    return ExportResult(
      file: outFile,
      width: targetW,
      height: targetH,
      byteLength: bytes.length,
    );
  }

  /// 辅助方法：从原始字节快速解码 ui.Image
  static Future<ui.Image> decodeImageFromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
}