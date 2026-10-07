import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Lightroom 级专业照片调色参数模型 (涵盖 滤镜参数.html 全套调色体系)
class PhotoEditAdjustments {
  // 1. 白平衡 (White Balance)
  final double temperature; // 色温: -100 (冷蓝) ~ +100 (暖黄)
  final double tint;        // 色调: -100 (偏绿) ~ +100 (洋红/品红)

  // 2. 基础色调 (Tone)
  final double exposure;    // 曝光度: -100 ~ +100 (-2EV ~ +2EV)
  final double contrast;    // 对比度: -100 (柔和灰阶) ~ +100 (高反差)
  final double highlights;  // 高光: -100 (压暗高光) ~ +100 (提亮高光)
  final double shadows;     // 阴影: -100 (压暗阴影) ~ +100 (提亮暗部死黑)
  final double whites;      // 白色色阶: -100 ~ +100 (高光白色剪切阈值)
  final double blacks;      // 黑色色阶: -100 ~ +100 (纯黑深度阈值)

  // 3. 偏好与细节质感 (Presence & Details)
  final double texture;     // 纹理: -100 (柔肤柔和) ~ +100 (微观表面肌理强化)
  final double clarity;     // 清晰度: -100 ~ +100 (中间调微反差质感)
  final double dehaze;      // 去朦胧: -100 (朦胧薄雾) ~ +100 (通透除霾)
  final double vibrance;    // 鲜艳度/自然饱和度: -100 ~ +100 (智能保肤色饱和度)
  final double saturation;  // 全局饱和度: -100 (灰度纯黑白) ~ +100 (浓郁纯色)

  // 4. 颜色分级 / 分离色调 (Color Grading / Split Toning)
  final double highlightHue; // 高光色相: 0° ~ 360° (如橙黄 35°~50°)
  final double highlightSat; // 高光饱和度: 0 ~ 100
  final double shadowHue;    // 阴影色相: 0° ~ 360° (如青蓝 200°~230°)
  final double shadowSat;    // 阴影饱和度: 0 ~ 100

  // 5. 镜头与质感效果 (Effects)
  final double vignette;    // 镜头暗角: -100 (高调白角) ~ +100 (经典电影黑暗角)
  final double grain;       // 胶片颗粒: 0 ~ 100 (真实银盐胶片颗粒感)

  const PhotoEditAdjustments({
    this.temperature = 0.0,
    this.tint = 0.0,
    this.exposure = 0.0,
    this.contrast = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.texture = 0.0,
    this.clarity = 0.0,
    this.dehaze = 0.0,
    this.vibrance = 0.0,
    this.saturation = 0.0,
    this.highlightHue = 40.0,
    this.highlightSat = 0.0,
    this.shadowHue = 220.0,
    this.shadowSat = 0.0,
    this.vignette = 0.0,
    this.grain = 0.0,
  });

  /// 是否为完全默认状态 (零调节)
  bool get isDefault =>
      temperature == 0.0 &&
      tint == 0.0 &&
      exposure == 0.0 &&
      contrast == 0.0 &&
      highlights == 0.0 &&
      shadows == 0.0 &&
      whites == 0.0 &&
      blacks == 0.0 &&
      texture == 0.0 &&
      clarity == 0.0 &&
      dehaze == 0.0 &&
      vibrance == 0.0 &&
      saturation == 0.0 &&
      highlightSat == 0.0 &&
      shadowSat == 0.0 &&
      vignette == 0.0 &&
      grain == 0.0;

  PhotoEditAdjustments copyWith({
    double? temperature,
    double? tint,
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? texture,
    double? clarity,
    double? dehaze,
    double? vibrance,
    double? saturation,
    double? highlightHue,
    double? highlightSat,
    double? shadowHue,
    double? shadowSat,
    double? vignette,
    double? grain,
  }) {
    return PhotoEditAdjustments(
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      texture: texture ?? this.texture,
      clarity: clarity ?? this.clarity,
      dehaze: dehaze ?? this.dehaze,
      vibrance: vibrance ?? this.vibrance,
      saturation: saturation ?? this.saturation,
      highlightHue: highlightHue ?? this.highlightHue,
      highlightSat: highlightSat ?? this.highlightSat,
      shadowHue: shadowHue ?? this.shadowHue,
      shadowSat: shadowSat ?? this.shadowSat,
      vignette: vignette ?? this.vignette,
      grain: grain ?? this.grain,
    );
  }

  /// 一键重置为初始状态
  static const PhotoEditAdjustments initial = PhotoEditAdjustments();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoEditAdjustments &&
          runtimeType == other.runtimeType &&
          temperature == other.temperature &&
          tint == other.tint &&
          exposure == other.exposure &&
          contrast == other.contrast &&
          highlights == other.highlights &&
          shadows == other.shadows &&
          whites == other.whites &&
          blacks == other.blacks &&
          texture == other.texture &&
          clarity == other.clarity &&
          dehaze == other.dehaze &&
          vibrance == other.vibrance &&
          saturation == other.saturation &&
          highlightHue == other.highlightHue &&
          highlightSat == other.highlightSat &&
          shadowHue == other.shadowHue &&
          shadowSat == other.shadowSat &&
          vignette == other.vignette &&
          grain == other.grain;

  @override
  int get hashCode => Object.hashAll([
        temperature,
        tint,
        exposure,
        contrast,
        highlights,
        shadows,
        whites,
        blacks,
        texture,
        clarity,
        dehaze,
        vibrance,
        saturation,
        highlightHue,
        highlightSat,
        shadowHue,
        shadowSat,
        vignette,
        grain,
      ]);
}

/// 直出胶片与大师调色预设类型 (对齐 滤镜参数.html 与大师色彩库)
enum PhotoFilterType {
  original('原片直出', 'Original', '相机原生色彩 · 零修饰直出'),
  fairSkin('冷白皮人像', 'Fair Skin', '去黄冷白 · 白里透红 · 柔肤清透高级感'),
  warmPortrait('暖色温馨', 'Warm Gold', '黄金时刻 · 暖高光冷阴影 · 治愈午后日光'),
  sunsetGlow('夕阳晚霞', 'Sunset', '晚霞余晖 · 保云层高光 · 浓郁暖橙与深邃地景'),
  japanesePure('日系街道', 'Japanese', '空气感高明度 · 低反差 · 暗部透气微泛青蓝'),
  shinkaiAnime('新海诚风', 'Shinkai', '梦幻动画感 · 高纯度青蓝晴空与鲜翠草木'),
  cityNight('城市夜景', 'City Night', '冷夜深蓝 · 高反差深邃黑 · 压制霓虹高光'),
  neonGlow('赛博霓虹', 'Neon Cyber', '青品对撞 · 通透街景夜色 · 港风赛博朋克'),
  forestGreen('绿色森林', 'Forest Green', '纯净翠绿 · 去黄透光感 · 去朦胧胶片氛围'),
  floralBotanical('花木生机', 'Botanical', '微距质感 · 自然饱和保花蕊 · 花瓣层次分明'),
  classicChrome('经典负片', 'Classic Chrome', '富士纪实人文 · 低彩度高反差 · 青绿暗调'),
  leicaMonochrome('徕卡黑白', 'Leica Mono', '极致银盐黑白 · 细腻灰阶过渡 · 高宽容度'),
  clearSky('通透蓝天', 'Sky Blue', '风光专属 · 强化晴空纯净天蓝 · 白云立体层次'),
  cinematic('电影质感', 'Cinematic', '大片光影 · 高宽容度叙事 · 青橙对撞暗调');

  final String label;
  final String code;
  final String description;

  const PhotoFilterType(this.label, this.code, this.description);

  PhotoEditAdjustments get presetAdjustments =>
      PhotoFilterEngine.presetAdjustments[this] ?? PhotoEditAdjustments.initial;
}

/// 胶片色彩矩阵与硬件加速图像调色引擎 (深度整合 滤镜参数.html)
class PhotoFilterEngine {
  PhotoFilterEngine._();

  /// 标准单位矩阵 (Identity Matrix)
  static const List<double> identityMatrix = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  /// 专业摄影 4x5 调色矩阵库 (基于 滤镜参数.html 严谨校准)
  static const Map<PhotoFilterType, List<double>> _filterMatrices = {
    PhotoFilterType.original: identityMatrix,

    // ① 冷白皮人像: 去黄 (色温偏冷、红微提、蓝微提、橙黄去黄)、柔光白里透红
    PhotoFilterType.fairSkin: <double>[
      1.08, -0.02, -0.02, 0, 12,
      -0.02, 1.05, -0.01, 0, 6,
      -0.01, -0.01, 1.15, 0, 14,
      0,     0,     0,    1, 0,
    ],

    // ② 暖色温馨人像: 暖高光 (金黄) + 冷阴影 (青蓝)
    PhotoFilterType.warmPortrait: <double>[
      1.18,  0.04, -0.08, 0, 16,
      0.02,  1.08, -0.06, 0, 8,
      -0.10, -0.04, 0.95, 0, -4,
      0,     0,     0,    1, 0,
    ],

    // ③ 夕阳晚霞: 强暖红橙，压高光救天空，阴影提亮，云层金黄
    PhotoFilterType.sunsetGlow: <double>[
      1.32,  0.06, -0.16, 0, 22,
      0.04,  1.12, -0.12, 0, 10,
      -0.18, -0.10, 0.78, 0, -14,
      0,     0,     0,    1, 0,
    ],

    // ④ 日系街道: 高明度、低反差、暗部上提透气去死黑、青蓝空气感
    PhotoFilterType.japanesePure: <double>[
      0.95,  0.04,  0.05, 0, 18,
      0.02,  1.03,  0.04, 0, 18,
      0.04,  0.04,  1.16, 0, 26,
      0,     0,     0,    1, 0,
    ],

    // ⑤ 新海诚风: 青蓝天空、翠绿树木、高纯度通透动漫感、暗部不死黑
    PhotoFilterType.shinkaiAnime: <double>[
      1.14, -0.05, -0.04, 0, 10,
      -0.04, 1.28, -0.06, 0, 14,
      -0.08, 0.05, 1.38,  0, 24,
      0,     0,     0,    1, 0,
    ],

    // ⑥ 城市夜景: 冷夜深蓝基准、高反差深邃黑、压制霓虹死白
    PhotoFilterType.cityNight: <double>[
      1.15, -0.08, -0.08, 0, -8,
      -0.06, 1.10,  0.02, 0, -6,
      -0.12,  0.04, 1.35, 0, 12,
      0,     0,     0,    1, 0,
    ],

    // ⑦ 赛博霓虹: 青蓝底色与洋红品红灯光对撞
    PhotoFilterType.neonGlow: <double>[
      1.25, -0.15,  0.08, 0, 8,
      -0.10, 1.12, -0.08, 0, -4,
      0.08, -0.08, 1.36, 0, 18,
      0,     0,     0,    1, 0,
    ],

    // ⑧ 绿色森林: 纯净翠绿、去黄偏青、叶子发光通透感、去朦胧
    PhotoFilterType.forestGreen: <double>[
      0.98, -0.06, -0.04, 0, 4,
      -0.04, 1.35, -0.06, 0, 18,
      -0.06,  0.06, 1.12, 0, 8,
      0,     0,     0,    1, 0,
    ],

    // ⑨ 花木生机: 自然饱和保护花蕊、微距花瓣层次立体
    PhotoFilterType.floralBotanical: <double>[
      1.12, -0.04, -0.02, 0, 8,
      -0.02, 1.24, -0.04, 0, 12,
      -0.04,  0.02, 1.18, 0, 10,
      0,     0,     0,    1, 0,
    ],

    // ⑩ 经典负片: 富士纪实经典、低饱和、高反差、青绿暗部
    PhotoFilterType.classicChrome: <double>[
      1.08, -0.05, -0.03, 0, -2,
      -0.03, 1.02, -0.02, 0, 1,
      -0.05, -0.02, 1.12, 0, 4,
      0,     0,     0,    1, 0,
    ],

    // ⑪ 徕卡黑白: 经典加权灰阶 + S 型反差强化
    PhotoFilterType.leicaMonochrome: <double>[
      0.35, 0.65, 0.15, 0, -10,
      0.35, 0.65, 0.15, 0, -10,
      0.35, 0.65, 0.15, 0, -10,
      0,    0,    0,    1, 0,
    ],

    // ⑫ 通透蓝天: 强化晴空纯净天蓝
    PhotoFilterType.clearSky: <double>[
      1.02, -0.02, -0.08, 0, 2,
      -0.02, 1.05, -0.04, 0, 4,
      -0.10,  0.08, 1.38, 0, 24,
      0,     0,     0,    1, 0,
    ],

    // ⑬ 电影质感: 好莱坞青橙对撞胶片
    PhotoFilterType.cinematic: <double>[
      1.24, -0.06, -0.12, 0, 6,
      -0.06, 1.08,  0.06, 0, -4,
      -0.14,  0.04, 1.28, 0, 8,
      0,     0,     0,    1, 0,
    ],
  };

  /// 滤镜参数.html 对应的专业参数预设表 (支持一键载入至滑块进行二次微调)
  static final Map<PhotoFilterType, PhotoEditAdjustments> presetAdjustments = {
    PhotoFilterType.original: PhotoEditAdjustments.initial,

    // ① 冷白皮人像
    PhotoFilterType.fairSkin: const PhotoEditAdjustments(
      temperature: -12.0,
      tint: 6.0,
      exposure: 15.0,
      contrast: 8.0,
      highlights: -25.0,
      shadows: 28.0,
      texture: -15.0,
      clarity: -12.0,
      vibrance: 12.0,
      saturation: -5.0,
      highlightHue: 345.0,
      highlightSat: 8.0,
      shadowHue: 215.0,
      shadowSat: 10.0,
    ),

    // ② 暖色温馨人像
    PhotoFilterType.warmPortrait: const PhotoEditAdjustments(
      temperature: 20.0,
      tint: 6.0,
      exposure: 10.0,
      contrast: 5.0,
      highlights: -30.0,
      shadows: 30.0,
      vibrance: 22.0,
      highlightHue: 42.0,
      highlightSat: 25.0,
      shadowHue: 215.0,
      shadowSat: 15.0,
    ),

    // ③ 夕阳晚霞
    PhotoFilterType.sunsetGlow: const PhotoEditAdjustments(
      temperature: 22.0,
      tint: 8.0,
      exposure: 5.0,
      contrast: 10.0,
      highlights: -30.0,
      shadows: 32.0,
      blacks: 8.0,
      dehaze: 10.0,
      vibrance: 15.0,
      saturation: -5.0,
      highlightHue: 42.0,
      highlightSat: 30.0,
      shadowHue: 215.0,
      shadowSat: 18.0,
    ),

    // ④ 日系街道
    PhotoFilterType.japanesePure: const PhotoEditAdjustments(
      temperature: -25.0,
      tint: 4.0,
      exposure: 25.0,
      contrast: -28.0,
      highlights: -40.0,
      shadows: 45.0,
      whites: -15.0,
      blacks: 20.0,
      texture: -10.0,
      clarity: 12.0,
      vibrance: -10.0,
      vignette: 10.0,
      grain: 15.0,
      shadowHue: 220.0,
      shadowSat: 12.0,
    ),

    // ⑤ 新海诚风
    PhotoFilterType.shinkaiAnime: const PhotoEditAdjustments(
      temperature: -35.0,
      tint: 25.0,
      exposure: 15.0,
      contrast: -20.0,
      highlights: -22.0,
      shadows: 50.0,
      clarity: 25.0,
      dehaze: 15.0,
      vibrance: 40.0,
      saturation: 25.0,
      highlightHue: 200.0,
      highlightSat: 15.0,
      shadowHue: 215.0,
      shadowSat: 20.0,
    ),

    // ⑥ 城市夜景
    PhotoFilterType.cityNight: const PhotoEditAdjustments(
      temperature: -20.0,
      tint: 5.0,
      exposure: -5.0,
      contrast: 20.0,
      highlights: -25.0,
      shadows: 15.0,
      whites: 15.0,
      blacks: -12.0,
      clarity: 20.0,
      dehaze: 15.0,
      shadowHue: 220.0,
      shadowSat: 15.0,
    ),

    // ⑦ 赛博霓虹
    PhotoFilterType.neonGlow: const PhotoEditAdjustments(
      temperature: -25.0,
      tint: 18.0,
      exposure: 10.0,
      contrast: 15.0,
      shadows: 45.0,
      clarity: 20.0,
      saturation: 15.0,
      dehaze: 15.0,
      grain: 25.0,
      shadowHue: 210.0,
      shadowSat: 20.0,
      highlightHue: 330.0,
      highlightSat: 20.0,
    ),

    // ⑧ 绿色森林
    PhotoFilterType.forestGreen: const PhotoEditAdjustments(
      temperature: -10.0,
      tint: 15.0,
      exposure: 15.0,
      contrast: 12.0,
      highlights: -35.0,
      shadows: 48.0,
      dehaze: 15.0,
      vibrance: 28.0,
      vignette: 18.0,
      grain: 20.0,
      shadowHue: 175.0,
      shadowSat: 12.0,
    ),

    // ⑨ 花木生机
    PhotoFilterType.floralBotanical: const PhotoEditAdjustments(
      temperature: 10.0,
      tint: 5.0,
      exposure: 15.0,
      contrast: 5.0,
      highlights: -30.0,
      shadows: 45.0,
      clarity: 25.0,
      vibrance: 35.0,
      highlightHue: 45.0,
      highlightSat: 12.0,
    ),

    // ⑩ 经典负片
    PhotoFilterType.classicChrome: const PhotoEditAdjustments(
      temperature: -5.0,
      tint: -6.0,
      exposure: 0.0,
      contrast: 18.0,
      highlights: -15.0,
      shadows: -10.0,
      clarity: 15.0,
      saturation: -18.0,
      grain: 20.0,
      shadowHue: 170.0,
      shadowSat: 10.0,
    ),

    // ⑪ 徕卡黑白
    PhotoFilterType.leicaMonochrome: const PhotoEditAdjustments(
      contrast: 25.0,
      highlights: -20.0,
      shadows: 15.0,
      clarity: 30.0,
      saturation: -100.0,
      grain: 15.0,
    ),

    // ⑫ 通透蓝天
    PhotoFilterType.clearSky: const PhotoEditAdjustments(
      temperature: -15.0,
      tint: 8.0,
      exposure: 10.0,
      contrast: 10.0,
      highlights: -25.0,
      shadows: 20.0,
      dehaze: 20.0,
      vibrance: 25.0,
      saturation: 10.0,
      highlightHue: 205.0,
      highlightSat: 15.0,
    ),

    // ⑬ 电影质感
    PhotoFilterType.cinematic: const PhotoEditAdjustments(
      temperature: -10.0,
      tint: 8.0,
      exposure: 5.0,
      contrast: 22.0,
      highlights: -20.0,
      shadows: 15.0,
      clarity: 18.0,
      vibrance: 12.0,
      vignette: 15.0,
      grain: 18.0,
      highlightHue: 35.0,
      highlightSat: 25.0,
      shadowHue: 215.0,
      shadowSat: 20.0,
    ),
  };

  /// 获取指定预设对应的基础调色模型
  static PhotoEditAdjustments getPresetAdjustments(PhotoFilterType type) {
    return presetAdjustments[type] ?? PhotoEditAdjustments.initial;
  }

  /// 获取指定滤镜在特定强度下的 4x5 混合矩阵
  static List<double> getMatrix(PhotoFilterType type, [double intensity = 1.0]) {
    final clamped = intensity.clamp(0.0, 1.0);
    final target = _filterMatrices[type] ?? identityMatrix;
    if (clamped >= 0.99) return target;
    if (clamped <= 0.01) return identityMatrix;

    final mixed = List<double>.filled(20, 0.0);
    for (int i = 0; i < 20; i++) {
      mixed[i] = identityMatrix[i] + (target[i] - identityMatrix[i]) * clamped;
    }
    return mixed;
  }

  /// 4x5 仿射色彩矩阵数学乘法 (Matrix A * Matrix B)
  static List<double> multiplyMatrices(List<double> a, List<double> b) {
    final result = List<double>.filled(20, 0.0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        result[row * 5 + col] = sum;
      }
      double offsetSum = a[row * 5 + 4];
      for (int k = 0; k < 4; k++) {
        offsetSum += a[row * 5 + k] * b[k * 5 + 4];
      }
      result[row * 5 + 4] = offsetSum;
    }
    return result;
  }

  /// HSV 转换为单位 RGB 分量
  static List<double> _hsvToRgb(double hue, double sat) {
    if (sat <= 0.01) return [0.5, 0.5, 0.5];
    final h = (hue % 360) / 60.0;
    final c = sat;
    final x = c * (1.0 - (h % 2 - 1.0).abs());
    double r = 0, g = 0, b = 0;
    if (h >= 0 && h < 1) {
      r = c; g = x;
    } else if (h >= 1 && h < 2) {
      r = x; g = c;
    } else if (h >= 2 && h < 3) {
      g = c; b = x;
    } else if (h >= 3 && h < 4) {
      g = x; b = c;
    } else if (h >= 4 && h < 5) {
      r = x; b = c;
    } else {
      r = c; b = x;
    }
    final m = 1.0 - c;
    return [r + m * 0.5, g + m * 0.5, b + m * 0.5];
  }

  /// 基于 Adobe Lightroom 核心调色算法计算 4x5 色彩调色矩阵
  static List<double> buildAdjustmentsMatrix(PhotoEditAdjustments adj) {
    if (adj.isDefault) return identityMatrix;

    // 1. 曝光度 (Exposure) 与 高光/阴影/白阶/黑阶 (Tone Balance)
    double expFactor = 1.0;
    if (adj.exposure >= 0) {
      expFactor = 1.0 + (adj.exposure / 100.0) * 1.0;
    } else {
      expFactor = 1.0 + (adj.exposure / 100.0) * 0.75;
    }
    final expOffset = adj.exposure * 0.25;

    // 高光与白色色阶补偿
    final hiGain = 1.0 + (adj.highlights / 100.0) * 0.18;
    final wOffset = (adj.whites / 100.0) * 18.0;

    // 阴影提拉与黑色色阶补偿
    final shOffset = (adj.shadows / 100.0) * 22.0;
    final blOffset = (adj.blacks / 100.0) * 16.0;

    // 2. 对比度 (Contrast) 与 清晰度 (Clarity) 与 纹理 (Texture) 与 去朦胧 (Dehaze)
    final cFactor = 1.0 +
        (adj.contrast / 100.0) * 0.65 +
        (adj.clarity / 100.0) * 0.25 +
        (adj.texture / 100.0) * 0.15 +
        (adj.dehaze / 100.0) * 0.20;
    final cOffset = 128.0 * (1.0 - cFactor);
    final dhCut = -(adj.dehaze / 100.0) * 14.0;

    // 3. 白平衡 (White Balance)
    final tempRScale = 1.0 + (adj.temperature / 100.0) * 0.22;
    final tempBScale = 1.0 - (adj.temperature / 100.0) * 0.22;
    final tempROffset = (adj.temperature / 100.0) * 16.0;
    final tempBOffset = -(adj.temperature / 100.0) * 16.0;

    final tintGScale = 1.0 - (adj.tint / 100.0) * 0.18;
    final tintRBScale = 1.0 + (adj.tint / 100.0) * 0.10;
    final tintGOffset = -(adj.tint / 100.0) * 12.0;
    final tintRBOffset = (adj.tint / 100.0) * 6.0;

    // 4. 颜色分级 / 分离色调 (Color Grading / Split Toning)
    double hiR = 0, hiG = 0, hiB = 0;
    if (adj.highlightSat > 0.01) {
      final rgb = _hsvToRgb(adj.highlightHue, (adj.highlightSat / 100.0).clamp(0.0, 1.0));
      final intensity = (adj.highlightSat / 100.0) * 0.24;
      hiR = (rgb[0] - 0.5) * intensity;
      hiG = (rgb[1] - 0.5) * intensity;
      hiB = (rgb[2] - 0.5) * intensity;
    }

    double shR = 0, shG = 0, shB = 0;
    if (adj.shadowSat > 0.01) {
      final rgb = _hsvToRgb(adj.shadowHue, (adj.shadowSat / 100.0).clamp(0.0, 1.0));
      final intensity = (adj.shadowSat / 100.0) * 16.0;
      shR = (rgb[0] - 0.5) * intensity;
      shG = (rgb[1] - 0.5) * intensity;
      shB = (rgb[2] - 0.5) * intensity;
    }

    // 合成基础色调矩阵
    final rSlope = expFactor * hiGain * cFactor * tempRScale * tintRBScale + hiR;
    final gSlope = expFactor * hiGain * cFactor * tintGScale + hiG;
    final bSlope = expFactor * hiGain * cFactor * tempBScale * tintRBScale + hiB;

    final baseOffset = expOffset + wOffset + shOffset + blOffset + cOffset + dhCut;

    final toneMatrix = <double>[
      rSlope, 0, 0, 0, baseOffset + tempROffset + tintRBOffset + shR,
      0, gSlope, 0, 0, baseOffset + tintGOffset + shG,
      0, 0, bSlope, 0, baseOffset + tempBOffset + tintRBOffset + shB,
      0, 0, 0, 1, 0,
    ];

    // 5. 饱和度 (Saturation) 与 鲜艳度 (Vibrance)
    final totalSat = (1.0 + (adj.saturation / 100.0) + (adj.vibrance / 100.0) * 0.65 + (adj.dehaze / 100.0) * 0.15).clamp(0.0, 3.5);

    const rw = 0.2126;
    const gw = 0.7152;
    const bw = 0.0722;

    final satMatrix = <double>[
      (1 - totalSat) * rw + totalSat, (1 - totalSat) * gw, (1 - totalSat) * bw, 0, 0,
      (1 - totalSat) * rw, (1 - totalSat) * gw + totalSat, (1 - totalSat) * bw, 0, 0,
      (1 - totalSat) * rw, (1 - totalSat) * gw, (1 - totalSat) * bw + totalSat, 0, 0,
      0, 0, 0, 1, 0,
    ];

    return multiplyMatrices(satMatrix, toneMatrix);
  }

  /// 计算胶片预设与 Lightroom 调色参数完美融合的复合 4x5 矩阵
  static List<double> createCompositeMatrix({
    PhotoFilterType filterType = PhotoFilterType.original,
    double filterIntensity = 1.0,
    PhotoEditAdjustments adjustments = const PhotoEditAdjustments(),
  }) {
    final presetMatrix = getMatrix(filterType, filterIntensity);
    if (adjustments.isDefault) {
      return presetMatrix;
    }
    final adjMatrix = buildAdjustmentsMatrix(adjustments);
    if (filterType == PhotoFilterType.original || filterIntensity <= 0.01) {
      return adjMatrix;
    }
    return multiplyMatrices(adjMatrix, presetMatrix);
  }

  /// 构建 Flutter 硬件加速渲染用的 ColorFilter (向后兼容)
  static ColorFilter createColorFilter(PhotoFilterType type, [double intensity = 1.0]) {
    return createCompositeColorFilter(filterType: type, filterIntensity: intensity);
  }

  /// 构建复合调色的硬件加速 ColorFilter
  static ColorFilter createCompositeColorFilter({
    PhotoFilterType filterType = PhotoFilterType.original,
    double filterIntensity = 1.0,
    PhotoEditAdjustments adjustments = const PhotoEditAdjustments(),
  }) {
    if (filterType == PhotoFilterType.original && adjustments.isDefault && filterIntensity <= 0.01) {
      return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
    final matrix = createCompositeMatrix(
      filterType: filterType,
      filterIntensity: filterIntensity,
      adjustments: adjustments,
    );
    return ColorFilter.matrix(matrix);
  }

  /// 构建用于 Canvas 离线绘制的 Paint (向后兼容)
  static Paint createFilterPaint(PhotoFilterType type, [double intensity = 1.0]) {
    return createCompositeFilterPaint(filterType: type, filterIntensity: intensity);
  }

  /// 构建用于 Canvas 离线绘制的高清 Paint
  static Paint createCompositeFilterPaint({
    PhotoFilterType filterType = PhotoFilterType.original,
    double filterIntensity = 1.0,
    PhotoEditAdjustments adjustments = const PhotoEditAdjustments(),
  }) {
    final paint = Paint()..isAntiAlias = true;
    final colorFilter = createCompositeColorFilter(
      filterType: filterType,
      filterIntensity: filterIntensity,
      adjustments: adjustments,
    );
    paint.colorFilter = colorFilter;
    return paint;
  }

  /// 绘制高级镜头暗角 (Vignette)
  static void drawVignette(Canvas canvas, Rect rect, double vignette) {
    if (vignette.abs() < 1.0) return;
    final center = rect.center;
    final maxDim = math.max(rect.width, rect.height);
    final radius = maxDim * 0.72;
    final isDark = vignette > 0;
    final alpha = (vignette.abs() / 100.0 * 200).round().clamp(0, 255);
    final edgeColor = isDark ? Color.fromARGB(alpha, 0, 0, 0) : Color.fromARGB(alpha, 255, 255, 255);

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [Colors.transparent, edgeColor],
        [0.40, 1.0],
      )
      ..blendMode = isDark ? BlendMode.multiply : BlendMode.screen;

    canvas.drawRect(rect, paint);
  }

  /// 绘制复古银盐胶片颗粒 (Grain)
  static void drawGrain(Canvas canvas, Rect rect, double grain) {
    if (grain < 1.0) return;
    final count = (rect.width * rect.height * 0.00045 * (grain / 100.0)).round().clamp(120, 3600);
    final points = <Offset>[];
    final rnd = math.Random(1989);
    for (int i = 0; i < count; i++) {
      points.add(Offset(
        rect.left + rnd.nextDouble() * rect.width,
        rect.top + rnd.nextDouble() * rect.height,
      ));
    }
    final alpha = (grain * 0.38).round().clamp(6, 60);
    final paint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..strokeWidth = 1.1
      ..blendMode = BlendMode.screen;
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  /// 快速矩阵变换 RGB 像素 (用于毫秒级直方图运算)
  static List<int> applyMatrixToRgb(int r, int g, int b, List<double> m) {
    final rNew = (m[0] * r + m[1] * g + m[2] * b + m[4]).round().clamp(0, 255);
    final gNew = (m[5] * r + m[6] * g + m[7] * b + m[9]).round().clamp(0, 255);
    final bNew = (m[10] * r + m[11] * g + m[12] * b + m[14]).round().clamp(0, 255);
    return [rNew, gNew, bNew];
  }
}
