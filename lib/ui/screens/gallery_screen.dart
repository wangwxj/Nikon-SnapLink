import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/network_config.dart';
import '../../core/utils/exif_helper.dart';
import '../../engine/transfer/download_manager.dart';
import '../../engine/transfer/export_history_manager.dart';
import '../../engine/transfer/shoot_and_transfer.dart';
import '../../protocol/camera_driver.dart';
import '../widgets/vant_widgets.dart';

// ================= 相机相册持久缓存 (列表 + 缩略图) =================

Future<Directory> _galleryCacheDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/gallery_cache');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 文件列表缓存路径 (按卡槽分文件)
Future<File> _cameraListCacheFile(int? storageId) async {
  final dir = await _galleryCacheDir();
  final key = storageId == null ? 'all' : storageId.toRadixString(16);
  return File('${dir.path}/camera_list_$key.json');
}

/// 读取上次的文件列表 (增量加载的基础)
Future<List<CameraFileItem>> _readCameraListCache(int? storageId) async {
  try {
    final f = await _cameraListCacheFile(storageId);
    if (!await f.exists()) return [];
    final List<dynamic> arr = jsonDecode(await f.readAsString());
    return arr
        .map((e) => CameraFileItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    return [];
  }
}

/// 持久化文件列表
Future<void> _writeCameraListCache(int? storageId, List<CameraFileItem> items) async {
  try {
    final f = await _cameraListCacheFile(storageId);
    await f.writeAsString(
      jsonEncode(items.map((e) => e.toJson()).toList()),
      flush: false,
    );
  } catch (_) {}
}

/// 缩略图磁盘缓存文件名 (相机 DCIM 内文件名唯一)
String _thumbCacheName(String fileName) =>
    fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').replaceAll(RegExp(r'_+'), '_');

Future<File> _thumbCacheFile(String fileName) async {
  final dir = Directory('${(await _galleryCacheDir()).path}/thumb');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}/${_thumbCacheName(fileName)}');
}

/// 静默获取照片原图字节 (本地已导出 > 缓存 > 相机下载)，失败返回 null
/// 预览界面渐进式加载使用：先出缩略图，随后升级为清晰原图
Future<Uint8List?> fetchFullPhotoBytesSilent(
  CameraDriver driver,
  Map<int, Uint8List> cache,
  CameraFileItem item,
) async {
  final cached = cache[item.handle];
  if (cached != null && cached.isNotEmpty) return cached;

  try {
    final local = ExportHistoryManager().findExportedItem(item.fileName);
    if (local != null && await local.file.exists()) {
      final bytes = await local.file.readAsBytes();
      if (bytes.isNotEmpty) {
        cache[item.handle] = bytes;
        return bytes;
      }
    }
  } catch (_) {}

  if (!driver.isConnected || item.size <= 0) return null;
  try {
    final bytes = await driver.downloadFullObject(item.handle, item.size);
    if (bytes.isNotEmpty) {
      cache[item.handle] = bytes;
      return bytes;
    }
  } catch (_) {}
  return null;
}

/// 带进度对话框获取照片原图 (进调色/水印前的高清传输等待)
Future<Uint8List?> fetchFullPhotoBytesWithDialog(
  BuildContext context,
  CameraDriver driver,
  Map<int, Uint8List> cache,
  CameraFileItem item,
) async {
  final cached = cache[item.handle];
  if (cached != null && cached.isNotEmpty) return cached;

  try {
    final local = ExportHistoryManager().findExportedItem(item.fileName);
    if (local != null && await local.file.exists()) {
      final bytes = await local.file.readAsBytes();
      if (bytes.isNotEmpty) {
        cache[item.handle] = bytes;
        return bytes;
      }
    }
  } catch (_) {}

  if (!driver.isConnected || item.size <= 0) return null;

  double downloadProgress = 0;
  bool isCanceled = false;
  bool dialogClosed = false;
  void Function(VoidCallback)? updateDialog;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        updateDialog = setDialogState;
        return AlertDialog(
          backgroundColor: SnapColors.cardElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.hd, color: SnapColors.primary, size: 22),
              SizedBox(width: 8),
              Text('加载高清照片中', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('正在从相机传输原图（${item.sizeFormatted}）以保证预览与水印画质...', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: downloadProgress > 0 ? downloadProgress : null,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(SnapColors.primary),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(downloadProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: SnapColors.primary, fontSize: 12, fontFamily: 'monospace')),
                  Text(item.fileName, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                isCanceled = true;
                dialogClosed = true;
                Navigator.pop(dialogCtx);
              },
              child: const Text('取消', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ],
        );
      },
    ),
  );

  Uint8List? result;
  try {
    result = await driver.downloadFullObject(
      item.handle,
      item.size,
      onProgress: (current, total) {
        if (!isCanceled) {
          downloadProgress = current / total;
          if (!dialogClosed) {
            try {
              updateDialog?.call(() {});
            } catch (_) {}
          }
        }
      },
    );
    if (result.isEmpty) result = null;
  } catch (_) {
    result = null;
  }

  if (!dialogClosed) {
    dialogClosed = true;
    if (context.mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
    }
  }

  if (result != null && !isCanceled) {
    cache[item.handle] = result;
    return result;
  }
  return null;
}

/// 相机照片同名合并组 (自动聚合 RAW 与 JPEG)
class CameraMediaGroup {
  final String baseName;
  CameraFileItem? jpegItem;
  CameraFileItem? rawItem;
  CameraFileItem? videoItem;

  CameraMediaGroup({
    required this.baseName,
    this.jpegItem,
    this.rawItem,
    this.videoItem,
  });

  bool get isRawAndJpeg => rawItem != null && jpegItem != null;
  bool get isRawOnly => rawItem != null && jpegItem == null && videoItem == null;
  bool get isJpegOnly => rawItem == null && jpegItem != null && videoItem == null;
  bool get isVideo => videoItem != null;

  String get formatBadge {
    if (isVideo) return 'VIDEO';
    if (isRawAndJpeg) return 'RAW+JPG';
    if (isRawOnly) return 'RAW';
    return 'JPG';
  }

  Color get formatBadgeColor {
    if (isVideo) return const Color(0xFFAB47BC);
    if (isRawAndJpeg) return const Color(0xFFFFB300); // 暖金标
    if (isRawOnly) return SnapColors.primary; // 极光青
    return const Color(0xFF66BB6A); // 翠绿
  }

  /// 缩略图优先取 JPEG 项以实现毫秒级快速解码，其次取 RAW
  CameraFileItem get primaryItem => jpegItem ?? rawItem ?? videoItem!;

  String get displayName => '$baseName.${primaryItem.fileName.split('.').last}';

  String get totalSizeFormatted {
    final total = (jpegItem?.size ?? 0) + (rawItem?.size ?? 0) + (videoItem?.size ?? 0);
    if (total >= 1024 * 1024 * 1024) {
      return '${(total / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (total >= 1024 * 1024) {
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(total / 1024).toStringAsFixed(1)} KB';
    }
  }
}

/// 相机存储卡照片浏览、下载与边拍边传管理页面 (Gallery Screen)
class GalleryScreen extends StatefulWidget {
  final CameraDriver driver;
  final DownloadManager downloadManager;
  final ShootAndTransferController shootAndTransferController;
  final Function(CameraFileItem item, Uint8List? imageBytes, {bool openFilter})? onOpenWatermark;

  const GalleryScreen({
    super.key,
    required this.driver,
    required this.downloadManager,
    required this.shootAndTransferController,
    this.onOpenWatermark,
  });

  @override
  State<GalleryScreen> createState() => GalleryScreenState();
}

class GalleryScreenState extends State<GalleryScreen> {
  bool _isLoading = false;
  List<CameraMediaGroup> _groups = [];
  final Set<String> _selectedBaseNames = {};
  bool _isSelectionMode = false;
  final Map<int, Uint8List> _thumbCache = {};
  final Map<int, Uint8List> _fullCache = {}; // 原图字节缓存 (预览/详情/调色共用)
  final Map<String, Future<Uint8List>> _thumbFutures = {}; // 缩略图 in-flight 去重 (key=fileName)
  int? _selectedStorageId; // null = 全部卡槽 (0xFFFFFFFF)
  StreamSubscription<CameraConnectionState>? _connSub;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _historyScrollController = ScrollController();

  // Tab 状态: 0 = 相机存储卡, 1 = 历史导出 (本地相册)
  int _activeTab = 0;
  final ExportHistoryManager _historyManager = ExportHistoryManager();
  String _activeFilter = '全部'; // '全部', '未同步', '已同步', 'JPG', 'RAW', 'JPG+RAW'

  List<CameraMediaGroup> get _filteredGroups {
    if (_activeFilter == '未同步') {
      return _groups.where((g) => !_historyManager.isExported(g.baseName)).toList();
    } else if (_activeFilter == '已同步') {
      return _groups.where((g) => _historyManager.isExported(g.baseName)).toList();
    } else if (_activeFilter == 'JPG') {
      return _groups.where((g) => g.isJpegOnly).toList();
    } else if (_activeFilter == 'RAW') {
      return _groups.where((g) => g.isRawOnly).toList();
    } else if (_activeFilter == 'JPG+RAW') {
      return _groups.where((g) => g.isRawAndJpeg).toList();
    } else if (_activeFilter == 'MP4') {
      return _groups.where((g) => g.isVideo).toList();
    }
    return _groups;
  }

  String _getSelectedTotalSize() {
    int total = 0;
    for (final g in _groups) {
      if (_selectedBaseNames.contains(g.baseName)) {
        total += (g.jpegItem?.size ?? 0) + (g.rawItem?.size ?? 0) + (g.videoItem?.size ?? 0);
      }
    }
    if (total == 0) return '大小未知';
    if (total >= 1024 * 1024 * 1024) {
      return '${(total / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (total >= 1024 * 1024) {
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(total / 1024).toStringAsFixed(1)} KB';
    }
  }

  @override
  void initState() {
    super.initState();
    // 初始化并刷新本地历史导出文件
    _historyManager.refresh();
    _historyManager.addListener(_onHistoryChanged);

    // 若当前未连接相机，默认激活历史导出视图，对齐用户指令
    if (!widget.driver.isConnected) {
      _activeTab = 1;
    }

    // 监听连接状态：连接建立时自动切回存储卡视图并刷新文件
    _connSub = widget.driver.connectionStateStream.listen((state) {
      if (!mounted) return;
      if (state == CameraConnectionState.connected) {
        setState(() => _activeTab = 0);
        _loadCameraFiles();
      } else if (state == CameraConnectionState.disconnected) {
        // 断开后自动切到历史导出
        setState(() => _activeTab = 1);
      }
    });

    if (widget.driver.isConnected) {
      _loadCameraFiles();
    }
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _historyManager.removeListener(_onHistoryChanged);
    _historyScrollController.dispose();
    _connSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// 供外部 (如 RootScaffold) 主动调用的刷新接口
  void reloadFiles() {
    if (mounted) _loadCameraFiles();
  }

  /// 标签页切换时空状态自动补漏刷新
  void reloadFilesIfEmpty() {
    if (_groups.isEmpty && widget.driver.isConnected && !_isLoading) {
      _loadCameraFiles();
    }
  }

  /// 超快渐进式文件列表加载算法
  /// 增量策略：本地列表缓存命中直接秒开，仅对相机上新增的句柄请求元数据
  Future<void> _loadCameraFiles() async {
    if (_isLoading || !widget.driver.isConnected) return;
    setState(() => _isLoading = true);

    try {
      final handles = await widget.driver.listObjectHandles(_selectedStorageId);
      final reversedHandles = handles.reversed.toList();

      if (reversedHandles.isEmpty) {
        if (mounted) {
          setState(() {
            _groups = [];
            _selectedBaseNames.clear();
          });
        }
        return;
      }

      // 阶段 0: 读取本地列表缓存，按句柄匹配已知项 (命中即免请求)
      final cachedItems = await _readCameraListCache(_selectedStorageId);
      final cachedByHandle = {for (final i in cachedItems) i.handle: i};
      final knownItems = <CameraFileItem>[];
      final missingHandles = <int>[];
      for (final h in reversedHandles) {
        final c = cachedByHandle[h];
        if (c != null) {
          knownItems.add(c);
        } else {
          missingHandles.add(h);
        }
      }

      // 阶段 1: 极速首屏 —— 缓存命中项直接上屏；无缓存时按最新 12 张拉取
      final firstItems = <CameraFileItem>[];
      if (knownItems.isNotEmpty) {
        firstItems.addAll(knownItems);
      } else {
        for (final h in missingHandles.take(12)) {
          try {
            final info = await widget.driver.getObjectInfo(h);
            if (info != null && !info.isFolder) {
              firstItems.add(info);
            }
          } catch (_) {}
        }
      }

      _updateMediaGroups(firstItems);

      if (mounted) {
        setState(() {
          _isLoading = false; // 首屏数据就绪，立刻呈现 UI 画面，避免白屏转圈
          _selectedBaseNames.clear();
        });
      }

      // 阶段 2: 后台流式补齐剩余的新增文件 (缓存全命中则无需任何相机请求)
      final remaining = knownItems.isNotEmpty
          ? missingHandles
          : missingHandles.skip(12).toList();
      if (remaining.isNotEmpty) {
        _streamLoadRemaining(remaining, firstItems);
      } else {
        // 小相册 (全部在首屏内完成) 或缓存全命中：直接落盘并预取缩略图
        if (firstItems.isNotEmpty) {
          await _writeCameraListCache(_selectedStorageId, firstItems);
          _prefetchThumbnails(firstItems);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载相机照片失败: $e'), backgroundColor: SnapColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 后台平滑分批流式追加加载，完成后持久化列表并预取缩略图
  void _streamLoadRemaining(List<int> handles, List<CameraFileItem> accumulator) async {
    const chunkSize = 12;
    for (var i = 0; i < handles.length; i += chunkSize) {
      if (!mounted || !widget.driver.isConnected) break;
      final chunk = handles.skip(i).take(chunkSize).toList();
      var hasNew = false;
      for (final h in chunk) {
        try {
          final info = await widget.driver.getObjectInfo(h);
          if (info != null && !info.isFolder) {
            accumulator.add(info);
            hasNew = true;
          }
        } catch (_) {}
      }
      if (hasNew && mounted) {
        _updateMediaGroups(accumulator);
        setState(() {});
      }
      await Future.delayed(const Duration(milliseconds: 30));
    }

    // 全量补齐后：持久化列表 (下次进来只查新增) + 后台预取缩略图
    if (mounted) {
      await _writeCameraListCache(_selectedStorageId, accumulator);
      _prefetchThumbnails(accumulator);
    }
  }

  /// 缩略图解析：内存 > 磁盘缓存 > 相机请求(写回磁盘)，同文件 in-flight 去重
  Future<Uint8List> _resolveThumb(CameraFileItem file) {
    final cached = _thumbCache[file.handle];
    if (cached != null && cached.isNotEmpty) {
      return Future.value(cached);
    }
    final inflight = _thumbFutures[file.fileName];
    if (inflight != null) return inflight;

    final future = () async {
      // 1. 磁盘缓存 (上次看过的缩略图秒出)
      try {
        final disk = await _thumbCacheFile(file.fileName);
        if (await disk.exists()) {
          final bytes = await disk.readAsBytes();
          if (bytes.isNotEmpty) {
            _thumbCache[file.handle] = bytes;
            return bytes;
          }
        }
      } catch (_) {}

      // 2. 相机请求并写回磁盘
      final bytes = await widget.driver.getThumbnail(file.handle);
      if (bytes.isNotEmpty) {
        _thumbCache[file.handle] = bytes;
        try {
          final disk = await _thumbCacheFile(file.fileName);
          disk.writeAsBytes(bytes); // fire & forget
        } catch (_) {}
      }
      return bytes;
    }();

    _thumbFutures[file.fileName] = future;
    future.whenComplete(() => _thumbFutures.remove(file.fileName));
    return future;
  }

  /// 后台低速预取缩略图：先磁盘后相机，让滚动到哪都秒显
  Future<void> _prefetchThumbnails(List<CameraFileItem> items) async {
    await Future.delayed(const Duration(milliseconds: 300)); // 避开首屏交互
    for (final item in items) {
      if (!mounted || !widget.driver.isConnected) return;
      if (item.isFolder || _thumbCache.containsKey(item.handle)) continue;
      try {
        await _resolveThumb(item);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 12));
    }
  }

  void _updateMediaGroups(List<CameraFileItem> items) {
    final groupMap = <String, CameraMediaGroup>{};
    final orderList = <String>[];

    for (final item in items) {
      final dotIdx = item.fileName.lastIndexOf('.');
      final baseName = dotIdx != -1 ? item.fileName.substring(0, dotIdx) : item.fileName;
      final ext = dotIdx != -1 ? item.fileName.substring(dotIdx + 1).toUpperCase() : '';
      final isVid = item.isVideo || ext == 'MOV' || ext == 'MP4';

      // 视频独立成组 (即使与照片同名也单独显示，保证 MP4 在相册中可见)
      final key = isVid ? '$baseName#video' : baseName;

      if (!groupMap.containsKey(key)) {
        groupMap[key] = CameraMediaGroup(baseName: baseName);
        orderList.add(key);
      }

      final g = groupMap[key]!;
      if (isVid) {
        g.videoItem = item;
      } else if (item.isRaw || ext == 'NEF' || ext == 'NRW') {
        g.rawItem = item;
      } else {
        g.jpegItem = item;
      }
    }

    _groups = orderList.map((k) => groupMap[k]!).toList();
  }

  void _toggleSelectGroup(String baseName) {
    setState(() {
      if (_selectedBaseNames.contains(baseName)) {
        _selectedBaseNames.remove(baseName);
        // 勾选归零时自动退出多选模式，恢复点击预览
        if (_selectedBaseNames.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedBaseNames.add(baseName);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedBaseNames.length == _groups.length) {
        _selectedBaseNames.clear();
        _isSelectionMode = false;
      } else {
        _selectedBaseNames.addAll(_groups.map((g) => g.baseName));
        _isSelectionMode = _groups.isNotEmpty;
      }
    });
  }

  /// 全屏查看大图预览 (支持双指手势缩放、左右滑动切图、原图渐进加载与一键调色)
  void _openFullScreenPreview(int index) {
    if (index < 0 || index >= _groups.length) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenPhotoViewer(
          groups: _groups,
          initialIndex: index,
          thumbCache: _thumbCache,
          fullCache: _fullCache,
          driver: widget.driver,
          onExportSingle: _handleExportSingle,
          onOpenWatermark: widget.onOpenWatermark,
        ),
      ),
    );
  }

  /// 导出单张照片流程
  Future<void> _handleExportSingle(CameraMediaGroup group) async {
    List<CameraFileItem> filesToDownload = [];
    if (group.isRawAndJpeg) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: SnapColors.cardElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => _buildExportFormatSheet(ctx, 1),
      );
      if (choice == null) return;
      if (choice == 'both') {
        if (group.rawItem != null) filesToDownload.add(group.rawItem!);
        if (group.jpegItem != null) filesToDownload.add(group.jpegItem!);
      } else {
        if (group.jpegItem != null) filesToDownload.add(group.jpegItem!);
      }
    } else {
      if (group.rawItem != null) filesToDownload.add(group.rawItem!);
      if (group.jpegItem != null) filesToDownload.add(group.jpegItem!);
      if (group.videoItem != null) filesToDownload.add(group.videoItem!);
    }

    if (filesToDownload.isNotEmpty) {
      _showBlockingTransferDialog(filesToDownload);
    }
  }

  /// 导出选中照片流程
  Future<void> _handleExport() async {
    final selected = _groups.where((g) => _selectedBaseNames.contains(g.baseName)).toList();
    if (selected.isEmpty) return;

    final hasRawAndJpeg = selected.any((g) => g.isRawAndJpeg);
    List<CameraFileItem> filesToDownload = [];

    if (hasRawAndJpeg) {
      // 弹出格式选择对话框
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: SnapColors.cardElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => _buildExportFormatSheet(ctx, selected.length),
      );

      if (choice == null) return; // 用户取消

      for (final g in selected) {
        if (g.isRawAndJpeg) {
          if (choice == 'both') {
            if (g.rawItem != null) filesToDownload.add(g.rawItem!);
            if (g.jpegItem != null) filesToDownload.add(g.jpegItem!);
          } else {
            // 仅需 JPEG
            if (g.jpegItem != null) filesToDownload.add(g.jpegItem!);
          }
        } else {
          if (g.rawItem != null) filesToDownload.add(g.rawItem!);
          if (g.jpegItem != null) filesToDownload.add(g.jpegItem!);
          if (g.videoItem != null) filesToDownload.add(g.videoItem!);
        }
      }
    } else {
      // 直接打包全部文件
      for (final g in selected) {
        if (g.rawItem != null) filesToDownload.add(g.rawItem!);
        if (g.jpegItem != null) filesToDownload.add(g.jpegItem!);
        if (g.videoItem != null) filesToDownload.add(g.videoItem!);
      }
    }

    if (filesToDownload.isEmpty) return;

    setState(() {
      _selectedBaseNames.clear();
      _isSelectionMode = false;
    });

    // 启动带进度条的阻塞式传输对话框
    _showBlockingTransferDialog(filesToDownload);
  }

  /// 导出格式选择底部模态框
  Widget _buildExportFormatSheet(BuildContext ctx, int groupCount) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '选择导出格式',
              style: TextStyle(color: SnapColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '选中的 $groupCount 张照片中包含 RAW + JPEG 双格式照片，请选择导出方式：',
              style: const TextStyle(color: SnapColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),

            // 选项 1: 导出全部 (RAW + JPEG)
            InkWell(
              onTap: () => Navigator.pop(ctx, 'both'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SnapColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SnapColors.primary.withAlpha(120), width: 1),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.collections, color: SnapColors.primary, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('导出全部 (RAW + JPEG)', style: TextStyle(color: SnapColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('保留最高画质 RAW 底片及直出 JPEG 成片', style: TextStyle(color: SnapColors.textTertiary, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 选项 2: 仅需 JPEG
            InkWell(
              onTap: () => Navigator.pop(ctx, 'jpeg_only'),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SnapColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SnapColors.border, width: 0.8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.image, color: Color(0xFF66BB6A), size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('仅需 JPEG (推荐快速分享)', style: TextStyle(color: SnapColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('仅传输直出成片，传输速度更快、省手机空间', style: TextStyle(color: SnapColors.textTertiary, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 阻塞式传输进度对话框 (避免用户并发冲突操作)
  void _showBlockingTransferDialog(List<CameraFileItem> files) {
    widget.downloadManager.enqueueAll(files);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (dialogCtx, setDialogState) {
              return AnimatedBuilder(
                animation: widget.downloadManager,
                builder: (context, _) {
                  final dm = widget.downloadManager;
                  final task = dm.currentTask;

                  final fileHandles = files.map((f) => f.handle).toSet();
                  final completedInBatch = dm.tasks.where((t) => fileHandles.contains(t.fileItem.handle) && t.status == DownloadTaskStatus.completed).length;
                  final failedInBatch = dm.tasks.where((t) => fileHandles.contains(t.fileItem.handle) && t.status == DownloadTaskStatus.failed).length;
                  final isAllDone = (completedInBatch + failedInBatch) >= files.length;

                  if (isAllDone) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (Navigator.canPop(dialogCtx)) {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已成功导出 $completedInBatch 张照片至手机相册 (/DCIM/SnapLink)'),
                            backgroundColor: SnapColors.success,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    });
                  }

                  final batchProgress = files.isNotEmpty ? (completedInBatch / files.length).clamp(0.0, 1.0) : 0.0;
                  final currentTaskProgress = task?.progress ?? 0.0;

                  return AlertDialog(
                    backgroundColor: SnapColors.cardElevated,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(SnapColors.primary)),
                        ),
                        SizedBox(width: 12),
                        Text('正在导出照片到手机', style: TextStyle(color: SnapColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '通信通道独占中，已自动阻止其他操作以防止 Socket 冲突。',
                          style: TextStyle(color: SnapColors.textSecondary, fontSize: 11),
                        ),
                        const SizedBox(height: 16),

                        // 当前文件与进度
                        if (task != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  task.fileItem.fileName,
                                  style: const TextStyle(color: SnapColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${(currentTaskProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(color: SnapColors.primary, fontSize: 12, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: currentTaskProgress,
                            backgroundColor: SnapColors.border,
                            valueColor: const AlwaysStoppedAnimation(SnapColors.primary),
                            minHeight: 4,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '单文件大小: ${task.fileItem.sizeFormatted}',
                            style: const TextStyle(color: SnapColors.textTertiary, fontSize: 10),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // 总体批次进度
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '批次进度: 第 ${completedInBatch + 1} / ${files.length} 张',
                              style: const TextStyle(color: SnapColors.textPrimary, fontSize: 12),
                            ),
                            Text(
                              '${(batchProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: batchProgress,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF00E676)),
                          minHeight: 3,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '保存路径: /DCIM/SnapLink (相册可见)',
                          style: TextStyle(color: SnapColors.textTertiary, fontSize: 10),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          dm.cancelAll();
                          Navigator.pop(dialogCtx);
                        },
                        child: const Text('取消剩余任务', style: TextStyle(color: SnapColors.danger, fontSize: 12)),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.driver.isConnected;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // 自适应大小：竖屏严格 3 列一行，横屏 4~8 列
    final crossAxisCount = isLandscape
        ? (MediaQuery.of(context).size.width / 130).floor().clamp(4, 8)
        : 3;

    final displayGroups = _filteredGroups;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(isConnected ? (_activeTab == 0 ? '相机照片' : '历史导出 (${_historyManager.count})') : '历史导出 (手机相册)'),
            const SizedBox(width: 8),
            if (isConnected && _activeTab == 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF152A1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00E676).withAlpha(80), width: 0.8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: Color(0xFF00E676)),
                    SizedBox(width: 4),
                    Text('相机 Wi-Fi', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (isConnected && _activeTab == 0) ...[
            // 卡槽选择下拉菜单 (单卡槽机型彻底隐藏)
            if (!widget.driver.isSingleSlotCamera && widget.driver.availableStorageIds.length > 1)
              PopupMenuButton<int?>(
                icon: const Icon(Icons.sd_card),
                tooltip: '选择卡槽',
                onSelected: (val) {
                  setState(() => _selectedStorageId = val);
                  _loadCameraFiles();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: null,
                    child: Text('全部存储 (自动合并)'),
                  ),
                  const PopupMenuItem(
                    value: 0x00010001,
                    child: Text('卡槽 1 (Slot 1)'),
                  ),
                  const PopupMenuItem(
                    value: 0x00020001,
                    child: Text('卡槽 2 (Slot 2)'),
                  ),
                ],
              ),

            // 批量选择切换按钮
            TextButton(
              onPressed: () {
                setState(() {
                  _isSelectionMode = !_isSelectionMode;
                  if (!_isSelectionMode) _selectedBaseNames.clear();
                });
              },
              child: Text(
                _isSelectionMode ? '取消' : '多选',
                style: TextStyle(color: _isSelectionMode ? SnapColors.danger : SnapColors.primary, fontSize: 13),
              ),
            ),

            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新存储卡',
              onPressed: _loadCameraFiles,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新已导出相册',
              onPressed: () {
                _historyManager.refresh();
              },
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 1. 相机信息卡片 (对齐 media_1791281187039.jpg)
              if (isConnected && _activeTab == 0) _buildCameraInfoBar(),

              // 2. 格式与同步快捷筛选药丸栏 (对齐 media_1791281187039.jpg)
              if (isConnected && _activeTab == 0) _buildFilterBar(),

              // 3. 边拍边传开启时极简指示
              if (isConnected && _activeTab == 0 && widget.shootAndTransferController.isEnabled)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16251B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SnapColors.success.withAlpha(100), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_alt, color: SnapColors.success, size: 14),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '边拍边传已开启：快门触发后静默同步原图',
                          style: TextStyle(color: Colors.white, fontSize: 10.5),
                        ),
                      ),
                      Switch(
                        value: true,
                        activeThumbColor: SnapColors.success,
                        onChanged: (val) {
                          setState(() {
                            widget.shootAndTransferController.setEnabled(val);
                          });
                        },
                      ),
                    ],
                  ),
                ),

              // 4. 内容主体区: 相机存储卡 vs 历史导出
              Expanded(
                child: (!isConnected || _activeTab == 1)
                    ? _buildHistoryExportView(crossAxisCount)
                    : _isLoading
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(SnapColors.primary)),
                                SizedBox(height: 12),
                                Text('正在枚举相机存储卡文件列表 (0x1007)...', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          )
                        : displayGroups.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.photo_library_outlined, size: 48, color: Colors.white24),
                                      const SizedBox(height: 12),
                                      Text(
                                        _groups.isEmpty ? '相机中未检测到照片或正在读取...' : '当前筛选「$_activeFilter」下无照片',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : GridView.builder(
                                key: const PageStorageKey<String>('camera_gallery_grid'),
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 80),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                  childAspectRatio: 1.0, // 严格正方形 (对齐 media_1791281187039.jpg)
                                ),
                                itemCount: displayGroups.length,
                                itemBuilder: (context, index) {
                                  final group = displayGroups[index];
                                  final isSelected = _selectedBaseNames.contains(group.baseName);
                                  return _buildMediaGroupCard(group, isSelected, index);
                                },
                              ),
              ),
            ],
          ),

          // 5. 底部悬浮操作岛 Floating Action Dock (对齐 media_1791281187039.jpg)
          if (isConnected && _activeTab == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFloatingActionDock(),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // 相机信息条 (对齐 media_1791281187039.jpg)
  // ==========================================
  Widget _buildCameraInfoBar() {
    final cameraName = widget.driver.cameraModel.isNotEmpty ? widget.driver.cameraModel : 'Z 30';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16171E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262832), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1014),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12, width: 0.8),
            ),
            child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cameraName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${NetworkConfig.cameraIp}:${NetworkConfig.cameraPort} · PTP/IP',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已就绪：可在底部导航「设置」中配置通信与缓存参数'),
                  duration: Duration(milliseconds: 1000),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, color: Colors.white70, size: 16),
                  SizedBox(width: 4),
                  Text('设置', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 格式与同步筛选药丸栏 (对齐 media_1791281187039.jpg)
  // ==========================================
  Widget _buildFilterBar() {
    const filters = ['全部', '未同步', '已同步', 'JPG', 'RAW', 'JPG+RAW', 'MP4'];
    return Container(
      color: SnapColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((f) {
                  final isSelected = _activeFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _activeFilter = f);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.black : const Color(0xFF22242C),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Colors.white38 : const Color(0xFF2D303C),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              const Icon(Icons.check, size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              f,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 蓝色漏斗筛选图标按钮 (对齐 media_1791281187039.jpg): 点击一键全选或反选当前媒体
          GestureDetector(
            onTap: _selectAll,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.select_all, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 底部悬浮操作岛 (对齐 media_1791281187039.jpg)
  // ==========================================
  Widget _buildFloatingActionDock() {
    final selectedCount = _selectedBaseNames.length;
    final totalSizeText = _getSelectedTotalSize();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111216),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF262832), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(160),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  '已选择 $selectedCount 组媒体 · 大小 $totalSizeText',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (selectedCount > 0) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedBaseNames.clear();
                        _isSelectionMode = false;
                      });
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline, size: 16, color: Colors.white54),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: selectedCount > 0
                ? _handleExport
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请先在照片右上角勾选需要同步的照片，或点击批量选择'),
                        duration: Duration(milliseconds: 1200),
                      ),
                    );
                  },
            child: const Text(
              '同步到手机',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }


  /// 历史导出 (本地相册已下载照片) 视图
  Widget _buildHistoryExportView(int crossAxisCount) {
    if (_historyManager.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(SnapColors.primary)),
            SizedBox(height: 12),
            Text('正在扫描本地已导出照片...', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    final items = _historyManager.items;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 52, color: SnapColors.textTertiary),
              const SizedBox(height: 14),
              const Text('本地暂无已导出的照片', style: TextStyle(color: SnapColors.textSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                '当您连接相机并导出照片，或在水印工坊制作并保存图片后，\n无需连接相机，均可在此随时查看、加水印与分享！',
                style: TextStyle(color: SnapColors.textTertiary, fontSize: 12, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              VantButton(
                text: '刷新手机相册目录',
                icon: Icons.refresh,
                onTap: () => _historyManager.refresh(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 本地相册路径与统计条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: SnapColors.surface,
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 14, color: SnapColors.primary),
              const SizedBox(width: 6),
              Text(
                '保存路径: /DCIM/SnapLink · 共 ${items.length} 张已导出',
                style: const TextStyle(color: SnapColors.textSecondary, fontSize: 11),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _historyManager.refresh(),
                child: const Row(
                  children: [
                    Icon(Icons.refresh, size: 13, color: SnapColors.primary),
                    SizedBox(width: 2),
                    Text('刷新', style: TextStyle(color: SnapColors.primary, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3 列网格列表
        Expanded(
          child: GridView.builder(
            key: const PageStorageKey<String>('exported_history_grid'),
            controller: _historyScrollController,
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.85,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildExportedItemCard(item, index);
            },
          ),
        ),
      ],
    );
  }

  /// 本地已导出照片卡片
  Widget _buildExportedItemCard(ExportedMediaItem item, int index) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openFullScreenLocalPreview(index),
      child: Container(
        decoration: BoxDecoration(
          color: SnapColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SnapColors.border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                    child: Container(
                      color: const Color(0xFF16161A),
                      child: Image.file(
                        item.file,
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, size: 28, color: Colors.white24),
                        ),
                      ),
                    ),
                  ),

                  // 左上角绿色「已导出」角标
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: SnapColors.success,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 8, color: Colors.white),
                          SizedBox(width: 2),
                          Text('已导出', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),

                  // 右上角格式角标
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        item.formatBadge,
                        style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 底栏文件名与大小 (干净无多余文字)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: SnapColors.textPrimary, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.sizeFormatted,
                    style: const TextStyle(color: SnapColors.textTertiary, fontSize: 8.5, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 全屏查看本地历史导出大图
  void _openFullScreenLocalPreview(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenLocalImageViewer(
          items: _historyManager.items,
          initialIndex: initialIndex,
          onOpenWatermark: (item, bytes) {
            final fakeCameraItem = CameraFileItem(
              handle: 0,
              storageId: 0,
              format: 0x3801,
              size: item.size,
              fileName: item.fileName,
              captureDate: item.dateFormatted,
            );
            widget.onOpenWatermark?.call(fakeCameraItem, bytes, openFilter: true);
          },
          onDelete: (item) async {
            await _historyManager.deleteItem(item);
          },
        ),
      ),
    );
  }

  /// 单个相机同名照片卡片 (对标 media_1791281187039.jpg: 纯正方形 1:1，格式角标左上，选择框右上，同步微胶囊左下)
  Widget _buildMediaGroupCard(CameraMediaGroup group, bool isSelected, int index) {
    final isExported = _historyManager.isExported(group.baseName);
    final isPartial = !isExported && group.isRawAndJpeg &&
        (_historyManager.isExported('${group.baseName}.JPG') || _historyManager.isExported('${group.baseName}.NEF'));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelectGroup(group.baseName);
        } else {
          // 点击照片弹出照片详情卡片 (对齐 media_1791281187020.jpg)
          _showPhotoDetailsModal(group, index);
        }
      },
      child: Container(
        key: ValueKey(group.baseName),
        decoration: BoxDecoration(
          color: const Color(0xFF16171E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF1976D2) : const Color(0xFF282A34),
            width: isSelected ? 2 : 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 核心缩略图展示 (铺满 1:1 正方形卡片)
            _buildThumbnailImage(group.primaryItem),

            // 左上角格式胶囊 (JPG+RAW, JPG, RAW, VIDEO) - 对齐 media_1791281187039.jpg
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  group.formatBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // 右上角圆形复选圈 (点击独立切换勾选状态) - 对齐 media_1791281187039.jpg
            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleSelectGroup(group.baseName),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? const Color(0xFF1976D2) : Colors.black.withAlpha(120),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1976D2) : Colors.white70,
                      width: 1.2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            ),

            // 左下角同步状态微胶囊 (已同步 / 部分同步 / 未同步) - 对齐 media_1791281187039.jpg
            Positioned(
              bottom: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isExported
                      ? const Color(0xFF00C853)
                      : (isPartial ? const Color(0xFFFF8F00) : Colors.black.withAlpha(160)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isExported ? '已同步' : (isPartial ? '部分同步' : '未同步'),
                  style: TextStyle(
                    color: isExported || isPartial ? Colors.white : Colors.white70,
                    fontSize: 8.5,
                    fontWeight: isExported || isPartial ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 照片详情弹窗 (高精度对齐 media_1791281187020.jpg)
  void _showPhotoDetailsModal(CameraMediaGroup group, int index) async {
    final cachedBytes = _thumbCache[group.primaryItem.handle];
    PhotoMetadata meta = const PhotoMetadata();
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      meta = await ExifHelper.parseBytes(cachedBytes);
    }
    if (!mounted) return;
    final cameraName = widget.driver.cameraModel.isNotEmpty ? widget.driver.cameraModel : 'Z50_2';

    // 原图渐进加载：先展示缩略图，后台拉取原图后自动升级画质
    final cachedFull = _fullCache[group.primaryItem.handle];
    final previewState = ValueNotifier<({Uint8List? bytes, bool done})>(
      (bytes: cachedFull, done: cachedFull != null && cachedFull.isNotEmpty),
    );
    if (!previewState.value.done) {
      fetchFullPhotoBytesSilent(widget.driver, _fullCache, group.primaryItem).then((b) {
        previewState.value = (bytes: b, done: true);
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14151C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部返回与标题 (对齐 media_1791281187020.jpg)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '照片详情',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: group.formatBadgeColor.withAlpha(200),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        group.formatBadge,
                        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 照片预览区域 (缩略图秒出，原图加载完成后自动升级画质)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 280,
                    width: double.infinity,
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ValueListenableBuilder<({Uint8List? bytes, bool done})>(
                          valueListenable: previewState,
                          builder: (context, state, _) {
                            if (state.bytes != null && state.bytes!.isNotEmpty) {
                              return Image.memory(
                                state.bytes!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, __, ___) => _buildFallbackIcon(group.primaryItem),
                              );
                            }
                            final thumb = _thumbCache[group.primaryItem.handle];
                            if (thumb != null && thumb.isNotEmpty) {
                              return Image.memory(
                                thumb,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, __, ___) => _buildFallbackIcon(group.primaryItem),
                              );
                            }
                            return _buildThumbnailImage(group.primaryItem);
                          },
                        ),
                        // 原图拉取进度角标
                        ValueListenableBuilder<({Uint8List? bytes, bool done})>(
                          valueListenable: previewState,
                          builder: (context, state, _) {
                            if (state.done) return const SizedBox.shrink();
                            return Positioned(
                              left: 10,
                              top: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(160),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(strokeWidth: 1.6, color: SnapColors.primary),
                                    ),
                                    SizedBox(width: 6),
                                    Text('原图加载中…', style: TextStyle(color: Colors.white70, fontSize: 9)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              _openFullScreenPreview(index);
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(160),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.open_in_full_rounded, size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 拍摄参数质感卡片 (对齐 media_1791281187020.jpg)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2028),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2F3C), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '拍摄参数',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 2x2 参数方块 (快门、光圈、ISO、焦距)
                      Row(
                        children: [
                          Expanded(
                            child: _buildParamBox(
                              '快门',
                              meta.shutterSpeed.isNotEmpty ? meta.shutterSpeed : '1/200s',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildParamBox(
                              '光圈',
                              meta.aperture.isNotEmpty ? meta.aperture : 'f/5',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildParamBox(
                              'ISO',
                              meta.iso.isNotEmpty ? meta.iso.replaceAll('ISO ', '') : '250',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildParamBox(
                              '焦距',
                              meta.focalLength.isNotEmpty ? meta.focalLength : '100mm',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 相机与镜头型号
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('相机', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'NIKON CORPORATION NIKON $cameraName',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('镜头', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              meta.lensModel.isNotEmpty ? meta.lensModel : 'NIKKOR Z DX 50-250mm f/4.5-6.3 VR',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF3E4150)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.branding_watermark_outlined, size: 16),
                        label: const Text('加水印 / 调色', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          // 先等待原图传输完成，再进入水印/调色，保证画质
                          final bytes = await fetchFullPhotoBytesWithDialog(
                            context,
                            widget.driver,
                            _fullCache,
                            group.primaryItem,
                          );
                          if (!mounted) return;
                          widget.onOpenWatermark?.call(
                            group.primaryItem,
                            bytes ?? _thumbCache[group.primaryItem.handle],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        label: const Text('同步到手机', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleExportSingle(group);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildParamBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF262833),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailImage(CameraFileItem file) {
    if (_thumbCache.containsKey(file.handle)) {
      final cachedBytes = _thumbCache[file.handle]!;
      if (cachedBytes.isNotEmpty) {
        return Image.memory(
          cachedBytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _buildFallbackIcon(file),
        );
      }
    }

    return FutureBuilder<Uint8List>(
      future: _resolveThumb(file), // 内存 > 磁盘缓存 > 相机 (in-flight 去重)
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data!.isNotEmpty) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _buildFallbackIcon(file),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(SnapColors.primary)),
            ),
          );
        }
        return _buildFallbackIcon(file);
      },
    );
  }

  Widget _buildFallbackIcon(CameraFileItem file) {
    return Center(
      child: Icon(
        file.isVideo ? Icons.videocam : Icons.photo,
        size: 38,
        color: file.isRaw ? SnapColors.primary : Colors.white30,
      ),
    );
  }
}

/// 全屏专业艺术展卡 / 诗意暗房大图预览器 (高保真对齐 media_1791281238081.jpg ~ media_1791281248682.jpg)
/// 支持展卡与暗房双模式切换、高斯模糊氛围背景、8段式 Stories 进度条、幻灯片轮播与快捷导出
class FullScreenPhotoViewer extends StatefulWidget {
  final List<CameraMediaGroup> groups;
  final int initialIndex;
  final Map<int, Uint8List> thumbCache;
  final Map<int, Uint8List> fullCache;
  final CameraDriver driver;
  final Function(CameraMediaGroup group)? onExportSingle;
  final Function(CameraFileItem item, Uint8List? imageBytes, {bool openFilter})? onOpenWatermark;

  const FullScreenPhotoViewer({
    super.key,
    required this.groups,
    required this.initialIndex,
    required this.thumbCache,
    required this.fullCache,
    required this.driver,
    this.onExportSingle,
    this.onOpenWatermark,
  });

  @override
  State<FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<FullScreenPhotoViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  final Set<int> _fullTried = {}; // 已发起过原图加载的 handle，避免失败后死循环重试

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 后台静默拉取原图，完成后 setState 升级画质 (加载动画 → 清晰照片)
  void _ensureFullLoaded(CameraFileItem file) {
    if (_fullTried.contains(file.handle)) return;
    _fullTried.add(file.handle);
    fetchFullPhotoBytesSilent(widget.driver, widget.fullCache, file).then((bytes) {
      if (mounted && bytes != null) setState(() {});
    });
  }

  /// 去调色：等待原图传输完成后退出预览并进入水印工坊调色 Tab
  Future<void> _handleOpenFilter(CameraFileItem primary) async {
    final bytes = await fetchFullPhotoBytesWithDialog(
      context,
      widget.driver,
      widget.fullCache,
      primary,
    );
    if (!mounted) return;
    Navigator.pop(context);
    widget.onOpenWatermark?.call(
      primary,
      bytes ?? widget.thumbCache[primary.handle],
      openFilter: true,
    );
  }

  /// 照片渲染：本地导出 > 原图 > 缩略图(带原图加载进度角标)
  Widget _buildPhotoWidget(CameraFileItem file, {BoxFit fit = BoxFit.contain}) {
    final localItem = ExportHistoryManager().findExportedItem(file.fileName);
    if (localItem != null && localItem.file.existsSync()) {
      return Image.file(
        localItem.file,
        fit: fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38, size: 64),
      );
    }

    final full = widget.fullCache[file.handle];
    if (full != null && full.isNotEmpty) {
      return Image.memory(
        full,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38, size: 64),
      );
    }

    _ensureFullLoaded(file);

    final cachedThumb = widget.thumbCache[file.handle];
    if (cachedThumb != null && cachedThumb.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            cachedThumb,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38, size: 64),
          ),
          const Positioned(
            top: 10,
            right: 10,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: SnapColors.primary),
            ),
          ),
        ],
      );
    }

    return FutureBuilder<Uint8List>(
      future: widget.driver.getThumbnail(file.handle),
      builder: (ctx, snap) {
        if (snap.hasData && snap.data!.isNotEmpty) {
          widget.thumbCache[file.handle] = snap.data!;
          return Image.memory(snap.data!, fit: fit);
        }
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(SnapColors.primary)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: const Center(child: Text('暂无照片', style: TextStyle(color: Colors.white70))),
      );
    }

    final primary = widget.groups[_currentIndex.clamp(0, widget.groups.length - 1)].primaryItem;
    final totalCount = widget.groups.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 纯黑底全屏滑动预览 (最基础的看图体验：无模糊背景、无信息卡)
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: totalCount,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemBuilder: (context, index) {
                final file = widget.groups[index].primaryItem;
                return Center(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.5,
                    child: _buildPhotoWidget(file, fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),

          // 2. 顶部相机内编号/总编号
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12, width: 0.8),
                ),
                child: Text(
                  '${_currentIndex + 1} / $totalCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),

          // 3. 底部控制条：退出 + 去调色
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            child: Row(
              children: [
                // 退出 [ X ]
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2028).withAlpha(220),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12, width: 0.8),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
                const Spacer(),

                // 去调色按钮
                GestureDetector(
                  onTap: () => _handleOpenFilter(primary),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: SnapColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.palette_outlined, color: Colors.black, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '调色',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 本地历史导出照片全屏艺术展卡 / 诗意暗房大图预览器 (对齐参考图规范)
class FullScreenLocalImageViewer extends StatefulWidget {
  final List<ExportedMediaItem> items;
  final int initialIndex;
  final Function(ExportedMediaItem item, Uint8List imageBytes)? onOpenWatermark;
  final Function(ExportedMediaItem item)? onDelete;

  const FullScreenLocalImageViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    this.onOpenWatermark,
    this.onDelete,
  });

  @override
  State<FullScreenLocalImageViewer> createState() => _FullScreenLocalImageViewerState();
}

class _FullScreenLocalImageViewerState extends State<FullScreenLocalImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 去调色：读取本地原图并进入水印工坊调色
  Future<void> _handleOpenFilter(ExportedMediaItem item) async {
    try {
      final bytes = await item.file.readAsBytes();
      if (mounted) {
        Navigator.pop(context);
        widget.onOpenWatermark?.call(item, bytes);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: const Center(child: Text('暂无照片', style: TextStyle(color: Colors.white70))),
      );
    }

    final curItem = widget.items[_currentIndex.clamp(0, widget.items.length - 1)];
    final totalCount = widget.items.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 纯黑底全屏滑动预览 (最基础看图，无模糊背景与信息卡)
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: totalCount,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return Center(
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.5,
                    child: Image.file(
                      item.file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38, size: 64),
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. 顶部编号/总编号
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12, width: 0.8),
                ),
                child: Text(
                  '${_currentIndex + 1} / $totalCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),

          // 3. 底部控制条：退出 + 去调色
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2028).withAlpha(220),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12, width: 0.8),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _handleOpenFilter(curItem),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: SnapColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.palette_outlined, color: Colors.black, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '调色',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
