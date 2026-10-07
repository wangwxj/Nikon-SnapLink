import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 已导出到本地相册的文件模型
class ExportedMediaItem {
  final File file;
  final String fileName;
  final String baseName;
  final int size;
  final DateTime modifiedTime;

  ExportedMediaItem({
    required this.file,
    required this.fileName,
    required this.baseName,
    required this.size,
    required this.modifiedTime,
  });

  bool get isJpeg {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg');
  }

  bool get isRaw {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.nef') || lower.endsWith('.nrw');
  }

  bool get isVideo {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.mov') || lower.endsWith('.mp4');
  }

  bool get isPng => fileName.toLowerCase().endsWith('.png');

  String get formatBadge {
    if (isRaw) return 'RAW';
    if (isVideo) return 'VIDEO';
    if (isPng) return 'PNG';
    return 'JPG';
  }

  String get sizeFormatted {
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(size / 1024).toStringAsFixed(0)} KB';
    }
  }

  String get dateFormatted {
    return '${modifiedTime.year}.${_twoDigits(modifiedTime.month)}.${_twoDigits(modifiedTime.day)} '
        '${_twoDigits(modifiedTime.hour)}:${_twoDigits(modifiedTime.minute)}';
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');
}

/// 手机本地已导出照片历史记录管理器
class ExportHistoryManager extends ChangeNotifier {
  static final ExportHistoryManager _instance = ExportHistoryManager._internal();
  factory ExportHistoryManager() => _instance;
  ExportHistoryManager._internal();

  List<ExportedMediaItem> _exportedItems = [];
  final Set<String> _exportedBaseNames = {};
  bool _isLoading = false;

  List<ExportedMediaItem> get items => List.unmodifiable(_exportedItems);
  Set<String> get exportedBaseNames => Set.unmodifiable(_exportedBaseNames);
  bool get isLoading => _isLoading;
  int get count => _exportedItems.length;

  /// 判断指定照片（或其基础名）是否已导出到本地
  bool isExported(String baseName) {
    final clean = _cleanBaseName(baseName);
    return _exportedBaseNames.contains(clean);
  }

  /// 根据文件名或基础名查找本地已导出的媒体项
  ExportedMediaItem? findExportedItem(String fileName) {
    final clean = _cleanBaseName(fileName);
    for (final item in _exportedItems) {
      if (item.baseName == clean || _cleanBaseName(item.fileName) == clean) {
        return item;
      }
    }
    return null;
  }

  /// 归一化提取文件名主干 (如 DSC_0001.JPG -> DSC_0001)
  static String _cleanBaseName(String name) {
    var s = name;
    final dotIdx = s.lastIndexOf('.');
    if (dotIdx > 0) {
      s = s.substring(0, dotIdx);
    }
    return s.toUpperCase().trim();
  }

  /// 扫描手机系统相册与下载目录，刷新已导出列表
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    final foundItems = <ExportedMediaItem>[];
    final foundBaseNames = <String>{};

    try {
      final targetDirs = <Directory>[
        Directory('/storage/emulated/0/DCIM/SnapLink'),
        Directory('/storage/emulated/0/Pictures/SnapLink'),
      ];

      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) targetDirs.add(extDir);
      } catch (_) {}

      try {
        final docDir = await getApplicationDocumentsDirectory();
        targetDirs.add(Directory('${docDir.path}/DCIM/SnapLink'));
        targetDirs.add(Directory('${docDir.path}/Pictures/SnapLink'));
        targetDirs.add(docDir);
      } catch (_) {}

      final seenPaths = <String>{};

      for (final dir in targetDirs) {
        if (!await dir.exists()) continue;

        try {
          final entries = dir.listSync(followLinks: false);
          for (final entry in entries) {
            if (entry is File) {
              final path = entry.path;
              if (seenPaths.contains(path)) continue;

              final name = entry.uri.pathSegments.last;
              final lower = name.toLowerCase();

              // 支持照片、视频与水印导出图
              if (lower.endsWith('.jpg') ||
                  lower.endsWith('.jpeg') ||
                  lower.endsWith('.png') ||
                  lower.endsWith('.nef') ||
                  lower.endsWith('.nrw') ||
                  lower.endsWith('.mov') ||
                  lower.endsWith('.mp4')) {
                seenPaths.add(path);
                final stat = await entry.stat();
                final base = _cleanBaseName(name);

                foundItems.add(ExportedMediaItem(
                  file: entry,
                  fileName: name,
                  baseName: base,
                  size: stat.size,
                  modifiedTime: stat.modified,
                ));
                foundBaseNames.add(base);
              }
            }
          }
        } catch (_) {}
      }

      // 按修改时间降序 (最新的在最前)
      foundItems.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    } catch (_) {}

    _exportedItems = foundItems;
    _exportedBaseNames.clear();
    _exportedBaseNames.addAll(foundBaseNames);
    _isLoading = false;
    notifyListeners();
  }

  /// 当下载或导出单张新照片时快速注册
  void registerExported(String fileName, [File? file]) {
    final base = _cleanBaseName(fileName);
    _exportedBaseNames.add(base);
    if (file != null && file.existsSync()) {
      final stat = file.statSync();
      _exportedItems.insert(
        0,
        ExportedMediaItem(
          file: file,
          fileName: fileName,
          baseName: base,
          size: stat.size,
          modifiedTime: stat.modified,
        ),
      );
    }
    notifyListeners();
  }

  /// 删除某张已导出照片
  Future<bool> deleteItem(ExportedMediaItem item) async {
    try {
      if (await item.file.exists()) {
        await item.file.delete();
      }
      _exportedItems.remove(item);
      // 重新评估 baseName 是否还有同组其他文件
      final hasSameBase = _exportedItems.any((e) => e.baseName == item.baseName);
      if (!hasSameBase) {
        _exportedBaseNames.remove(item.baseName);
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
