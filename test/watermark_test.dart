import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/core/utils/exif_helper.dart';
import 'package:snaplink/engine/filter/photo_filter.dart';
import 'package:snaplink/engine/watermark/watermark_painter.dart';
import 'package:snaplink/engine/watermark/watermark_template.dart';
import 'package:snaplink/ui/widgets/lightroom_histogram.dart';

void main() {
  group('Watermark 模板与元数据模型单元测试', () {
    test('6 款全新高质感摄影画廊模板枚举完整性与查找', () {
      expect(WatermarkTemplate.values.length, equals(7));
      expect(WatermarkTemplate.fromId('none'), equals(WatermarkTemplate.none));
      expect(WatermarkTemplate.fromId('in_photo'), equals(WatermarkTemplate.inPhotoOverlay));
      expect(WatermarkTemplate.fromId('bottom_banner_blur'), equals(WatermarkTemplate.bottomBannerBlur));
      expect(WatermarkTemplate.fromId('top_bottom_banner_blur'), equals(WatermarkTemplate.topBottomBannerBlur));
      expect(WatermarkTemplate.fromId('dark_glass_blur'), equals(WatermarkTemplate.darkGlassBlur));
      expect(WatermarkTemplate.fromId('polaroid_blur'), equals(WatermarkTemplate.polaroidBlur));
      expect(WatermarkTemplate.fromId('flush_master_bar'), equals(WatermarkTemplate.flushMasterBar));

      // 验证向后平滑兼容历史 ID
      expect(WatermarkTemplate.fromId('blur_card_gallery'), equals(WatermarkTemplate.bottomBannerBlur));
      expect(WatermarkTemplate.fromId('cinema_black'), equals(WatermarkTemplate.darkGlassBlur));
      expect(WatermarkTemplate.fromId('classic_white'), equals(WatermarkTemplate.polaroidBlur));
      expect(WatermarkTemplate.fromId('white_card'), equals(WatermarkTemplate.polaroidBlur));
      expect(WatermarkTemplate.fromId('pro_master_bar'), equals(WatermarkTemplate.flushMasterBar));
      expect(WatermarkTemplate.fromId('exposure_grid'), equals(WatermarkTemplate.flushMasterBar));
      expect(WatermarkTemplate.fromId('immersive_minimal'), equals(WatermarkTemplate.flushMasterBar));
    });

    test('PhotoMetadata 格式化与标题规范化校验', () {
      const meta = PhotoMetadata(
        cameraMake: 'NIKON CORPORATION',
        cameraModel: 'NIKON Z 8',
        lensModel: 'NIKKOR Z 50mm f/1.2 S',
        shutterSpeed: '1/250s',
        aperture: 'f/1.8',
        iso: 'ISO 100',
        focalLength: '50mm',
        capturedDate: '2026:10:05 14:32:00',
      );

      expect(meta.titleText, equals('NIKON Z 8'));
      expect(meta.exposureSummary, equals('50mm · f/1.8 · 1/250s · ISO 100'));
      expect(meta.hasValidExif, isTrue);
    });

    test('PhotoFilterEngine 14 套大师级滤镜矩阵与线性插值校验', () {
      expect(PhotoFilterType.values.length, equals(14));

      // 原片直出矩阵为单位矩阵
      final originalMatrix = PhotoFilterEngine.getMatrix(PhotoFilterType.original, 1.0);
      expect(originalMatrix.length, equals(20));
      expect(originalMatrix[0], equals(1.0));
      expect(originalMatrix[6], equals(1.0));
      expect(originalMatrix[12], equals(1.0));

      // 经典负片矩阵
      final ccMatrix = PhotoFilterEngine.getMatrix(PhotoFilterType.classicChrome, 1.0);
      expect(ccMatrix.length, equals(20));
      expect(ccMatrix.every((v) => !v.isNaN && !v.isInfinite), isTrue);

      // 新海诚动漫与冷白皮人像
      final shinkaiMatrix = PhotoFilterEngine.getMatrix(PhotoFilterType.shinkaiAnime, 1.0);
      expect(shinkaiMatrix.length, equals(20));
      final portraitMatrix = PhotoFilterEngine.getMatrix(PhotoFilterType.fairSkin, 1.0);
      expect(portraitMatrix.length, equals(20));

      // 验证全部 14 种预设均具备真实参数映射（支持一键载入滑块深度微调）
      for (final filter in PhotoFilterType.values) {
        final preset = filter.presetAdjustments;
        expect(preset, isNotNull);
      }

      // 50% 强度混合插值
      final halfMatrix = PhotoFilterEngine.getMatrix(PhotoFilterType.classicChrome, 0.5);
      expect(halfMatrix.length, equals(20));
      expect(halfMatrix[0], closeTo((1.0 + ccMatrix[0]) / 2.0, 0.01));
    });

    test('PhotoEditAdjustments 与 Lightroom 复合矩阵算法校验 (含纹理、分级、颗粒)', () {
      // 默认初始状态验证
      const adjDefault = PhotoEditAdjustments.initial;
      expect(adjDefault.isDefault, isTrue);

      final identityMatrix = PhotoFilterEngine.buildAdjustmentsMatrix(adjDefault);
      expect(identityMatrix, equals(PhotoFilterEngine.identityMatrix));

      // 曝光、对比度、纹理、高光色相调节矩阵运算
      final adjTone = const PhotoEditAdjustments().copyWith(
        exposure: 20.0,
        contrast: 15.0,
        highlights: -10.0,
        shadows: 15.0,
        texture: 25.0,
        highlightHue: 40.0,
        highlightSat: 30.0,
        shadowHue: 210.0,
        shadowSat: 25.0,
        grain: 20.0,
      );
      expect(adjTone.isDefault, isFalse);

      final toneMatrix = PhotoFilterEngine.buildAdjustmentsMatrix(adjTone);
      expect(toneMatrix.length, equals(20));
      expect(toneMatrix.every((v) => !v.isNaN && !v.isInfinite), isTrue);
      // 曝光提升后斜率与偏移均应大于默认单位矩阵
      expect(toneMatrix[0], greaterThan(1.0));

      // 白平衡色温与色调双向分离校验
      final warmAdj = const PhotoEditAdjustments().copyWith(temperature: 50.0);
      final warmMatrix = PhotoFilterEngine.buildAdjustmentsMatrix(warmAdj);
      // 暖色温提升红通道斜率，压制蓝通道
      expect(warmMatrix[0], greaterThan(warmMatrix[12]));

      final coolAdj = const PhotoEditAdjustments().copyWith(temperature: -50.0);
      final coolMatrix = PhotoFilterEngine.buildAdjustmentsMatrix(coolAdj);
      // 冷色温提升蓝通道斜率，压制红通道
      expect(coolMatrix[12], greaterThan(coolMatrix[0]));

      // 滤镜预设与 Lightroom 参数复合运算
      final compositeMatrix = PhotoFilterEngine.createCompositeMatrix(
        filterType: PhotoFilterType.classicChrome,
        filterIntensity: 0.8,
        adjustments: adjTone,
      );
      expect(compositeMatrix.length, equals(20));
      expect(compositeMatrix.every((v) => !v.isNaN && !v.isInfinite), isTrue);
    });

    test('Lightroom 直方图算法与区间频数统计校验', () {
      // 基础无图摄影分布直方图计算
      final histData = HistogramData.compute(
        adjustments: const PhotoEditAdjustments(),
        filterType: PhotoFilterType.original,
      );

      expect(histData.lumBins.length, equals(64));
      expect(histData.redBins.length, equals(64));
      expect(histData.greenBins.length, equals(64));
      expect(histData.blueBins.length, equals(64));

      // 频数值均在 0.0 ~ 1.0 归一化区间内
      expect(histData.lumBins.every((v) => v >= 0.0 && v <= 1.0), isTrue);

      // 带采样像素的精准实时直方图计算
      final sampledR = [50, 100, 150, 200, 250];
      final sampledG = [60, 110, 160, 210, 240];
      final sampledB = [70, 120, 170, 220, 230];

      final customHist = HistogramData.compute(
        adjustments: const PhotoEditAdjustments().copyWith(exposure: 30.0),
        filterType: PhotoFilterType.shinkaiAnime,
        sampledR: sampledR,
        sampledG: sampledG,
        sampledB: sampledB,
      );

      expect(customHist.lumBins.length, equals(64));
      expect(customHist.redBins.any((v) => v > 0), isTrue);
    });

    test('WatermarkCanvasPainter.computeLayout 动态排版尺寸计算', () {
      const srcW = 6000.0;
      const srcH = 4000.0;

      // 纯调色无水印保持原图尺寸与零边距
      final noneLayout = WatermarkCanvasPainter.computeLayout(srcW, srcH, WatermarkTemplate.none);
      expect(noneLayout.totalWidth, equals(srcW));
      expect(noneLayout.totalHeight, equals(srcH));
      expect(noneLayout.imageRect.left, equals(0));

      // 照片内嵌参数入画：满幅无边框，文字排在照片内部
      final inPhotoLayout = WatermarkCanvasPainter.computeLayout(srcW, srcH, WatermarkTemplate.inPhotoOverlay);
      expect(inPhotoLayout.totalWidth, equals(srcW));
      expect(inPhotoLayout.totalHeight, equals(srcH));
      expect(inPhotoLayout.imageRect.width, equals(srcW));
      expect(inPhotoLayout.imageRect.top, equals(0));

      // 高斯虚化纯下边框 (四周带虚化外框，图片左右与卡片齐平)
      final bottomBannerLayout = WatermarkCanvasPainter.computeLayout(srcW, srcH, WatermarkTemplate.bottomBannerBlur);
      expect(bottomBannerLayout.totalWidth, greaterThan(srcW));
      expect(bottomBannerLayout.totalHeight, greaterThan(srcH));
      expect(bottomBannerLayout.imageRect.left, greaterThan(0));
      expect(bottomBannerLayout.imageRect.width, equals(srcW));

      // 高斯虚化上下双边框 (顶部 LIGHT AND SHADOW，底部大师参数)
      final topBottomLayout = WatermarkCanvasPainter.computeLayout(srcW, srcH, WatermarkTemplate.topBottomBannerBlur);
      expect(topBottomLayout.totalWidth, greaterThan(srcW));
      expect(topBottomLayout.totalHeight, greaterThan(srcH));
      expect(topBottomLayout.imageRect.top, greaterThan(0));

      // 极光暗黑黑玻
      final darkGlassLayout = WatermarkCanvasPainter.computeLayout(srcW, srcH, WatermarkTemplate.darkGlassBlur);
      expect(darkGlassLayout.totalWidth, greaterThan(srcW));
      expect(darkGlassLayout.totalHeight, greaterThan(srcH));

      // 拍立得复古白卡
      final polaroidLayout = WatermarkCanvasPainter.computeLayout(srcW, srcH, WatermarkTemplate.polaroidBlur);
      expect(polaroidLayout.totalWidth, greaterThan(srcW));
      expect(polaroidLayout.totalHeight, greaterThan(srcH));

      // 大师画廊纯净直出底栏 (保持原图宽度，仅底部追加信息条)
      final masterLayout = WatermarkCanvasPainter.computeLayout(srcW, srcH, WatermarkTemplate.flushMasterBar);
      expect(masterLayout.totalWidth, equals(srcW));
      expect(masterLayout.totalHeight, greaterThan(srcH));
      expect(masterLayout.imageRect.left, equals(0));
      expect(masterLayout.imageRect.top, equals(0));
    });
  });
}
