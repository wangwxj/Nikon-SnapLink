import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/utils/exif_helper.dart';
import '../../engine/liveview/liveview_controller.dart';
import '../../engine/transfer/download_manager.dart';
import '../../engine/transfer/shoot_and_transfer.dart';
import '../../engine/update/app_update_manager.dart';
import '../../protocol/nikon_driver.dart';
import 'screens/connect_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/liveview_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/watermark_screen.dart';

/// SnapLink 主界面导航框架 (底部 Vant Tabbar)
class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _currentIndex = 0;

  late final NikonDriver _driver;
  late final LiveViewController _liveViewController;
  late final DownloadManager _downloadManager;
  late final ShootAndTransferController _shootAndTransferController;
  final GlobalKey<GalleryScreenState> _galleryKey = GlobalKey<GalleryScreenState>();
  final GlobalKey<WatermarkScreenState> _watermarkKey = GlobalKey<WatermarkScreenState>();

  @override
  void initState() {
    super.initState();
    _driver = NikonDriver();
    _liveViewController = LiveViewController(driver: _driver);
    _downloadManager = DownloadManager(driver: _driver);
    _shootAndTransferController = ShootAndTransferController(
      driver: _driver,
      downloadManager: _downloadManager,
    );

    // 应用启动静默检测是否有远程新版本 (优先 Gitee 源)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateManager.checkOnStartup(context);
      }
    });
  }

  @override
  void dispose() {
    _shootAndTransferController.dispose();
    _liveViewController.dispose();
    _driver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ConnectScreen(
        driver: _driver,
        onConnected: () {
          // 连接成功后静默刷新相册，保留在连接主页展示连接就绪状态，对齐用户指令
          _galleryKey.currentState?.reloadFiles();
        },
        onNavigateToLiveView: () {
          // 仅跳转取景页，不自动拉流：由用户在取景页点击「启动取景监看」后才触发相机取景
          setState(() => _currentIndex = 1);
        },
        onNavigateToGallery: () {
          _galleryKey.currentState?.reloadFilesIfEmpty();
          setState(() => _currentIndex = 2);
        },
      ),
      LiveViewScreen(
        controller: _liveViewController,
        onNavigateToGallery: () {
          _liveViewController.stopStream();
          _galleryKey.currentState?.reloadFilesIfEmpty();
          setState(() => _currentIndex = 2);
        },
        onBack: () {
          _liveViewController.stopStream();
          setState(() => _currentIndex = 0);
        },
      ),
      GalleryScreen(
        key: _galleryKey,
        driver: _driver,
        downloadManager: _downloadManager,
        shootAndTransferController: _shootAndTransferController,
        onOpenWatermark: (file, cachedBytes, {bool openFilter = false}) async {
          setState(() => _currentIndex = 3);
          if (openFilter) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _watermarkKey.currentState?.showFilterTab();
            });
          }

          void inject(Uint8List b) {
            final fallbackMeta = PhotoMetadata(
              cameraModel: _driver.cameraModel.isNotEmpty ? _driver.cameraModel : 'Z 30',
              capturedDate: file.captureDate.isNotEmpty ? file.captureDate : '',
            );
            if (_watermarkKey.currentState != null) {
              _watermarkKey.currentState!.loadImageBytes(b, fallbackMeta);
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _watermarkKey.currentState?.loadImageBytes(b, fallbackMeta);
              });
            }
          }

          if (cachedBytes != null && cachedBytes.isNotEmpty) {
            inject(cachedBytes);
          } else {
            try {
              final bytes = await _driver.getThumbnail(file.handle);
              if (bytes.isNotEmpty) {
                inject(bytes);
              }
            } catch (_) {}
          }
        },
      ),
      WatermarkScreen(key: _watermarkKey),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (_currentIndex == 1 && index != 1) {
            // 离开实时取景页面：自动暂停取景拉流并释放相机传感器，保障媒体库浏览与下载通道畅通
            _liveViewController.stopStream();
          }
          // 进入取景页不自动拉流：仅当用户在取景页内点击「启动取景监看」才开启

          if (index == 2 && _driver.isConnected) {
            // 切换至相册时，若为空自动加载
            _galleryKey.currentState?.reloadFilesIfEmpty();
          }

          setState(() => _currentIndex = index);
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.wifi_tethering),
            activeIcon: Icon(Icons.wifi_tethering, color: SnapColors.primary),
            label: '连接',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam_outlined),
            activeIcon: Icon(Icons.videocam, color: SnapColors.primary),
            label: '监看取景',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library_outlined),
            activeIcon: Icon(Icons.photo_library, color: SnapColors.primary),
            label: '相机相册',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.branding_watermark_outlined),
            activeIcon: Icon(Icons.branding_watermark, color: SnapColors.primary),
            label: '水印工坊',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune_outlined),
            activeIcon: Icon(Icons.tune, color: SnapColors.primary),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
