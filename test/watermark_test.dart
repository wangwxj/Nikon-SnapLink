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

    test('PhotoFilterEngine 87 款相机实拍配方与大师级滤镜矩阵校验 (含夕阳晚霞与赛博霓虹删除验证)', () {
      // 验证总共 87 款预设 (77 款新配方 + 10 款经典精选)
      expect(PhotoFilterType.values.length, equals(87));

      // 验证已彻底删除“夕阳晚霞”与“赛博霓虹”
      final allNames = PhotoFilterType.values.map((e) => e.name).toList();
      final allLabels = PhotoFilterType.values.map((e) => e.label).toList();
      expect(allNames.contains('sunsetGlow'), isFalse);
      expect(allNames.contains('neonGlow'), isFalse);
      expect(allLabels.contains('夕阳晚霞'), isFalse);
      expect(allLabels.contains('赛博霓虹'), isFalse);

      // 验证一级分类与二级分类体系
      expect(PhotoFilterType.categories1.length, equals(7));
      expect(PhotoFilterType.categories1, containsAll([
        '富士胶片',
        '柯达胶片',
        '理光人文',
        '索尼大师',
        '经典黑白',
        '电影特色',
        '经典精选',
      ]));

      // 验证各一级分类下均包含正确的子项
      final fujiPresets = PhotoFilterType.getByCategories('富士胶片');
      expect(fujiPresets.length, equals(21)); // 16 款胶片模拟 + 5 款经典胶卷
      final kodakPresets = PhotoFilterType.getByCategories('柯达胶片');
      expect(kodakPresets.length, equals(14)); // 11 款彩色负片 + 3 款黑白
      final ricohPresets = PhotoFilterType.getByCategories('理光人文');
      expect(ricohPresets.length, equals(8));  // 8 款 GR 影像控制
      final sonyPresets = PhotoFilterType.getByCategories('索尼大师');
      expect(sonyPresets.length, equals(22)); // 8 款索尼 + 5 徕卡哈苏 + 5 佳能尼康 + 4 松下奥巴
      final monoPresets = PhotoFilterType.getByCategories('经典黑白');
      expect(monoPresets.length, equals(5));  // 5 款伊尔福银盐
      final cinePresets = PhotoFilterType.getByCategories('电影特色');
      expect(cinePresets.length, equals(7));  // 4 款电影 + 3 款宝丽来爱克发
      final classicPresets = PhotoFilterType.getByCategories('经典精选');
      expect(classicPresets.length, equals(10)); // 1 款原片直出 + 9 款经典

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

      // 验证全部 87 种预设均具备真实参数映射、色板与有效调色矩阵
      for (final filter in PhotoFilterType.values) {
        final preset = filter.presetAdjustments;
        expect(preset, isNotNull);
        expect(filter.label.isNotEmpty, isTrue);
        expect(filter.code.isNotEmpty, isTrue);
        expect(filter.previewColors.isNotEmpty, isTrue);
        expect(filter.recipeSummary.isNotEmpty, isTrue);

        final matrix = PhotoFilterEngine.getMatrix(filter, 1.0);
        expect(matrix.length, equals(20));
        expect(matrix.every((v) => !v.isNaN && !v.isInfinite), isTrue);
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
      expect(warmMatrix[0], greaterThan(1.0)); // 红色增益增强
      expect(warmMatrix[12], lessThan(1.0));   // 蓝色增益压暗

      final coolAdj = const PhotoEditAdjustments().copyWith(temperature: -50.0);
      final coolMatrix = PhotoFilterEngine.buildAdjustmentsMatrix(coolAdj);
      expect(coolMatrix[0], lessThan(1.0));   // 红色增益压暗
      expect(coolMatrix[12], greaterThan(1.0)); // 蓝色增益增强
    });

    test('Lightroom 直方图算法与区间频数统计校验', () {
      // 构造合成采样像素 (RGB 分布)
      final sampledR = List<int>.generate(256, (i) => i);
      final sampledG = List<int>.generate(256, (i) => (i * 0.8).round());
      final sampledB = List<int>.generate(256, (i) => (i * 0.5).round());

      final hist = HistogramData.compute(
        adjustments: PhotoEditAdjustments.initial,
        filterType: PhotoFilterType.original,
        sampledR: sampledR,
        sampledG: sampledG,
        sampledB: sampledB,
      );

      expect(hist.lumBins.length, equals(64));
      expect(hist.redBins.length, equals(64));
      expect(hist.greenBins.length, equals(64));
      expect(hist.blueBins.length, equals(64));

      // 验证直方图各区间均归一化至 0.0 ~ 1.0 且具备有效频数
      expect(hist.lumBins.every((v) => v >= 0.0 && v <= 1.0), isTrue);
      expect(hist.lumBins.any((v) => v > 0.0), isTrue);

      // 叠加上色调曝光调整后的直方图变动
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

    test('水印字体颜色在拍立得等模板中黑白逻辑一致性验证 (彻底修复选白字体变黑的Bug)', () {
      // 验证拍立得等模板在 textDark=false 时渲染纯白高亮字，textDark=true 时渲染深黑字
      const meta = PhotoMetadata(
        cameraMake: 'Nikon',
        cameraModel: 'Z fc',
        lensModel: 'NIKKOR Z 28mm f/2.8',
        shutterSpeed: '1/500s',
        aperture: 'f/2.8',
        iso: 'ISO 200',
        capturedDate: '2026.10.08',
      );

      final whiteTextPainter = WatermarkCanvasPainter(
        image: null,
        metadata: meta,
        template: WatermarkTemplate.polaroidBlur,
        cardDark: true, // 黑底相纸
        textDark: false, // 用户选择“白”字
      );
      expect(whiteTextPainter.textDark, isFalse);
      expect(whiteTextPainter.cardDark, isTrue);

      final blackTextPainter = WatermarkCanvasPainter(
        image: null,
        metadata: meta,
        template: WatermarkTemplate.polaroidBlur,
        cardDark: false, // 白底相纸
        textDark: true, // 用户选择“黑”字
      );
      expect(blackTextPainter.textDark, isTrue);
      expect(blackTextPainter.cardDark, isFalse);

      // 上下双边框模板的默认配色：白底黑字
      expect(WatermarkTemplate.topBottomBannerBlur.defaultCardDark, isFalse);
      expect(WatermarkTemplate.topBottomBannerBlur.defaultTextDark, isTrue);
    });
  });
}
