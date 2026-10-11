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
import '../../engine/editor/photo_edit_controller.dart';
import '../../protocol/camera_native_bridge.dart';
import '../../engine/transfer/export_history_manager.dart';
import '../widgets/photo_edit_preview.dart';
import '../widgets/photo_edit_tools.dart';
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

class WatermarkScreenState extends State<WatermarkScreen>
    with SingleTickerProviderStateMixin {
  double _panelHeight(BuildContext context) => math.min(
      MediaQuery.orientationOf(context) == Orientation.landscape
          ? (_tabController.index == 2 ? 204.0 : 200.0)
          : (_tabController.index == 2 ? 268.0 : 320.0),
      MediaQuery.sizeOf(context).height * .44);

  // 当前加载的图像与原始字节
  ui.Image? get _decodedImage => _editController.previewImage;

  // ---- 图像编辑 Tab（编辑结果回灌工作图，与水印/调色共用管线）----
  final PhotoEditController _editController = PhotoEditController();
  PhotoEditTool _editTool = PhotoEditTool.rotate;
  double get _editCropAspect => _editController.value.cropAspect;

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

  // 胶片预设一二级分类状态
  String _selectedCat1 = '富士胶片';
  String? _selectedCat2;

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
    _tabController = TabController(length: 3, vsync: this);
    _editController.addListener(_onEditChanged);
    _tabController.addListener(_onTabChanged);

    if (widget.initialImageBytes != null) {
      loadImageBytes(widget.initialImageBytes!, widget.initialMetadata);
    }
  }

  @override
  void dispose() {
    _editController.removeListener(_onEditChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _editController.dispose();
    super.dispose();
  }

  void _onEditChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChanged() {
    _editController.setCropOverlay(_tabController.index == 2 &&
        (_editTool == PhotoEditTool.crop ||
            _editTool == PhotoEditTool.distort));
    if (mounted) setState(() {});
  }

  /// 公共入口：从外部（如相册大图查看器）传入图片字节与元数据
  Future<void> loadImageBytes(Uint8List bytes,
      [PhotoMetadata? metadata]) async {
    _editController.reset();
    setState(() => _isLoadingImage = true);
    try {
      await _editController.load(bytes);
      if (!mounted) return;
      final decoded = _decodedImage;
      if (decoded == null)
        throw StateError(_editController.renderError ?? '图片解码失败');
      PhotoMetadata parsed = await ExifHelper.parseBytes(bytes);
      PhotoMetadata meta;
      if (metadata != null) {
        // 智能融合：优先采用真实 EXIF 解析结果，缺失字段由外部传入的机型或日期补充
        meta = PhotoMetadata(
          cameraMake: parsed.cameraMake.isNotEmpty
              ? parsed.cameraMake
              : (metadata.cameraMake.isNotEmpty
                  ? metadata.cameraMake
                  : 'Nikon'),
          cameraModel: parsed.cameraModel.isNotEmpty
              ? parsed.cameraModel
              : metadata.cameraModel,
          lensModel: parsed.lensModel.isNotEmpty
              ? parsed.lensModel
              : metadata.lensModel,
          shutterSpeed: parsed.shutterSpeed.isNotEmpty
              ? parsed.shutterSpeed
              : metadata.shutterSpeed,
          aperture:
              parsed.aperture.isNotEmpty ? parsed.aperture : metadata.aperture,
          iso: parsed.iso.isNotEmpty ? parsed.iso : metadata.iso,
          focalLength: parsed.focalLength.isNotEmpty
              ? parsed.focalLength
              : metadata.focalLength,
          capturedDate: parsed.capturedDate.isNotEmpty
              ? parsed.capturedDate
              : metadata.capturedDate,
        );
      } else {
        meta = parsed;
      }

      // 提取微型缩略像素采样用于毫秒级直方图高速演算
      List<int>? rList;
      List<int>? gList;
      List<int>? bList;
      try {
        final byteData =
            await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
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

      if (!mounted) return;
      setState(() {
        _metadata = meta;
        _sampledR = rList;
        _sampledG = gList;
        _sampledB = bList;
        _isLoadingImage = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('图片解析失败: $e'),
              backgroundColor: SnapColors.of(context).danger),
        );
      }
    }
  }

  /// 供外部 (如相册"去调色"按钮) 直达「调色预设」Tab
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
          backgroundColor: SnapColors.of(context).success,
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
        SnackBar(
          content: const Text('请先点击右上角相册图标选择照片，或从相机相册导入'),
          backgroundColor: SnapColors.of(context).warning,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    ui.Image? fullImage;
    try {
      final bytes = await _editController.renderFull();
      fullImage = await WatermarkRenderer.decodeImageFromBytes(bytes);
      // 1. 在后台 PictureRecorder 全物理尺寸光栅化合成
      final result = await WatermarkRenderer.exportWatermarkedPhoto(
        sourceImage: fullImage,
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
      try {
        final name = result.file.uri.pathSegments.last;
        final uri =
            await CameraNativeBridge.saveMediaToGallery(result.file.path, name);
        if (uri == null || uri.isEmpty) throw StateError('保存到系统相册失败');
        ExportHistoryManager().registerExported(name, result.file, uri);
      } finally {
        if (await result.file.exists()) await result.file.delete();
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: SnapColors.of(context).cardElevated,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.check_circle,
                    color: SnapColors.of(context).success, size: 22),
                const SizedBox(width: 8),
                Text('成片已保存到系统相册',
                    style: TextStyle(
                        color: SnapColors.of(context).textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('排版风格: ${_selectedTemplate.label}',
                    style: TextStyle(
                        color: SnapColors.of(context).textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                    '调色预设: ${_selectedFilter.label} (${(_filterIntensity * 100).round()}%)',
                    style: TextStyle(
                        color: SnapColors.of(context).textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text('输出分辨率: ${result.width} × ${result.height}',
                    style: TextStyle(
                        color: SnapColors.of(context).textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                    '文件大小: ${(result.byteLength / 1024 / 1024).toStringAsFixed(2)} MB',
                    style: TextStyle(
                        color: SnapColors.of(context).textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SnapColors.of(context).cardElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SnapColors.of(context).border),
                  ),
                  child: Text(
                    '已保存至系统相册 (Pictures/SnapLink)，可在手机自带相册即刻查看。',
                    style: TextStyle(
                        color: SnapColors.of(context).primary, fontSize: 11),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('完成',
                    style: TextStyle(
                        color: SnapColors.of(context).primary,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('导出失败: $e'),
              backgroundColor: SnapColors.of(context).danger),
        );
      }
    } finally {
      fullImage?.dispose();
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 弹出 EXIF 参数手动微调抽屉
  void _showMetadataEditSheet() {
    final cameraController = TextEditingController(text: _metadata.cameraModel);
    final lensController = TextEditingController(text: _metadata.lensModel);
    final apertureController = TextEditingController(text: _metadata.aperture);
    final shutterController =
        TextEditingController(text: _metadata.shutterSpeed);
    final isoController = TextEditingController(text: _metadata.iso);
    final focalController = TextEditingController(text: _metadata.focalLength);
    final dateController = TextEditingController(text: _metadata.capturedDate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SnapColors.of(context).cardElevated,
      shape: const RoundedRectangleBorder(
          borderRadius:
              const BorderRadius.vertical(top: const Radius.circular(20))),
      builder: (ctx) {
        final context = ctx;
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
                    Text('微调拍摄参数',
                        style: TextStyle(
                            color: SnapColors.of(context).textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: SnapColors.of(context).textTertiary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text('对无芯片手动镜头或无 EXIF 照片，可在此自由修改显示参数',
                    style: TextStyle(
                        color: SnapColors.of(context).textTertiary,
                        fontSize: 11)),
                const SizedBox(height: 16),
                _buildEditField('相机机型', cameraController, '如 Z 30, Z 8, Z fc'),
                const SizedBox(height: 10),
                _buildEditField('镜头型号', lensController, '如 NIKKOR Z 40mm f/2'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _buildEditField(
                            '光圈值', apertureController, '如 f/1.8')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildEditField(
                            '快门速度', shutterController, '如 1/250s')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child:
                            _buildEditField('感光度', isoController, '如 ISO 100')),
                    const SizedBox(width: 10),
                    Expanded(
                        child:
                            _buildEditField('焦距', focalController, '如 40mm')),
                  ],
                ),
                const SizedBox(height: 10),
                _buildEditField('拍摄时间', dateController, '如 2026.10.06 14:32'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SnapColors.of(context).primary,
                      foregroundColor: SnapColors.of(context).textInverse,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
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
                    child: const Text('应用参数',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditField(
      String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: SnapColors.of(context).textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(
              color: SnapColors.of(context).textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: SnapColors.of(context).textTertiary, fontSize: 12),
            filled: true,
            fillColor: SnapColors.of(context).card,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: SnapColors.of(context).border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: SnapColors.of(context).border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: SnapColors.of(context).primary)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnapColors.of(context).background,
      appBar: AppBar(
        title: const Text('水印工坊 · 调色预设'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '从手机相册选图',
            onPressed: _pickImageFromGallery,
          ),
          IconButton(
            icon: _isExporting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SnapColors.of(context).primary))
                : Icon(Icons.download, color: SnapColors.of(context).primary),
            tooltip: '保存高清成片至相册',
            onPressed: _isExporting ? null : _exportPhoto,
          ),
        ],
      ),
      body: AbsorbPointer(
          absorbing: _isExporting,
          child: Column(
            children: [
              // 1. 顶部所见即所得 (WYSIWYG) 实时画布预览区
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 自定义画布 (所见即所得：画布严格等于导出成品比例)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (_tabController.index == 2) {
                              return PhotoEditPreview(
                                  controller: _editController,
                                  activeTool: _editTool,
                                  cropAspect: _editCropAspect);
                            }
                            var canvasSize = Size(
                                constraints.maxWidth, constraints.maxHeight);
                            if (_decodedImage != null) {
                              final srcW = _decodedImage!.width.toDouble();
                              final srcH = _decodedImage!.height.toDouble();
                              final layout =
                                  WatermarkCanvasPainter.computeLayout(
                                srcW,
                                srcH,
                                _selectedTemplate,
                                _spacingScale,
                              );
                              final aspect =
                                  layout.totalWidth / layout.totalHeight;
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
                                    filterType: _isComparingOriginal
                                        ? PhotoFilterType.original
                                        : _selectedFilter,
                                    filterIntensity: _isComparingOriginal
                                        ? 0.0
                                        : _filterIntensity,
                                    adjustments: _isComparingOriginal
                                        ? const PhotoEditAdjustments()
                                        : _adjustments,
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
                        if (_decodedImage != null &&
                            (!_adjustments.isDefault ||
                                _selectedFilter != PhotoFilterType.original))
                          Positioned(
                            top: 10,
                            right: 10,
                            child: GestureDetector(
                              onTapDown: (_) =>
                                  setState(() => _isComparingOriginal = true),
                              onTapUp: (_) =>
                                  setState(() => _isComparingOriginal = false),
                              onTapCancel: () =>
                                  setState(() => _isComparingOriginal = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _isComparingOriginal
                                      ? SnapColors.of(context).primary
                                      : SnapColors.of(context)
                                          .card
                                          .withAlpha(230),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _isComparingOriginal
                                        ? Colors.transparent
                                        : SnapColors.of(context).textSecondary,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.compare,
                                      size: 13,
                                      color: _isComparingOriginal
                                          ? SnapColors.of(context).textInverse
                                          : SnapColors.of(context).textPrimary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isComparingOriginal ? '显示原片中' : '按住对比原片',
                                      style: TextStyle(
                                        color: _isComparingOriginal
                                            ? SnapColors.of(context).textInverse
                                            : SnapColors.of(context)
                                                .textPrimary,
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
                          Center(
                              child: CircularProgressIndicator(
                                  color: SnapColors.of(context).primary)),

                        if (_decodedImage == null && !_isLoadingImage)
                          Positioned(
                            bottom: 16,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    SnapColors.of(context).textSecondary,
                                side: BorderSide(
                                    color:
                                        SnapColors.of(context).textSecondary),
                                backgroundColor: SnapColors.of(context).surface,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                              ),
                              icon: Icon(Icons.add_photo_alternate,
                                  size: 16,
                                  color: SnapColors.of(context).primary),
                              label: const Text('选择本地照片进行调色加水印',
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: _pickImageFromGallery,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. 拍摄参数 HUD 状态栏与微调入口
              if (_tabController.index != 2)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: SnapColors.of(context).card,
                  child: Row(
                    children: [
                      Icon(Icons.camera_alt,
                          size: 15, color: SnapColors.of(context).primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_metadata.titleText}  |  ${_metadata.exposureSummary}',
                          style: TextStyle(
                              color: SnapColors.of(context).textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: _showMetadataEditSheet,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit,
                                  size: 13,
                                  color: SnapColors.of(context).primary),
                              const SizedBox(width: 4),
                              Text('微调参数',
                                  style: TextStyle(
                                      color: SnapColors.of(context).primary,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 3. 中间功能切换 TabBar ("水印模板" vs "胶片调色")
              Container(
                color: SnapColors.of(context).card,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: SnapColors.of(context).primary,
                  indicatorWeight: 2.5,
                  labelColor: SnapColors.of(context).primary,
                  unselectedLabelColor: SnapColors.of(context).textTertiary,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: [
                    const Tab(text: '添加水印'),
                    const Tab(text: '调色预设'),
                    const Tab(text: '图像编辑'),
                  ],
                ),
              ),

              // 4. 底部面板内容
              SizedBox(
                height: _panelHeight(context),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 4.1 水印模板面板
                    _buildTemplateSelectorPanel(),

                    // 4.2 胶片调色面板
                    _buildFilterSelectorPanel(),

                    // 4.3 图像编辑面板
                    _buildEditPanel(),
                  ],
                ),
              ),
            ],
          )),
    );
  }

  /// 构建水印模板排版结构线框缩略示意
  Widget _buildTemplateSchematic(WatermarkTemplate t, bool isSelected) {
    final accent = isSelected
        ? SnapColors.of(context).primary
        : SnapColors.of(context).textTertiary;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        // 固定深底：线框代表模板真实配色，跟随主题会让浅色模式黑白反转糊成一团
        color: const Color(0xFF222228),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected
              ? SnapColors.of(context).primary.withAlpha(140)
              : SnapColors.of(context).border,
          width: 0.8,
        ),
      ),
      child: Center(
        child: _getTemplateWireframe(t, accent),
      ),
    );
  }

  Widget _getTemplateWireframe(WatermarkTemplate t, Color accent) {
    switch (t) {
      case WatermarkTemplate.none:
        return Icon(Icons.crop_free, size: 20, color: accent);
      case WatermarkTemplate.inPhotoOverlay:
        return Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF232733),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(width: 7, height: 2, color: accent),
                    Container(
                        width: 9, height: 2, color: accent.withAlpha(180)),
                  ],
                ),
              ),
            ],
          ),
        );
      case WatermarkTemplate.bottomBannerBlur:
        return Container(
          margin: const EdgeInsets.all(2),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: const Color(0xFF282D3C),
                    borderRadius: const BorderRadius.vertical(
                        top: const Radius.circular(2)),
                  ),
                ),
              ),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                      bottom: const Radius.circular(2)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Container(
                        width: 3, height: 3, color: const Color(0xFFFFD100)),
                    const SizedBox(width: 2),
                    Container(width: 8, height: 2, color: Colors.black),
                  ],
                ),
              ),
            ],
          ),
        );
      case WatermarkTemplate.topBottomBannerBlur:
        return Container(
          margin: const EdgeInsets.all(2),
          child: Column(
            children: [
              Container(height: 5, color: Colors.white),
              Expanded(child: Container(color: const Color(0xFF282D3C))),
              Container(
                height: 7,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Container(width: 8, height: 2, color: Colors.black),
                  ],
                ),
              ),
            ],
          ),
        );
      case WatermarkTemplate.darkGlassBlur:
        return Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1E28),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
                color: SnapColors.of(context).textSecondary, width: 0.6),
          ),
          child: Column(
            children: [
              Expanded(child: Container(color: const Color(0xFF12141C))),
              Container(
                height: 7,
                color: const Color(0xDE13151B),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Container(
                        width: 3, height: 3, color: const Color(0xFFFFD100)),
                    const SizedBox(width: 2),
                    Container(
                        width: 7,
                        height: 1.5,
                        color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        );
      case WatermarkTemplate.polaroidBlur:
        return Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF9F6),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Container(color: const Color(0xFF2C303E)),
        );
      case WatermarkTemplate.flushMasterBar:
        return Container(
          margin: const EdgeInsets.all(2),
          child: Column(
            children: [
              Expanded(child: Container(color: const Color(0xFF282D3C))),
              Container(
                height: 8,
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: const Color(0xFFFFD100),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Container(
                        width: 8,
                        height: 2,
                        color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  /// 构建单个水印模板卡片
  Widget _buildTemplateCard(WatermarkTemplate t) {
    final isSelected = t == _selectedTemplate;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          _selectedTemplate = t;
          _cardDark = t.defaultCardDark;
          _textDark = t.defaultTextDark;
        }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? SnapColors.of(context).primary.withAlpha(30)
                : SnapColors.of(context).card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? SnapColors.of(context).primary
                  : SnapColors.of(context).border,
              width: isSelected ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            children: [
              _buildTemplateSchematic(t, isSelected),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.label,
                            style: TextStyle(
                              color: isSelected
                                  ? SnapColors.of(context).primary
                                  : SnapColors.of(context).textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle,
                              size: 13, color: SnapColors.of(context).primary),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.description,
                      style: TextStyle(
                          color: SnapColors.of(context).textTertiary,
                          fontSize: 9),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建水印模板选择面板 (视觉网格化排版卡片 + 结构缩略图)
  /// 图像编辑面板：变换工具 + 参数 + 预览，复用共享组件。
  Widget _buildEditPanel() => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(
              tooltip: '撤销',
              onPressed: _editController.canUndo ? _editController.undo : null,
              icon: const Icon(Icons.undo)),
          IconButton(
              tooltip: '重做',
              onPressed: _editController.canRedo ? _editController.redo : null,
              icon: const Icon(Icons.redo)),
          TextButton(
              onPressed: _editController.isDirty ? _editController.reset : null,
              child: const Text('重置')),
        ]),
        Expanded(
            child: PhotoEditToolsPanel(
          controller: _editController,
          activeTool: _editTool,
          onToolChanged: (tool) {
            setState(() => _editTool = tool);
            _onTabChanged();
          },
          cropAspect: _editCropAspect,
          onCropAspectSelected: (aspect) =>
              applyCropAspect(_editController, aspect),
        )),
      ]);

  Widget _buildTemplateSelectorPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 模板双列视觉网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: WatermarkTemplate.values.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.1,
          ),
          itemBuilder: (context, index) {
            final t = WatermarkTemplate.values[index];
            return _buildTemplateCard(t);
          },
        ),

        const SizedBox(height: 14),

        if (_selectedTemplate == WatermarkTemplate.none)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SnapColors.of(context).primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: SnapColors.of(context).primary.withAlpha(60)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: SnapColors.of(context).primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前处于【纯滤镜调色模式】',
                        style: TextStyle(
                            color: SnapColors.of(context).textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '画面不添加任何边框或水印文字，保持原图全画幅尺寸直出。',
                        style: TextStyle(
                            color: SnapColors.of(context).textSecondary,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: Text('去调色',
                      style: TextStyle(
                          color: SnapColors.of(context).primary,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          )
        else ...[
          // 边距与留白微调
          Row(
            children: [
              Text('边框缩放比例',
                  style: TextStyle(
                      color: SnapColors.of(context).textSecondary,
                      fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _spacingScale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  activeColor: SnapColors.of(context).primary,
                  inactiveColor: SnapColors.of(context).border,
                  label: '${(_spacingScale * 100).round()}%',
                  onChanged: (val) => setState(() => _spacingScale = val),
                ),
              ),
              Text('${(_spacingScale * 100).round()}%',
                  style: TextStyle(
                      color: SnapColors.of(context).primary,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ],
          ),

          // 详细信息开关
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('展示拍摄时间与细节',
                  style: TextStyle(
                      color: SnapColors.of(context).textSecondary,
                      fontSize: 12)),
              Switch(
                value: _showDetails,
                activeThumbColor: SnapColors.of(context).primary,
                activeTrackColor: SnapColors.of(context).primary.withAlpha(120),
                onChanged: (val) => setState(() => _showDetails = val),
              ),
            ],
          ),

          // 字体选择 (系统内置字体族)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('字体',
                  style: TextStyle(
                      color: SnapColors.of(context).textSecondary,
                      fontSize: 12)),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(
                      value: 'default', label: const Text('默认')),
                  const ButtonSegment(value: 'serif', label: const Text('衬线')),
                  const ButtonSegment(value: 'mono', label: const Text('等宽')),
                  const ButtonSegment(
                      value: 'condensed', label: const Text('窄体')),
                ],
                selected: {_fontChoice},
                onSelectionChanged: (s) =>
                    setState(() => _fontChoice = s.first),
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
                Text('边框颜色',
                    style: TextStyle(
                        color: SnapColors.of(context).textSecondary,
                        fontSize: 12)),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                        value: false,
                        label: const Text('白'),
                        icon: _colorSwatch(SnapColors.of(context).textPrimary)),
                    ButtonSegment(
                        value: true,
                        label: const Text('黑'),
                        icon: _colorSwatch(const Color(0xFF141416))),
                  ],
                  selected: {_cardDark},
                  onSelectionChanged: (s) =>
                      setState(() => _cardDark = s.first),
                  style: _watermarkSegStyle(),
                  showSelectedIcon: false,
                ),
              ],
            ),

          // 字体颜色 (黑白二选一)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('字体颜色',
                  style: TextStyle(
                      color: SnapColors.of(context).textSecondary,
                      fontSize: 12)),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: false,
                      label: const Text('白'),
                      icon: _colorSwatch(SnapColors.of(context).textPrimary)),
                  ButtonSegment(
                      value: true,
                      label: const Text('黑'),
                      icon: _colorSwatch(const Color(0xFF141416))),
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
        (states) => states.contains(WidgetState.selected)
            ? SnapColors.of(context).primary
            : SnapColors.of(context).card,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SnapColors.of(context).textInverse
            : SnapColors.of(context).textSecondary,
      ),
      side: WidgetStateProperty.all(
          BorderSide(color: SnapColors.of(context).border, width: 0.8)),
      textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
        border:
            Border.all(color: SnapColors.of(context).textSecondary, width: 0.8),
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
          selectedZone: _activeHistogramZone,
          onSelectZone: (zone) {
            setState(() {
              _activeHistogramZone = zone;
              _lightroomGroupIndex = 0; // 基础色调
            });
          },
        ),

        const SizedBox(height: 12),

        // 2. 水印开启/关闭与当前模式指示条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: SnapColors.of(context).card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SnapColors.of(context).border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _selectedTemplate == WatermarkTemplate.none
                        ? Icons.filter_vintage
                        : Icons.branding_watermark,
                    color: _selectedTemplate == WatermarkTemplate.none
                        ? SnapColors.of(context).success
                        : SnapColors.of(context).primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedTemplate == WatermarkTemplate.none
                        ? '当前模式: 纯调色直出 (无水印)'
                        : '当前水印: ${_selectedTemplate.label}',
                    style: TextStyle(
                      color: _selectedTemplate == WatermarkTemplate.none
                          ? SnapColors.of(context).success
                          : SnapColors.of(context).textPrimary,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    _selectedTemplate == WatermarkTemplate.none
                        ? '开启水印'
                        : '关闭水印 (仅调色)',
                    style: TextStyle(
                      color: SnapColors.of(context).primary,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? SnapColors.of(context).primary
                          : SnapColors.of(context).card,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: isSelected
                            ? SnapColors.of(context).primary
                            : SnapColors.of(context).border,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      groups[idx],
                      style: TextStyle(
                        color: isSelected
                            ? SnapColors.of(context).textInverse
                            : SnapColors.of(context).textSecondary,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
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
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(exposure: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(exposure: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '对比度',
          code: 'Contrast',
          icon: Icons.contrast,
          value: _adjustments.contrast,
          hint: '增强或降低画面明暗反差',
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(contrast: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(contrast: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '高光',
          code: 'Highlights',
          icon: Icons.brightness_high_outlined,
          value: _adjustments.highlights,
          hint: '压暗过曝高光或提升亮部层次',
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(highlights: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(highlights: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '阴影',
          code: 'Shadows',
          icon: Icons.brightness_low_outlined,
          value: _adjustments.shadows,
          hint: '提亮暗部死黑或加深暗影深度',
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(shadows: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(shadows: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '白色色阶',
          code: 'Whites',
          icon: Icons.crop_square_outlined,
          value: _adjustments.whites,
          hint: '微调高光纯白剪切阈值',
          onChanged: (val) =>
              setState(() => _adjustments = _adjustments.copyWith(whites: val)),
          onReset: () =>
              setState(() => _adjustments = _adjustments.copyWith(whites: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '黑色色阶',
          code: 'Blacks',
          icon: Icons.square,
          value: _adjustments.blacks,
          hint: '微调暗部纯黑剪切点',
          onChanged: (val) =>
              setState(() => _adjustments = _adjustments.copyWith(blacks: val)),
          onReset: () =>
              setState(() => _adjustments = _adjustments.copyWith(blacks: 0.0)),
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
            colors: [const Color(0xFF29B6F6), const Color(0xFFFFB300)],
          ),
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(temperature: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(temperature: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '色调',
          code: 'Tint',
          icon: Icons.palette_outlined,
          value: _adjustments.tint,
          hint: '向左校正偏绿，向右偏洋红品红补偿',
          trackGradient: const LinearGradient(
            colors: [const Color(0xFF66BB6A), const Color(0xFFEC407A)],
          ),
          onChanged: (val) =>
              setState(() => _adjustments = _adjustments.copyWith(tint: val)),
          onReset: () =>
              setState(() => _adjustments = _adjustments.copyWith(tint: 0.0)),
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
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(clarity: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(clarity: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '纹理',
          code: 'Texture',
          icon: Icons.grain,
          value: _adjustments.texture,
          hint: '强化或柔化中高频细节，为人像微磨皮或突出毛发轮廓',
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(texture: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(texture: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '去朦胧',
          code: 'Dehaze',
          icon: Icons.blur_off_outlined,
          value: _adjustments.dehaze,
          hint: '消除逆光光雾漫反射，显著增加画面通透感',
          onChanged: (val) =>
              setState(() => _adjustments = _adjustments.copyWith(dehaze: val)),
          onReset: () =>
              setState(() => _adjustments = _adjustments.copyWith(dehaze: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '鲜艳度',
          code: 'Vibrance',
          icon: Icons.local_florist_outlined,
          value: _adjustments.vibrance,
          hint: '优先提升未饱和低彩度区域，智能保护人像肤色',
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(vibrance: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(vibrance: 0.0)),
        ),
        _buildLightroomSliderItem(
          title: '饱和度',
          code: 'Saturation',
          icon: Icons.color_lens_outlined,
          value: _adjustments.saturation,
          hint: '全局色彩纯度，降至最低为纯黑白，最高为浓郁艳丽',
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(saturation: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(saturation: 0.0)),
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
            color: SnapColors.of(context).card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SnapColors.of(context).border),
          ),
          child: Row(
            children: [
              Icon(Icons.palette_outlined,
                  size: 16, color: SnapColors.of(context).primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '色彩分级 (Split Toning)：分别为画面高光亮部与阴影暗部注入特定色调，打造电影感与日式冷暖色彩分离。',
                  style: TextStyle(
                      color: SnapColors.of(context).textSecondary,
                      fontSize: 11),
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
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(highlightHue: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(highlightHue: 0.0)),
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
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(highlightSat: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(highlightSat: 0.0)),
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
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(shadowHue: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(shadowHue: 0.0)),
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
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(shadowSat: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(shadowSat: 0.0)),
        ),
      ],
    );
  }

  Widget _buildSubCategoryPill({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? SnapColors.of(context).primary.withAlpha(40)
              : SnapColors.of(context).card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? SnapColors.of(context).primary
                : SnapColors.of(context).border,
            width: isSelected ? 1.2 : 0.6,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: isSelected
                  ? SnapColors.of(context).primary
                  : SnapColors.of(context).textSecondary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetCard(PhotoFilterType filter) {
    final isSelected = filter == _selectedFilter;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedFilter = filter),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? SnapColors.of(context).primary.withAlpha(35)
                : SnapColors.of(context).card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? SnapColors.of(context).primary
                  : SnapColors.of(context).border,
              width: isSelected ? 1.5 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 顶行: 色板条 + 英文代码
              Row(
                children: [
                  Row(
                    children: filter.previewColors
                        .take(3)
                        .map((c) => Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      filter.code,
                      style: TextStyle(
                        color: SnapColors.of(context).textTertiary,
                        fontSize: 9.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle,
                        size: 13, color: SnapColors.of(context).primary),
                ],
              ),
              const SizedBox(height: 3),
              // 中行: 中文名称
              Text(
                filter.label,
                style: TextStyle(
                  color: isSelected
                      ? SnapColors.of(context).primary
                      : SnapColors.of(context).textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 12.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // 底行: 核心配方参数摘要
              Text(
                filter.recipeSummary,
                style: TextStyle(
                  color: isSelected
                      ? SnapColors.of(context).primary.withAlpha(210)
                      : SnapColors.of(context).textTertiary,
                  fontSize: 9,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 胶片预设控制组 (一二级分类导航 + 双列视觉网格卡片 + 浓度滑块 + 一键载入)
  Widget _buildFilmPresetsGroup() {
    final cats2 = PhotoFilterType.getCategories2(_selectedCat1);
    final displayedFilters =
        PhotoFilterType.getByCategories(_selectedCat1, _selectedCat2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 一级分类水平标签栏
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: PhotoFilterType.categories1.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat1 = PhotoFilterType.categories1[index];
              final isSelected = cat1 == _selectedCat1;
              return ChoiceChip(
                label: Text(cat1),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedCat1 = cat1;
                      _selectedCat2 = null; // 重置二级分类为“全部”
                    });
                  }
                },
                selectedColor: SnapColors.of(context).primary,
                backgroundColor: SnapColors.of(context).card,
                labelStyle: TextStyle(
                  color: isSelected
                      ? SnapColors.of(context).textInverse
                      : SnapColors.of(context).textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                side: BorderSide(
                  color: isSelected
                      ? SnapColors.of(context).primary
                      : SnapColors.of(context).border,
                  width: 0.8,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                showCheckmark: false,
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // 2. 二级分类水平胶囊药丸栏
        if (cats2.length > 1) ...[
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildSubCategoryPill(
                  title:
                      '全部 (${PhotoFilterType.getByCategories(_selectedCat1).length})',
                  isSelected: _selectedCat2 == null,
                  onTap: () => setState(() => _selectedCat2 = null),
                ),
                const SizedBox(width: 6),
                ...cats2.map((c2) {
                  final count =
                      PhotoFilterType.getByCategories(_selectedCat1, c2).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildSubCategoryPill(
                      title: '$c2 ($count)',
                      isSelected: _selectedCat2 == c2,
                      onTap: () => setState(() => _selectedCat2 = c2),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ] else
          const SizedBox(height: 4),

        // 3. 双列预设卡片网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayedFilters.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.1,
          ),
          itemBuilder: (context, index) {
            final filter = displayedFilters[index];
            return _buildPresetCard(filter);
          },
        ),

        const SizedBox(height: 12),

        // 4. 当前选中预设详细参数提示卡片
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: SnapColors.of(context).card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SnapColors.of(context).border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 14, color: SnapColors.of(context).primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '【${_selectedFilter.label}】${_selectedFilter.description}',
                      style: TextStyle(
                          color: SnapColors.of(context).textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.tune,
                      size: 12, color: SnapColors.of(context).textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '机内配方: ${_selectedFilter.recipeSummary}',
                      style: TextStyle(
                          color: SnapColors.of(context).textSecondary,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 5. 预设浓度滑块
        Row(
          children: [
            Text('预设浓度',
                style: TextStyle(
                    color: SnapColors.of(context).textSecondary, fontSize: 12)),
            Expanded(
              child: Slider(
                value: _filterIntensity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                activeColor: SnapColors.of(context).primary,
                inactiveColor: SnapColors.of(context).border,
                label: '${(_filterIntensity * 100).round()}%',
                onChanged: _selectedFilter == PhotoFilterType.original
                    ? null
                    : (val) => setState(() => _filterIntensity = val),
              ),
            ),
            Text(
              '${(_filterIntensity * 100).round()}%',
              style: TextStyle(
                  color: SnapColors.of(context).primary,
                  fontSize: 11,
                  fontFamily: 'monospace'),
            ),
          ],
        ),

        // 6. 载入参数至滑块按钮
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
                  content:
                      Text('已载入【${_selectedFilter.label}】全套参数至调色滑块，可自由深度微调！'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: Icon(Icons.tune,
                size: 16, color: SnapColors.of(context).primary),
            label: Text(
              '载入【${_selectedFilter.label}】参数至滑块 (支持深度微调)',
              style: TextStyle(
                  color: SnapColors.of(context).primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side:
                  BorderSide(color: SnapColors.of(context).primary, width: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
          onChanged: (val) => setState(
              () => _adjustments = _adjustments.copyWith(vignette: val)),
          onReset: () => setState(
              () => _adjustments = _adjustments.copyWith(vignette: 0.0)),
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
          onChanged: (val) =>
              setState(() => _adjustments = _adjustments.copyWith(grain: val)),
          onReset: () =>
              setState(() => _adjustments = _adjustments.copyWith(grain: 0.0)),
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
      valueText = displayVal > 0
          ? '+$displayVal${unit ?? ''}'
          : '$displayVal${unit ?? ''}';
    }
    final isModified = value.abs() > 0.5;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SnapColors.of(context).card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isModified
              ? SnapColors.of(context).primary.withAlpha(80)
              : SnapColors.of(context).border,
          width: isModified ? 1.0 : 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 15,
                    color: isModified
                        ? SnapColors.of(context).primary
                        : SnapColors.of(context).textTertiary),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: TextStyle(
                  color: isModified
                      ? SnapColors.of(context).primary
                      : SnapColors.of(context).textSecondary,
                  fontSize: 12,
                  fontWeight: isModified ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                code,
                style: TextStyle(
                    color: SnapColors.of(context).textTertiary,
                    fontSize: 10,
                    fontFamily: 'monospace'),
              ),
              const Spacer(),
              InkWell(
                onTap: onReset,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isModified
                        ? SnapColors.of(context).primary.withAlpha(35)
                        : SnapColors.of(context).border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    valueText,
                    style: TextStyle(
                      color: isModified
                          ? SnapColors.of(context).primary
                          : SnapColors.of(context).textSecondary,
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
              style: TextStyle(
                  color: SnapColors.of(context).textTertiary, fontSize: 10),
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
                  activeTrackColor: trackGradient != null
                      ? Colors.transparent
                      : SnapColors.of(context).primary,
                  inactiveTrackColor: trackGradient != null
                      ? Colors.transparent
                      : SnapColors.of(context).border,
                  thumbColor: SnapColors.of(context).primary,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
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
