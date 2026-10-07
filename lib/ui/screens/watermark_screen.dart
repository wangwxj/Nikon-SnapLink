import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/utils/exif_helper.dart';
import '../../engine/filter/photo_filter.dart';
import '../../engine/watermark/watermark_painter.dart';
import '../../engine/watermark/watermark_renderer.dart';
import '../../engine/watermark/watermark_template.dart';
import '../../protocol/camera_native_bridge.dart';
import '../widgets/lightroom_histogram.dart';

/// 摄影画廊级水印工坊与胶片调色工作室
class WatermarkScreen extends StatefulWidget {
  final Uint8List? initialImageBytes;
  final PhotoMetadata? initialMetadata;

  const WatermarkScreen({
    super.key,
    this.initialImageBytes,
    this.initialMetadata,
  });

  @override
  State<WatermarkScreen> createState() => WatermarkScreenState();
}

class WatermarkScreenState extends State<WatermarkScreen> with SingleTickerProviderStateMixin {
  // 当前加载的图像与原始字节
  ui.Image? _decodedImage;
  bool _isLoadingImage = false;

  // 状态变量
  WatermarkTemplate _selectedTemplate = WatermarkTemplate.bottomBannerBlur;
  WatermarkTemplate _lastActiveTemplate = WatermarkTemplate.bottomBannerBlur;
  PhotoFilterType _selectedFilter = PhotoFilterType.original;
  double _filterIntensity = 1.0;
  PhotoEditAdjustments _adjustments = const PhotoEditAdjustments();
  int _lightroomGroupIndex = 0;
  HistogramZone? _activeHistogramZone;
  bool _isComparingOriginal = false;
  List<int>? _sampledR;
  List<int>? _sampledG;
  List<int>? _sampledB;
  double _spacingScale = 1.0;
  bool _showDetails = true;

  // 水印精细化：边框颜色 / 字体颜色 (黑白二选一) + 内置字体
  bool _cardDark = false; // false = 白底 (bottomBannerBlur 默认)
  bool _textDark = true; // true = 黑字
  String _fontChoice = 'default';
  bool _isExporting = false;

  /// 当前选择的水印字体族 (null = 各文字保持模板原生字体)
  String? get _watermarkFontFamily {
    switch (_fontChoice) {
      case 'serif':
        return 'serif';
      case 'mono':
        return 'monospace';
      case 'condensed':
        return 'sans-serif-condensed';
      default:
        return null;
    }
  }

  // 拍摄参数元数据 (自动从 EXIF 提取，支持手动微调)
  PhotoMetadata _metadata = const PhotoMetadata(
    cameraMake: 'Nikon',
    cameraModel: 'Z 30',
    lensModel: 'NIKKOR Z 40mm f/2',
    shutterSpeed: '1/250s',
    aperture: 'f/2.0',
    iso: 'ISO 100',
    focalLength: '40mm',
    capturedDate: '2026.10.06 14:32',
  );

  // Tab 控制器 (0: 水印模板, 1: 胶片调色)
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialImageBytes != null) {
      loadImageBytes(widget.initialImageBytes!, widget.initialMetadata);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 公共入口：从外部（如相册大图查看器）传入图片字节与元数据
  Future<void> loadImageBytes(Uint8List bytes, [PhotoMetadata? metadata]) async {
    setState(() => _isLoadingImage = true);
    try {
      final decoded = await WatermarkRenderer.decodeImageFromBytes(bytes);
      PhotoMetadata parsed = await ExifHelper.parseBytes(bytes);
      PhotoMetadata meta;
      if (metadata != null) {
        // 智能融合：优先采用真实 EXIF 解析结果，缺失字段由外部传入的机型或日期补充
        meta = PhotoMetadata(
          cameraMake: parsed.cameraMake.isNotEmpty ? parsed.cameraMake : (metadata.cameraMake.isNotEmpty ? metadata.cameraMake : 'Nikon'),
          cameraModel: parsed.cameraModel.isNotEmpty ? parsed.cameraModel : metadata.cameraModel,
          lensModel: parsed.lensModel.isNotEmpty ? parsed.lensModel : metadata.lensModel,
          shutterSpeed: parsed.shutterSpeed.isNotEmpty ? parsed.shutterSpeed : metadata.shutterSpeed,
          aperture: parsed.aperture.isNotEmpty ? parsed.aperture : metadata.aperture,
          iso: parsed.iso.isNotEmpty ? parsed.iso : metadata.iso,
          focalLength: parsed.focalLength.isNotEmpty ? parsed.focalLength : metadata.focalLength,
          capturedDate: parsed.capturedDate.isNotEmpty ? parsed.capturedDate : metadata.capturedDate,
        );
      } else {
        meta = parsed;
      }

      // 提取微型缩略像素采样用于毫秒级直方图高速演算
      List<int>? rList;
      List<int>? gList;
      List<int>? bList;
      try {
        final byteData = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData != null) {
          final w = decoded.width;
          final h = decoded.height;
          final stepX = math.max(1, w ~/ 48);
          final stepY = math.max(1, h ~/ 48);
          final rBuf = <int>[];
          final gBuf = <int>[];
          final bBuf = <int>[];
          final raw = byteData.buffer.asUint8List();
          for (int y = 0; y < h; y += stepY) {
            for (int x = 0; x < w; x += stepX) {
              final idx = (y * w + x) * 4;
              if (idx + 2 < raw.length) {
                rBuf.add(raw[idx]);
                gBuf.add(raw[idx + 1]);
                bBuf.add(raw[idx + 2]);
              }
            }
          }
          rList = rBuf;
          gList = gBuf;
          bList = bBuf;
        }
      } catch (_) {}

      setState(() {
        _decodedImage = decoded;
        _metadata = meta;
        _sampledR = rList;
        _sampledG = gList;
        _sampledB = bList;
        _isLoadingImage = false;
      });
    } catch (e) {
      setState(() => _isLoadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片解析失败: $e'), backgroundColor: SnapColors.danger),
        );
      }
    }
  }

  /// 供外部 (如相册"去调色"按钮) 直达「直出胶片调色」Tab
  void showFilterTab() {
    if (mounted && _tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  /// 从手机本地相册选择一张图片并自动提取 EXIF
  Future<void> _pickImageFromGallery() async {
    final path = await CameraNativeBridge.pickImageFromGallery();
    if (path == null || path.isEmpty) return;

    final file = File(path);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    await loadImageBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功导入本地照片，已自动提取拍摄参数（${_metadata.titleText}）'),
          backgroundColor: SnapColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 执行高分辨率离线光栅化导出并保存至系统相册
  Future<void> _exportPhoto() async {
    if (_decodedImage == null) {
      // 提示用户导入图片
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先点击右上角相册图标选择照片，或从相机相册导入'),
          backgroundColor: SnapColors.warning,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      // 1. 在后台 PictureRecorder 全物理尺寸光栅化合成
      final result = await WatermarkRenderer.exportWatermarkedPhoto(
        sourceImage: _decodedImage!,
        metadata: _metadata,
        template: _selectedTemplate,
        filterType: _selectedFilter,
        filterIntensity: _filterIntensity,
        adjustments: _adjustments,
        spacingScale: _spacingScale,
        showDetails: _showDetails,
        cardDark: _cardDark,
        textDark: _textDark,
        fontFamily: _watermarkFontFamily,
      );

      // 2. 写入系统公共相册并触发扫描刷新
      await CameraNativeBridge.saveImageToGallery(result.file.path);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: SnapColors.cardElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: SnapColors.success, size: 22),
                SizedBox(width: 8),
                Text('成片已保存到系统相册', style: TextStyle(color: SnapColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('排版风格: ${_selectedTemplate.label}', style: const TextStyle(color: SnapColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text('直出调色: ${_selectedFilter.label} (${(_filterIntensity * 100).round()}%)', style: const TextStyle(color: SnapColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text('输出分辨率: ${result.width} × ${result.height}', style: const TextStyle(color: SnapColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text('文件大小: ${(result.byteLength / 1024 / 1024).toStringAsFixed(2)} MB', style: const TextStyle(color: SnapColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Text(
                    '已保存至系统相册 (Pictures/SnapLink)，可在手机自带相册即刻查看。',
                    style: TextStyle(color: SnapColors.primary, fontSize: 11),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成', style: TextStyle(color: SnapColors.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: SnapColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 弹出 EXIF 参数手动微调抽屉
  void _showMetadataEditSheet() {
    final cameraController = TextEditingController(text: _metadata.cameraModel);
    final lensController = TextEditingController(text: _metadata.lensModel);
    final apertureController = TextEditingController(text: _metadata.aperture);
    final shutterController = TextEditingController(text: _metadata.shutterSpeed);
    final isoController = TextEditingController(text: _metadata.iso);
    final focalController = TextEditingController(text: _metadata.focalLength);
    final dateController = TextEditingController(text: _metadata.capturedDate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SnapColors.cardElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('微调拍摄参数', style: TextStyle(color: SnapColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: SnapColors.textTertiary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Text('对无芯片手动镜头或无 EXIF 照片，可在此自由修改显示参数', style: TextStyle(color: SnapColors.textTertiary, fontSize: 11)),
                const SizedBox(height: 16),
                _buildEditField('相机机型', cameraController, '如 Z 30, Z 8, Z fc'),
                const SizedBox(height: 10),
                _buildEditField('镜头型号', lensController, '如 NIKKOR Z 40mm f/2'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildEditField('光圈值', apertureController, '如 f/1.8')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildEditField('快门速度', shutterController, '如 1/250s')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildEditField('感光度', isoController, '如 ISO 100')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildEditField('焦距', focalController, '如 40mm')),
                  ],
                ),
                const SizedBox(height: 10),
                _buildEditField('拍摄时间', dateController, '如 2026.10.06 14:32'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SnapColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      setState(() {
                        _metadata = _metadata.copyWith(
                          cameraModel: cameraController.text.trim(),
                          lensModel: lensController.text.trim(),
                          aperture: apertureController.text.trim(),
                          shutterSpeed: shutterController.text.trim(),
                          iso: isoController.text.trim(),
                          focalLength: focalController.text.trim(),
                          capturedDate: dateController.text.trim(),
                        );
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('应用参数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: SnapColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(color: SnapColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            filled: true,
            fillColor: SnapColors.card,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: SnapColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: SnapColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: SnapColors.primary)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnapColors.background,
      appBar: AppBar(
        title: const Text('水印工坊 · 直出调色'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '从手机相册选图',
            onPressed: _pickImageFromGallery,
          ),
          IconButton(
            icon: _isExporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: SnapColors.primary))
                : const Icon(Icons.download, color: SnapColors.primary),
            tooltip: '保存高清成片至相册',
            onPressed: _isExporting ? null : _exportPhoto,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 顶部所见即所得 (WYSIWYG) 实时画布预览区
          Expanded(
            flex: 11,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(140),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 自定义画布 (所见即所得：画布严格等于导出成品比例)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        var canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                        if (_decodedImage != null) {
                          final layout = WatermarkCanvasPainter.computeLayout(
                            _decodedImage!.width.toDouble(),
                            _decodedImage!.height.toDouble(),
                            _selectedTemplate,
                            _spacingScale,
                          );
                          final aspect = layout.totalWidth / layout.totalHeight;
                          var w = constraints.maxWidth;
                          var h = w / aspect;
                          if (h > constraints.maxHeight) {
                            h = constraints.maxHeight;
                            w = h * aspect;
                          }
                          canvasSize = Size(w, h);
                        }
                        return Center(
                          child: SizedBox(
                            width: canvasSize.width,
                            height: canvasSize.height,
                            child: CustomPaint(
                              size: canvasSize,
                              painter: WatermarkCanvasPainter(
                                image: _decodedImage,
                                metadata: _metadata,
                                template: _selectedTemplate,
                                filterType: _isComparingOriginal ? PhotoFilterType.original : _selectedFilter,
                                filterIntensity: _isComparingOriginal ? 0.0 : _filterIntensity,
                                adjustments: _isComparingOriginal ? const PhotoEditAdjustments() : _adjustments,
                                spacingScale: _spacingScale,
                                showDetails: _showDetails,
                                cardDark: _cardDark,
                                textDark: _textDark,
                                fontFamily: _watermarkFontFamily,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // 原片与调色长按对比悬浮指示器
                    if (_decodedImage != null && (!_adjustments.isDefault || _selectedFilter != PhotoFilterType.original))
                      Positioned(
                        top: 10,
                        right: 10,
                        child: GestureDetector(
                          onTapDown: (_) => setState(() => _isComparingOriginal = true),
                          onTapUp: (_) => setState(() => _isComparingOriginal = false),
                          onTapCancel: () => setState(() => _isComparingOriginal = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _isComparingOriginal ? SnapColors.primary : Colors.black.withAlpha(160),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _isComparingOriginal ? Colors.transparent : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.compare,
                                  size: 13,
                                  color: _isComparingOriginal ? Colors.black : Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isComparingOriginal ? '显示原片中' : '按住对比原片',
                                  style: TextStyle(
                                    color: _isComparingOriginal ? Colors.black : Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (_isLoadingImage)
                      const Center(child: CircularProgressIndicator(color: SnapColors.primary)),

                    if (_decodedImage == null && !_isLoadingImage)
                      Positioned(
                        bottom: 16,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            backgroundColor: Colors.black54,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.add_photo_alternate, size: 16, color: SnapColors.primary),
                          label: const Text('选择本地照片进行调色加水印', style: TextStyle(fontSize: 12)),
                          onPressed: _pickImageFromGallery,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 2. 拍摄参数 HUD 状态栏与微调入口
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: SnapColors.card,
            child: Row(
              children: [
                const Icon(Icons.camera_alt, size: 15, color: SnapColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_metadata.titleText}  |  ${_metadata.exposureSummary}',
                    style: const TextStyle(color: SnapColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: _showMetadataEditSheet,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 13, color: SnapColors.primary),
                        SizedBox(width: 4),
                        Text('微调参数', style: TextStyle(color: SnapColors.primary, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. 中间功能切换 TabBar ("水印模板" vs "胶片调色")
          Container(
            color: SnapColors.card,
            child: TabBar(
              controller: _tabController,
              indicatorColor: SnapColors.primary,
              indicatorWeight: 2.5,
              labelColor: SnapColors.primary,
              unselectedLabelColor: SnapColors.textTertiary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: '画廊水印模板'),
                Tab(text: '直出胶片调色'),
              ],
            ),
          ),

          // 4. 底部面板内容
          Expanded(
            flex: 8,
            child: TabBarView(
              controller: _tabController,
              children: [
                // 4.1 水印模板面板
                _buildTemplateSelectorPanel(),

                // 4.2 胶片调色面板
                _buildFilterSelectorPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建水印模板选择面板
  Widget _buildTemplateSelectorPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 模板卡片横向滚动
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: WatermarkTemplate.values.length,
            itemBuilder: (context, index) {
              final t = WatermarkTemplate.values[index];
              final isSelected = t == _selectedTemplate;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  onTap: () => setState(() {
                    _selectedTemplate = t;
                    // 切换模板时恢复该模板的默认黑白配色
                    _cardDark = t.defaultCardDark;
                    _textDark = t.defaultTextDark;
                  }),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 135,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? SnapColors.primary.withAlpha(30) : SnapColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? SnapColors.primary : SnapColors.border,
                        width: isSelected ? 1.5 : 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.label,
                          style: TextStyle(
                            color: isSelected ? SnapColors.primary : SnapColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.description,
                          style: const TextStyle(color: SnapColors.textTertiary, fontSize: 9),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        if (_selectedTemplate == WatermarkTemplate.none)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SnapColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SnapColors.primary.withAlpha(60)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: SnapColors.primary, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前处于【纯滤镜调色模式】',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '画面不添加任何边框或水印文字，保持原图全画幅尺寸直出。',
                        style: TextStyle(color: SnapColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: const Text('去调色', style: TextStyle(color: SnapColors.primary, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          )
        else ...[
          // 边距与留白微调
          Row(
            children: [
              const Text('边框缩放比例', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _spacingScale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  activeColor: SnapColors.primary,
                  inactiveColor: SnapColors.border,
                  label: '${(_spacingScale * 100).round()}%',
                  onChanged: (val) => setState(() => _spacingScale = val),
                ),
              ),
              Text('${(_spacingScale * 100).round()}%', style: const TextStyle(color: SnapColors.primary, fontSize: 11, fontFamily: 'monospace')),
            ],
          ),

          // 详细信息开关
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('展示拍摄时间与细节', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
              Switch(
                value: _showDetails,
                activeThumbColor: SnapColors.primary,
                activeTrackColor: SnapColors.primary.withAlpha(120),
                onChanged: (val) => setState(() => _showDetails = val),
              ),
            ],
          ),

          // 字体选择 (系统内置字体族)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('字体', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'default', label: Text('默认')),
                  ButtonSegment(value: 'serif', label: Text('衬线')),
                  ButtonSegment(value: 'mono', label: Text('等宽')),
                  ButtonSegment(value: 'condensed', label: Text('窄体')),
                ],
                selected: {_fontChoice},
                onSelectionChanged: (s) => setState(() => _fontChoice = s.first),
                style: _watermarkSegStyle(),
                showSelectedIcon: false,
              ),
            ],
          ),

          // 边框颜色 (黑白二选一；照片内嵌模板无边框时不显示)
          if (_selectedTemplate != WatermarkTemplate.inPhotoOverlay)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('边框颜色', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: const Text('白'), icon: _colorSwatch(Colors.white)),
                    ButtonSegment(value: true, label: const Text('黑'), icon: _colorSwatch(const Color(0xFF141416))),
                  ],
                  selected: {_cardDark},
                  onSelectionChanged: (s) => setState(() => _cardDark = s.first),
                  style: _watermarkSegStyle(),
                  showSelectedIcon: false,
                ),
              ],
            ),

          // 字体颜色 (黑白二选一)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('字体颜色', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: const Text('白'), icon: _colorSwatch(Colors.white)),
                  ButtonSegment(value: true, label: const Text('黑'), icon: _colorSwatch(const Color(0xFF141416))),
                ],
                selected: {_textDark},
                onSelectionChanged: (s) => setState(() => _textDark = s.first),
                style: _watermarkSegStyle(),
                showSelectedIcon: false,
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 精细化设置用的分段选择器样式 (Material 现成组件，尼康金选中态)
  ButtonStyle _watermarkSegStyle() {
    return ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? SnapColors.primary : SnapColors.card,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.black : Colors.white70,
      ),
      side: WidgetStateProperty.all(const BorderSide(color: SnapColors.border, width: 0.8)),
      textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  /// 黑白色块图标
  Widget _colorSwatch(Color color) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white38, width: 0.8),
      ),
    );
  }

  /// 构建 Lightroom 级专业胶片与参数调色选择面板
  Widget _buildFilterSelectorPanel() {
    final groups = [
      '基础色调',
      '白平衡',
      '偏好质感',
      '颜色分级',
      '胶片预设',
      '镜头与效果',
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 1. 专业直方图组件 (实时 RGB 曲线 + 5 分区指引)
        LightroomHistogramWidget(
          data: HistogramData.compute(
            adjustments: _adjustments,
            filterType: _selectedFilter,
            filterIntensity: _filterIntensity,
            sampledR: _sampledR,
            sampledG: _sampledG,
            sampledB: _sampledB,
          ),
          metadata: _metadata,
          selectedZone: _activeHistogramZone,
          onSelectZone: (zone) {
            setState(() {
              _activeHistogramZone = zone;
              _lightroomGroupIndex = 0; // 基础色调
            });
          },
          onResetAll: () {
            setState(() {
              _adjustments = PhotoEditAdjustments.initial;
              _selectedFilter = PhotoFilterType.original;
              _filterIntensity = 1.0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已重置所有 Lightroom 调色参数与胶片预设'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // 2. 水印开启/关闭与当前模式指示条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: SnapColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SnapColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _selectedTemplate == WatermarkTemplate.none ? Icons.filter_vintage : Icons.branding_watermark,
                    color: _selectedTemplate == WatermarkTemplate.none ? SnapColors.success : SnapColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedTemplate == WatermarkTemplate.none ? '当前模式: 纯调色直出 (无水印)' : '当前水印: ${_selectedTemplate.label}',
                    style: TextStyle(
                      color: _selectedTemplate == WatermarkTemplate.none ? SnapColors.success : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    if (_selectedTemplate == WatermarkTemplate.none) {
                      _selectedTemplate = _lastActiveTemplate;
                    } else {
                      _lastActiveTemplate = _selectedTemplate;
                      _selectedTemplate = WatermarkTemplate.none;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    _selectedTemplate == WatermarkTemplate.none ? '开启水印' : '关闭水印 (仅调色)',
                    style: TextStyle(
                      color: _selectedTemplate == WatermarkTemplate.none ? SnapColors.primary : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 3. 调色分类水平药丸选择器
        SizedBox(
          height: 34,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: groups.length,
            itemBuilder: (context, idx) {
              final isSelected = idx == _lightroomGroupIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _lightroomGroupIndex = idx),
                  borderRadius: BorderRadius.circular(17),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? SnapColors.primary : SnapColors.card,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: isSelected ? SnapColors.primary : SnapColors.border,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      groups[idx],
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        // 4. 当前分类调色控制项
        _buildActiveLightroomGroupContent(),
      ],
    );
  }

  /// 构建当前选中的 Lightroom 分类内容
  Widget _buildActiveLightroomGroupContent() {
    switch (_lightroomGroupIndex) {
      case 0:
        return _buildToneGroup();
      case 1:
        return _buildWhiteBalanceGroup();
      case 2:
        return _buildPresenceGroup();
      case 3:
        return _buildColorGradingGroup();
      case 4:
        return _buildFilmPresetsGroup();
      case 5:
        return _buildLensEffectsGroup();
      default:
        return _buildToneGroup();
    }
  }

  /// 基础色调控制组
  Widget _buildToneGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLightroomSliderItem(
          title: '曝光度',
          code: 'Exposure',
          icon: Icons.wb_sunny_outlined,
          value: _adjustments.exposure,
          hint: '调整画面全局亮度 (-2EV ~ +2EV)',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(exposure: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(exposure: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '对比度',
          code: 'Contrast',
          icon: Icons.contrast,
          value: _adjustments.contrast,
          hint: '增强或降低画面明暗反差',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(contrast: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(contrast: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '高光',
          code: 'Highlights',
          icon: Icons.brightness_high_outlined,
          value: _adjustments.highlights,
          hint: '压暗过曝高光或提升亮部层次',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(highlights: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(highlights: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '阴影',
          code: 'Shadows',
          icon: Icons.brightness_low_outlined,
          value: _adjustments.shadows,
          hint: '提亮暗部死黑或加深暗影深度',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(shadows: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(shadows: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '白色色阶',
          code: 'Whites',
          icon: Icons.crop_square_outlined,
          value: _adjustments.whites,
          hint: '微调高光纯白剪切阈值',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(whites: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(whites: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '黑色色阶',
          code: 'Blacks',
          icon: Icons.square,
          value: _adjustments.blacks,
          hint: '微调暗部纯黑剪切点',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(blacks: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(blacks: 0.0)),
        ),
      ],
    );
  }

  /// 白平衡控制组 (色温 + 色调)
  Widget _buildWhiteBalanceGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLightroomSliderItem(
          title: '色温',
          code: 'Temperature',
          icon: Icons.thermostat_outlined,
          value: _adjustments.temperature,
          hint: '向左偏冷蓝 (冷调天空/雪景)，向右偏暖黄 (日落/人像金黄)',
          trackGradient: const LinearGradient(
            colors: [Color(0xFF29B6F6), Color(0xFFFFB300)],
          ),
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(temperature: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(temperature: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '色调',
          code: 'Tint',
          icon: Icons.palette_outlined,
          value: _adjustments.tint,
          hint: '向左校正偏绿，向右偏洋红品红补偿',
          trackGradient: const LinearGradient(
            colors: [Color(0xFF66BB6A), Color(0xFFEC407A)],
          ),
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(tint: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(tint: 0.0)),
        ),
      ],
    );
  }

  /// 偏好效果控制组 (清晰度 + 纹理 + 去朦胧 + 鲜艳度 + 饱和度)
  Widget _buildPresenceGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLightroomSliderItem(
          title: '清晰度',
          code: 'Clarity',
          icon: Icons.filter_center_focus_outlined,
          value: _adjustments.clarity,
          hint: '调整中间调微反差，强化景物轮廓肌理',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(clarity: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(clarity: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '纹理',
          code: 'Texture',
          icon: Icons.grain,
          value: _adjustments.texture,
          hint: '强化或柔化中高频细节，为人像微磨皮或突出毛发轮廓',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(texture: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(texture: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '去朦胧',
          code: 'Dehaze',
          icon: Icons.blur_off_outlined,
          value: _adjustments.dehaze,
          hint: '消除逆光光雾漫反射，显著增加画面通透感',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(dehaze: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(dehaze: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '鲜艳度',
          code: 'Vibrance',
          icon: Icons.local_florist_outlined,
          value: _adjustments.vibrance,
          hint: '优先提升未饱和低彩度区域，智能保护人像肤色',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(vibrance: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(vibrance: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '饱和度',
          code: 'Saturation',
          icon: Icons.color_lens_outlined,
          value: _adjustments.saturation,
          hint: '全局色彩纯度，降至最低为纯黑白，最高为浓郁艳丽',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(saturation: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(saturation: 0.0)),
        ),
      ],
    );
  }

  /// 颜色分级控制组 (高光色相/饱和度 + 阴影色相/饱和度)
  Widget _buildColorGradingGroup() {
    const rainbowGradient = LinearGradient(
      colors: [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: SnapColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SnapColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.palette_outlined, size: 16, color: SnapColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '色彩分级 (Split Toning)：分别为画面高光亮部与阴影暗部注入特定色调，打造电影感与日式冷暖色彩分离。',
                  style: TextStyle(color: SnapColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        // 高光部分
        _buildLightroomSliderItem(
          title: '高光色相',
          code: 'Highlight Hue',
          icon: Icons.light_mode_outlined,
          value: _adjustments.highlightHue,
          min: 0,
          max: 360,
          unit: '°',
          hint: '高光注入色相 (0°~360°)，暖金色约 35°~45°，青蓝约 195°~210°',
          trackGradient: rainbowGradient,
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(highlightHue: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(highlightHue: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '高光饱和度',
          code: 'Highlight Sat',
          icon: Icons.opacity_outlined,
          value: _adjustments.highlightSat,
          min: 0,
          max: 100,
          unit: '%',
          hint: '高光色调注入浓度 (0%~100%)',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(highlightSat: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(highlightSat: 0.0)),
        ),

        const SizedBox(height: 8),

        // 阴影部分
        _buildLightroomSliderItem(
          title: '阴影色相',
          code: 'Shadow Hue',
          icon: Icons.dark_mode_outlined,
          value: _adjustments.shadowHue,
          min: 0,
          max: 360,
          unit: '°',
          hint: '阴影注入色相 (0°~360°)，冷青蓝约 200°~220°，复古品红约 300°~320°',
          trackGradient: rainbowGradient,
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(shadowHue: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(shadowHue: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '阴影饱和度',
          code: 'Shadow Sat',
          icon: Icons.opacity_outlined,
          value: _adjustments.shadowSat,
          min: 0,
          max: 100,
          unit: '%',
          hint: '阴影色调注入浓度 (0%~100%)',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(shadowSat: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(shadowSat: 0.0)),
        ),
      ],
    );
  }

  /// 胶片预设控制组 (14 款大师级预设 + 浓度 + 一键载入滑块)
  Widget _buildFilmPresetsGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: PhotoFilterType.values.length,
            itemBuilder: (context, index) {
              final filter = PhotoFilterType.values[index];
              final isSelected = filter == _selectedFilter;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  onTap: () => setState(() => _selectedFilter = filter),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 110,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? SnapColors.primary.withAlpha(30) : SnapColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? SnapColors.primary : SnapColors.border,
                        width: isSelected ? 1.5 : 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filter.label,
                          style: TextStyle(
                            color: isSelected ? SnapColors.primary : SnapColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          filter.code,
                          style: const TextStyle(color: SnapColors.textTertiary, fontSize: 9, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: SnapColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SnapColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: SnapColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedFilter.description,
                  style: const TextStyle(color: SnapColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            const Text('胶片预设浓度', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
            Expanded(
              child: Slider(
                value: _filterIntensity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                activeColor: SnapColors.primary,
                inactiveColor: SnapColors.border,
                label: '${(_filterIntensity * 100).round()}%',
                onChanged: _selectedFilter == PhotoFilterType.original
                    ? null
                    : (val) => setState(() => _filterIntensity = val),
              ),
            ),
            Text(
              '${(_filterIntensity * 100).round()}%',
              style: const TextStyle(color: SnapColors.primary, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),

        if (_selectedFilter != PhotoFilterType.original) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _adjustments = _selectedFilter.presetAdjustments;
                _lightroomGroupIndex = 0;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已载入【${_selectedFilter.label}】全套参数至调色滑块，可自由深度微调！'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.tune, size: 16, color: SnapColors.primary),
            label: Text(
              '载入【${_selectedFilter.label}】参数至滑块 (支持深度微调)',
              style: const TextStyle(color: SnapColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: SnapColors.primary, width: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ],
    );
  }

  /// 镜头高级效果控制组 (暗角 + 胶片颗粒)
  Widget _buildLensEffectsGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLightroomSliderItem(
          title: '镜头暗角',
          code: 'Vignette',
          icon: Icons.camera_outlined,
          value: _adjustments.vignette,
          hint: '向右加深电影边缘黑暗角，向左添加高调纯白晕影',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(vignette: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(vignette: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '胶片颗粒',
          code: 'Grain',
          icon: Icons.grain_outlined,
          value: _adjustments.grain,
          hint: '模拟经典银盐胶片细密颗粒噪点，显著增加怀旧与故事感',
          min: 0,
          max: 100,
          unit: '%',
          onChanged: (val) => setState(() => _adjustments = _adjustments.copyWith(grain: val)),
          onReset: () => setState(() => _adjustments = _adjustments.copyWith(grain: 0.0)),
        ),
      ],
    );
  }

  /// 通用专业 Lightroom 调节滑块组件
  Widget _buildLightroomSliderItem({
    required String title,
    required String code,
    required double value,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
    IconData? icon,
    Gradient? trackGradient,
    String hint = '',
    double min = -100,
    double max = 100,
    int? divisions,
    String? unit,
  }) {
    final displayVal = value.round();
    final String valueText;
    if (min >= 0) {
      valueText = '$displayVal${unit ?? ''}';
    } else {
      valueText = displayVal > 0 ? '+$displayVal${unit ?? ''}' : '$displayVal${unit ?? ''}';
    }
    final isModified = value.abs() > 0.5;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SnapColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isModified ? SnapColors.primary.withAlpha(80) : SnapColors.border,
          width: isModified ? 1.0 : 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: isModified ? SnapColors.primary : SnapColors.textTertiary),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: TextStyle(
                  color: isModified ? Colors.white : SnapColors.textSecondary,
                  fontSize: 12,
                  fontWeight: isModified ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                code,
                style: const TextStyle(color: SnapColors.textTertiary, fontSize: 10, fontFamily: 'monospace'),
              ),
              const Spacer(),
              InkWell(
                onTap: onReset,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isModified ? SnapColors.primary.withAlpha(35) : Colors.white.withAlpha(12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    valueText,
                    style: TextStyle(
                      color: isModified ? SnapColors.primary : SnapColors.textSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: const TextStyle(color: SnapColors.textTertiary, fontSize: 10),
            ),
          ],

          const SizedBox(height: 2),

          // 滑块轨道 (支持双色温/双色调渐变色轨)
          Stack(
            alignment: Alignment.center,
            children: [
              if (trackGradient != null)
                Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: trackGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: trackGradient != null ? 3.0 : 4.0,
                  activeTrackColor: trackGradient != null ? Colors.transparent : SnapColors.primary,
                  inactiveTrackColor: trackGradient != null ? Colors.transparent : SnapColors.border,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions ?? ((max - min).round().clamp(10, 360)),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
