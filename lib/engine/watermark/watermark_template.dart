/// 摄影画廊水印模板枚举 (全新精编 7 大高质感模板库 · 彻底去除低质同质化边框)
enum WatermarkTemplate {
  none('none', '纯调色 · 无水印', '保持原图尺寸与比例 · 不加任何边框与文字 · 仅导出直出胶片调色效果', false, false),
  inPhotoOverlay('in_photo', '照片内嵌 · 参数入画', '满幅无边框 · 机型与曝光参数直接排布在照片内部', false, false),
  bottomBannerBlur('bottom_banner_blur', '高斯虚化 · 纯下边框', '朋友圈神图 · 周围全幅高斯虚化 · 悬浮立体阴影卡片 · 仅下边框无多余白边 · 品牌与参数双列精排', false, true),
  topBottomBannerBlur('top_bottom_banner_blur', '高斯虚化 · 上下双边框', '用户力荐款 · 周围全幅高斯虚化 · 悬浮柔和阴影 · 图片带精致上下留白边框 · 顶部光影微标与底部大师参数', true, false),
  darkGlassBlur('dark_glass_blur', '高斯虚化 · 极光暗黑黑玻', '电影级暗房 · 周围暗调虚化氛围 · 悬浮磨砂黑玻质感卡片 · 顶部微标与高反差银白参数', true, false),
  polaroidBlur('polaroid_blur', '高斯虚化 · 拍立得相纸', '周围全幅高斯虚化 · 浮动复古白卡立体相纸 · 四周留白与经典宽厚底标', false, true),
  flushMasterBar('flush_master_bar', '大师画廊 · 纯净直出底栏', '满幅照片直接拼接 · 无周围虚化背景 · 底部追加德味大师信息条 · 保留照片最大展示面积', false, true);

  final String id;
  final String label;
  final String description;

  /// 模板默认边框颜色是否为黑底 (false = 白底)
  final bool defaultCardDark;

  /// 模板默认字体颜色是否为黑字 (false = 白字)
  final bool defaultTextDark;

  const WatermarkTemplate(
    this.id,
    this.label,
    this.description,
    this.defaultCardDark,
    this.defaultTextDark,
  );

  static WatermarkTemplate fromId(String id) {
    if (id == 'blur_card_gallery') return WatermarkTemplate.bottomBannerBlur;
    if (id == 'cinema_black') return WatermarkTemplate.darkGlassBlur;
    if (id == 'classic_white' || id == 'white_card') return WatermarkTemplate.polaroidBlur;
    if (id == 'pro_master_bar' || id == 'exposure_grid' || id == 'immersive_minimal') return WatermarkTemplate.flushMasterBar;

    return WatermarkTemplate.values.firstWhere(
      (e) => e.id == id,
      orElse: () => WatermarkTemplate.bottomBannerBlur,
    );
  }
}
