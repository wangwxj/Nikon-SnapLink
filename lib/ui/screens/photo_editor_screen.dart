import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/colors.dart';
import '../../engine/editor/photo_edit_controller.dart';
import '../../engine/transfer/export_history_manager.dart';
import '../../protocol/camera_native_bridge.dart';
import '../widgets/photo_edit_preview.dart';
import '../widgets/photo_edit_tools.dart';

/// 编辑结果保存方式
enum PhotoEditSaveMode { overwrite, saveAsCopy }

/// 编辑结果
class PhotoEditResult {
  final PhotoEditSaveMode mode;
  final String fileName;
  final String? mediaUri;
  final File file;
  final bool overwriteFallback;

  const PhotoEditResult({
    required this.mode,
    required this.fileName,
    required this.mediaUri,
    required this.file,
    this.overwriteFallback = false,
  });
}

/// 图片编辑器：旋转 / 翻转 / 透视 / 扭曲 / 自由变换 / 裁切。
///
/// 全屏查看器与水印工坊共用本页，不重复实现。
class PhotoEditorScreen extends StatefulWidget {
  final ExportedMediaItem item;
  final Uint8List bytes;

  const PhotoEditorScreen({
    super.key,
    required this.item,
    required this.bytes,
  });

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  late final PhotoEditController _controller;
  final GlobalKey _previewKey = GlobalKey();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  PhotoEditTool _activeTool = PhotoEditTool.rotate;
  double get _cropAspect => _controller.value.cropAspect;

  @override
  void initState() {
    super.initState();
    _controller = PhotoEditController();
    _controller.addListener(_onTransformChanged);
    _loadImage();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadImage() async {
    await _controller.load(widget.bytes);
    if (mounted)
      setState(() {
        _isLoading = false;
        _error = _controller.renderError;
      });
  }

  // ----------------------------------------------------------------
  // 保存：覆盖原图 / 另存为新文件
  // ----------------------------------------------------------------
  Future<void> _handleSave() async {
    if (_controller.loading || _isSaving) return;

    final mode = await showModalBottomSheet<PhotoEditSaveMode>(
      context: context,
      backgroundColor: SnapColors.of(context).cardElevated,
      shape: const RoundedRectangleBorder(
        borderRadius:
            const BorderRadius.vertical(top: const Radius.circular(16)),
      ),
      builder: (ctx) => _buildSaveSheet(ctx),
    );
    if (mode == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final result = await _renderAndSave(mode);
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('保存失败: $e'),
              backgroundColor: SnapColors.of(context).danger),
        );
      }
    }
  }

  Widget _buildSaveSheet(BuildContext ctx) {
    final context = ctx;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: SnapColors.of(context).borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('保存编辑结果',
                style: TextStyle(
                    color: SnapColors.of(context).textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('覆盖会替换原图；另存会生成一份新图片。',
                style: TextStyle(
                    color: SnapColors.of(context).textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            _saveOption(
              ctx,
              mode: PhotoEditSaveMode.overwrite,
              icon: Icons.save_outlined,
              title: '覆盖原图',
              subtitle: '替换原有图片（失败时自动另存）',
            ),
            const SizedBox(height: 10),
            _saveOption(
              ctx,
              mode: PhotoEditSaveMode.saveAsCopy,
              icon: Icons.copy_all_outlined,
              title: '另存为新文件',
              subtitle: '保留原图，生成 _edit 新文件',
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveOption(
    BuildContext ctx, {
    required PhotoEditSaveMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final context = ctx;
    final accent = mode == PhotoEditSaveMode.overwrite
        ? SnapColors.info
        : SnapColors.of(context).warning;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(ctx, mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: SnapColors.of(context).card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SnapColors.of(context).border),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: SnapColors.of(context).textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: SnapColors.of(context).textSecondary,
                          fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: SnapColors.of(context).textTertiary, size: 18),
          ],
        ),
      ),
    );
  }

  Future<PhotoEditResult> _renderAndSave(PhotoEditSaveMode mode) async {
    final isPng = widget.item.fileName.toLowerCase().endsWith('.png');
    final ext = isPng
        ? 'png'
        : widget.item.fileName.toLowerCase().endsWith('.jpeg')
            ? 'jpeg'
            : 'jpg';
    final encoded = await _controller.renderFull(format: isPng ? 'png' : 'jpg');

    final tempDir = await getTemporaryDirectory();
    final tempName = 'snaplink_edit_' +
        DateTime.now().millisecondsSinceEpoch.toString() +
        (isPng ? '.png' : '.jpg');
    final tempFile = File(tempDir.path + '/' + tempName);
    await tempFile.writeAsBytes(encoded, flush: true);

    final history = ExportHistoryManager();
    try {
      if (mode == PhotoEditSaveMode.overwrite) {
        final uri = widget.item.mediaUri;
        var ok = false;
        if (uri != null && uri.isNotEmpty) {
          ok = await CameraNativeBridge.overwriteMedia(uri, tempFile.path);
        }
        if (ok) {
          await history.markOverwritten(
            widget.item.fileName,
            tempFile,
            uri,
          );
          return PhotoEditResult(
            mode: PhotoEditSaveMode.overwrite,
            fileName: widget.item.fileName,
            mediaUri: uri,
            file: await history.ensureLocalFile(
                history.findExportedItemByExactName(widget.item.fileName) ??
                    widget.item),
          );
        }
        // 覆盖失败：回退到另存，避免用户丢失编辑
        return await _saveAsCopy(encoded, ext, history, fallbackNote: true);
      }

      return await _saveAsCopy(encoded, ext, history);
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<PhotoEditResult> _saveAsCopy(
    Uint8List encoded,
    String ext,
    ExportHistoryManager history, {
    bool fallbackNote = false,
  }) async {
    final base = widget.item.fileName.contains('.')
        ? widget.item.fileName
            .substring(0, widget.item.fileName.lastIndexOf('.'))
        : widget.item.fileName;
    final newName = base +
        '_edit_' +
        DateTime.now().millisecondsSinceEpoch.toString() +
        '.' +
        ext;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(tempDir.path + '/' + newName);
    await tempFile.writeAsBytes(encoded, flush: true);

    try {
      final saved = await CameraNativeBridge.saveMediaToGallery(
        tempFile.path,
        newName,
      );
      if (saved == null || saved.isEmpty) {
        throw StateError(fallbackNote ? '覆盖失败，且另存也失败' : '另存失败');
      }
      history.registerSavedCopy(newName, tempFile, saved);
      return PhotoEditResult(
        mode: PhotoEditSaveMode.saveAsCopy,
        fileName: newName,
        mediaUri: saved,
        file: await history
            .ensureLocalFile(history.findExportedItemByExactName(newName)!),
        overwriteFallback: fallbackNote,
      );
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  // ----------------------------------------------------------------
  // UI 构建
  // ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnapColors.of(context).background,
      body: SafeArea(
        child: AbsorbPointer(
            absorbing: _isSaving,
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _error != null
                      ? _buildError()
                      : _isLoading
                          ? const Center(
                              child: const CircularProgressIndicator(
                                color: SnapColors.nikonYellow,
                              ),
                            )
                          : _buildPreviewArea(),
                ),
                if (_error == null && !_isLoading)
                  PhotoEditToolsPanel(
                    controller: _controller,
                    activeTool: _activeTool,
                    onToolChanged: (t) {
                      setState(() => _activeTool = t);
                      _controller.setCropOverlay(t == PhotoEditTool.crop ||
                          t == PhotoEditTool.distort);
                    },
                    cropAspect: _cropAspect,
                    onCropAspectSelected: (v) => applyCropAspect(_controller, v),
                  ),
              ],
            )),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image,
                color: SnapColors.of(context).textSecondary, size: 56),
            const SizedBox(height: 12),
            Text(
              _error ?? '未知错误',
              style: TextStyle(
                  color: SnapColors.of(context).textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: SnapColors.of(context).surface,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: SnapColors.of(context).textPrimary),
            tooltip: '退出',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
              child: Text(
            '图像编辑',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: SnapColors.of(context).textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          )),
          IconButton(
            icon: Icon(Icons.undo, color: SnapColors.of(context).textPrimary),
            tooltip: '撤销',
            onPressed: _controller.canUndo ? _controller.undo : null,
          ),
          IconButton(
            icon: Icon(Icons.redo, color: SnapColors.of(context).textPrimary),
            tooltip: '重做',
            onPressed: _controller.canRedo ? _controller.redo : null,
          ),
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: SnapColors.nikonYellow),
                  )
                : Text('保存',
                    style: TextStyle(
                        color: SnapColors.of(context).primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    return Container(
      key: _previewKey,
      color: SnapColors.of(context).background,
      child: PhotoEditPreview(
        controller: _controller,
        previewImage: _controller.previewImage,
        cropAspect: _cropAspect,
        activeTool: _activeTool,
      ),
    );
  }
}
