import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/colors.dart';
import '../../engine/liveview/liveview_controller.dart';
import '../../engine/liveview/monitor_overlay.dart';
import '../../protocol/camera_driver.dart';
import '../../protocol/nikon_liveview_parser.dart';

/// 无线相机画面实时传输与专业监看监视器 (LiveView Monitor)
/// 支持横屏全屏导演监看、曝光与镜头参数 HUD、对焦框与电子水平仪渲染
class LiveViewScreen extends StatefulWidget {
  final LiveViewController controller;
  final VoidCallback? onNavigateToGallery;
  final VoidCallback? onBack;

  const LiveViewScreen({
    super.key,
    required this.controller,
    this.onNavigateToGallery,
    this.onBack,
  });

  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  bool _isTriggering = false;
  Offset? _lastTapPosition;
  double _lastScale = 1.0;
  bool _isScaling = false;
  bool _isLandscape = false;

  int _liveSeconds = 0;
  Timer? _liveTimer;
  bool _trackingAf = false;
  String _meteringMode = '亮部重点';
  String _controlMode = '远控模式';
  bool _zebra = false;
  bool _lut = false;
  bool _falseColor = false;
  bool _peaking = false;
  bool _mirror = false;
  String _wb = '自动';
  String _viewMode = '照片';
  bool _isPhotoAf = false;
  bool _isVideoAf = false;

  @override
  void initState() {
    super.initState();
    // 不自动拉流：连接成功也仅停留在「点击下方开启」状态，
    // 只有用户在本页点击「启动取景监看」才会让相机进入取景画面
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.isStreaming) {
        setState(() => _liveSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _toggleLandscape() {
    setState(() {
      _isLandscape = !_isLandscape;
    });
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  void _handleZoomPulse(bool isTele) {
    // 未开启取景流时不向相机发送变焦指令
    if (!widget.controller.isStreaming) return;
    widget.controller.pulseZoom(isTele: isTele, durationMs: 320);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isTele ? '🔍 长焦短脉冲变焦 (TELE 320ms)' : '🔍 广角短脉冲变焦 (WIDE 320ms)'),
          duration: const Duration(milliseconds: 600),
          backgroundColor: SnapColors.cardElevated,
        ),
      );
    }
  }

  Future<void> _handleShutter() async {
    if (_isTriggering || !widget.controller.driver.isConnected) return;
    setState(() => _isTriggering = true);
    try {
      await widget.controller.driver.triggerShutter();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📸 拍照指令已发送 (Nikon_CaptureToCard)'),
            duration: Duration(milliseconds: 1000),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  Future<void> _handleAutofocus() async {
    await widget.controller.driver.autofocus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎯 自动对焦 (Nikon_AfDrive)'),
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final isConnected = widget.controller.driver.isConnected;
        final frame = widget.controller.latestFrame;
        final params = widget.controller.exposureParams;
        final isHorizontal = _isLandscape || MediaQuery.of(context).orientation == Orientation.landscape;

        if (isHorizontal) {
          return _buildLandscapeView(context, isConnected, frame, params);
        } else {
          return _buildPortraitView(context, isConnected, frame, params);
        }
      },
    );
  }

  // ==========================================
  // 1. 竖屏监看模式布局 (高保真对齐 media_1791281187023.jpg)
  // ==========================================
  Widget _buildPortraitView(
    BuildContext context,
    bool isConnected,
    Uint8List? frame,
    CameraExposureParams params,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. 顶部状态栏: ← 返回 | ● 相机已连接 Z | 25.5 FPS (实时) | 00:00:00 (LIVE) | 100% (电量)
            _buildTopHeaderBar(params),

            // 2. 顶部 RGB 直方图卡片 (对齐 media_1791281187023.jpg)
            _buildTopHistogramCard(),

            // 3. 核心取景框 (包含左侧垂直 EV 刻度阶梯标尺、3x3 构图网格、中心对焦框、以及底部 HUD 药丸 [⛶ 1x] & [P 模式 | 1/80 快门 | 3200 ISO | F4.5 光圈])
            Expanded(
              child: _buildPortraitViewport(context, isConnected, frame, params),
            ),

            const SizedBox(height: 4),

            // 4. 2x5 核心曝光参数矩阵 (点击弹出专业平滑滑块调节抽屉)
            _buildParamMatrix2x5(params, isConnected),

            const SizedBox(height: 5),

            // 5. 2x5 专业监看工具网格 (自动对焦、追踪对焦、测光模式、控制模式、网格、斑马纹、LUT、伪色彩、峰值辅助、镜像)
            _buildMonitoringTools2x5(),

            // 6. 底部快门 Dock (左: 🖼 图库, 中: 巨型白圆双环快门释放键, 右: ⚙ 设置)
            _buildBottomShutterDock(isConnected),
          ],
        ),
      ),
    );
  }

  /// 顶部相机状态栏 (对齐 media_1791281187023.jpg)
  Widget _buildTopHeaderBar(CameraExposureParams params) {
    final fps = widget.controller.currentFps;
    final battery = params.batteryLevel > 0 ? '${params.batteryLevel}%' : '100%';
    final durationStr = _formatDuration(_liveSeconds);

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              if (widget.onBack != null) {
                widget.onBack!();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 10),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF4CAF50),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '相机已连接',
            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Text(
            widget.controller.driver.cameraModel.contains('Z') ? 'Z' : '',
            style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic),
          ),

          // 右侧状态组：窄屏自动等比缩放，避免 Row 溢出
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // FPS 实时
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${fps > 0 ? fps.toStringAsFixed(1) : "25.5"} FPS',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                      const Text('实时', style: TextStyle(color: Colors.white54, fontSize: 9)),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // LIVE 时长
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        durationStr,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                      const Text('LIVE', style: TextStyle(color: Colors.white54, fontSize: 9)),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // 电量
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        battery,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                      const Text('电量', style: TextStyle(color: Colors.white54, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部 RGB 曲线直方图卡片 (对齐 media_1791281187023.jpg)
  Widget _buildTopHistogramCard() {
    return Container(
      height: 74,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF13141B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF262835), width: 0.8),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, 62),
        painter: RgbCurveHistogramPainter(bins: widget.controller.histogramBins),
      ),
    );
  }

  /// 竖屏取景器画面构建器 (对齐 media_1791281187023.jpg)
  Widget _buildPortraitViewport(
    BuildContext context,
    bool isConnected,
    Uint8List? frame,
    CameraExposureParams params,
  ) {
    return Container(
      key: const ValueKey('liveviewViewport'),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF222432), width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 实时取景画面
          _buildViewport(context, isConnected, frame, isLandscape: false),

          // 左侧垂直 EV 曝光补偿标尺 —— 仅取景开启后显示
          if (widget.controller.isStreaming)
            Positioned(
              left: 8,
              top: 24,
              bottom: 48,
              child: _buildEvLadderScale(params),
            ),

          // 中心对焦框 (白框) —— 仅取景开启后显示
          if (widget.controller.isStreaming)
            Center(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withAlpha(220), width: 1.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

          // 底部两组 HUD 药丸 (对标 media_1791281187023.jpg: [⛶ 1x] 与 [P 模式 | 1/80 快门 | 3200 ISO | F4.5 光圈])
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Row(
              children: [
                // 变焦胶囊 [⛶ 1x]
                GestureDetector(
                  onTap: () => _handleZoomPulse(true),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xCC181A22),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: Colors.white12, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.crop_free, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '1x',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 核心四参数药丸
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xCC181A22),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: Colors.white12, width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildHudParamColumn(params.programMode, '模式'),
                        _buildHudParamColumn(params.shutterSpeed, '快门'),
                        _buildHudParamColumn(params.iso.replaceAll('ISO ', ''), 'ISO'),
                        _buildHudParamColumn(params.aperture.replaceAll('f/', 'F'), '光圈'),
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

  Widget _buildHudParamColumn(String value, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 8),
        ),
      ],
    );
  }

  /// 左侧垂直 EV 曝光补偿标尺 (对齐 media_1791281187023.jpg)
  Widget _buildEvLadderScale(CameraExposureParams params) {
    double curEv = 0.0;
    final cleanEv = params.exposureComp.replaceAll('EV', '').replaceAll('+', '').trim();
    curEv = double.tryParse(cleanEv) ?? 0.0;

    return GestureDetector(
      onTap: () => _showEvPicker(context, params.exposureComp),
      child: Container(
        width: 38,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: CustomPaint(
          size: const Size(38, 140),
          painter: EvLadderPainter(currentEv: curEv),
        ),
      ),
    );
  }

  /// 2x5 核心曝光参数矩阵 (对齐 media_1791281187023.jpg)
  Widget _buildParamMatrix2x5(CameraExposureParams params, bool isConnected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              _buildParamMatrixCard(
                value: _viewMode,
                label: '取景模式',
                onTap: () {
                  setState(() => _viewMode = _viewMode == '照片' ? '视频' : '照片');
                  _showParamToast('取景模式切换为 $_viewMode');
                },
              ),
              _buildParamMatrixCard(
                value: params.shutterSpeed,
                badge: 'AUTO',
                label: '快门',
                onTap: isConnected ? () => _showShutterSpeedPicker(context, params.shutterSpeed) : null,
              ),
              _buildParamMatrixCard(
                value: params.aperture.replaceAll('f/', 'F'),
                badge: 'AUTO',
                label: '光圈',
                onTap: isConnected ? () => _showAperturePicker(context, params.aperture) : null,
              ),
              _buildParamMatrixCard(
                value: params.iso.replaceAll('ISO ', ''),
                label: 'ISO',
                onTap: isConnected ? () => _showIsoPicker(context, params.iso) : null,
              ),
              _buildParamMatrixCard(
                value: _wb,
                label: '白平衡',
                onTap: isConnected ? () => _showWbPicker(context, _wb) : null,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _buildParamMatrixCard(
                value: params.exposureComp,
                label: '曝光补偿',
                onTap: isConnected ? () => _showEvPicker(context, params.exposureComp) : null,
              ),
              _buildParamMatrixCard(
                value: params.programMode,
                label: '模式',
                onTap: isConnected ? () => _showExposureModePicker(context, params.programMode) : null,
              ),
              _buildParamMatrixCard(
                value: _isPhotoAf ? 'AF' : 'MF',
                label: '照片对焦',
                onTap: () {
                  setState(() => _isPhotoAf = !_isPhotoAf);
                  _showParamToast('照片对焦切换为 ${_isPhotoAf ? "AF" : "MF"}');
                },
              ),
              _buildParamMatrixCard(
                value: _isVideoAf ? 'AF' : 'MF',
                label: '视频对焦',
                onTap: () {
                  setState(() => _isVideoAf = !_isVideoAf);
                  _showParamToast('视频对焦切换为 ${_isVideoAf ? "AF" : "MF"}');
                },
              ),
              _buildParamMatrixCard(
                value: '刷新',
                label: '曝光参数',
                onTap: () {
                  widget.controller.refreshExposureParams();
                  _showParamToast('正在刷新相机参数...');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParamMatrixCard({
    required String value,
    String? badge,
    required String label,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF14151C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF222430), width: 0.8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(color: Colors.black, fontSize: 7, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 8.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2x5 专业监看工具网格 (对齐 media_1791281187023.jpg)
  Widget _buildMonitoringTools2x5() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              _buildToolCard(
                icon: Icons.filter_center_focus,
                label: '自动对焦 · AF',
                onTap: _handleAutofocus,
              ),
              _buildToolCard(
                icon: Icons.radar,
                label: '追踪对焦 · ${_trackingAf ? "开" : "关"}',
                active: _trackingAf,
                onTap: () {
                  setState(() => _trackingAf = !_trackingAf);
                  _showParamToast('追踪对焦: ${_trackingAf ? "开启" : "关闭"}');
                },
              ),
              _buildToolCard(
                icon: Icons.brightness_medium,
                label: '测光 · $_meteringMode',
                onTap: () {
                  setState(() {
                    _meteringMode = _meteringMode == '亮部重点' ? '矩阵测光' : (_meteringMode == '矩阵测光' ? '中央重点' : '亮部重点');
                  });
                  _showParamToast('测光模式已切换为 $_meteringMode');
                },
              ),
              _buildToolCard(
                icon: Icons.settings_remote,
                label: '控制 · $_controlMode',
                onTap: () {
                  setState(() {
                    _controlMode = _controlMode == '远控模式' ? '监视模式' : '远控模式';
                  });
                  _showParamToast('控制模式切换为 $_controlMode');
                },
              ),
              _buildToolCard(
                icon: Icons.grid_on,
                label: '网格 · ${widget.controller.showGrid ? "开" : "关"}',
                active: widget.controller.showGrid,
                onTap: widget.controller.toggleGrid,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _buildToolCard(
                icon: Icons.texture,
                label: '斑马纹 · ${_zebra ? "开" : "关"}',
                active: _zebra,
                onTap: () {
                  setState(() => _zebra = !_zebra);
                  _showParamToast('斑马纹辅助: ${_zebra ? "开启" : "关闭"}');
                },
              ),
              _buildToolCard(
                icon: Icons.palette,
                label: 'LUT · ${_lut ? "开" : "关"}',
                active: _lut,
                onTap: () {
                  setState(() => _lut = !_lut);
                  _showParamToast('电影级 LUT 监看: ${_lut ? "开启" : "关闭"}');
                },
              ),
              _buildToolCard(
                icon: Icons.grid_view,
                label: '伪色彩 · ${_falseColor ? "开" : "关"}',
                active: _falseColor,
                onTap: () {
                  setState(() => _falseColor = !_falseColor);
                  _showParamToast('伪色彩曝光监看: ${_falseColor ? "开启" : "关闭"}');
                },
              ),
              _buildToolCard(
                icon: Icons.crop_free,
                label: '峰值辅助 · ${_peaking ? "开" : "关"}',
                active: _peaking,
                onTap: () {
                  setState(() => _peaking = !_peaking);
                  _showParamToast('对焦峰值辅助: ${_peaking ? "开启" : "关闭"}');
                },
              ),
              _buildToolCard(
                icon: Icons.flip,
                label: '镜像 · ${_mirror ? "开" : "关"}',
                active: _mirror,
                onTap: () {
                  setState(() => _mirror = !_mirror);
                  _showParamToast('画面水平镜像: ${_mirror ? "开启" : "关闭"}');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard({
    required IconData icon,
    required String label,
    bool active = false,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF14151C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? const Color(0xFFFF9800) : const Color(0xFF222430),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? const Color(0xFFFF9800) : Colors.white70,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: active ? const Color(0xFFFF9800) : Colors.white60,
                  fontSize: 7.5,
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

  /// 底部快门 Dock (对齐 media_1791281187023.jpg)
  Widget _buildBottomShutterDock(bool isConnected) {
    return Container(
      height: 86,
      padding: EdgeInsets.only(
        left: 36,
        right: 36,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧：图库入口
          InkWell(
            onTap: () {
              if (widget.onNavigateToGallery != null) {
                widget.onNavigateToGallery!();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, size: 24, color: Colors.white),
                  SizedBox(height: 3),
                  Text('图库', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),

          // 居中：巨型白圆双环快门 (对齐 media_1791281187023.jpg)
          GestureDetector(
            onTap: isConnected ? _handleShutter : null,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3.5),
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isTriggering ? SnapColors.primary : Colors.white,
                ),
              ),
            ),
          ),

          // 右侧：设置入口
          InkWell(
            onTap: _showSettingsModal,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_outlined, size: 24, color: Colors.white),
                  SizedBox(height: 3),
                  Text('设置', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161720),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '监看与相机设置',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const ListTile(
                  leading: Icon(Icons.high_quality, color: SnapColors.primary),
                  title: Text('实时流分辨率', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('自适应高清硬件流 (640x424 @ 30FPS)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: Icon(Icons.check, color: SnapColors.primary, size: 20),
                ),
                const ListTile(
                  leading: Icon(Icons.speed, color: SnapColors.primary),
                  title: Text('电动变焦步进驱动', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('短脉冲 320ms / 连续变焦速度 5 级', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
                ListTile(
                  leading: const Icon(Icons.battery_charging_full, color: SnapColors.success),
                  title: const Text('低电量智能保护', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('相机电量低于 15% 时暂停大负荷传输与拉流', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: Switch(
                    value: true,
                    activeThumbColor: SnapColors.primary,
                    onChanged: (v) {},
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showExposureModePicker(BuildContext context, String currentVal) {
    const modes = ['P (程序自动)', 'S (快门优先)', 'A (光圈优先)', 'M (手动曝光)'];
    _showPickerModal(
      title: '调节拍摄模式 (Mode)',
      icon: Icons.camera_alt,
      items: modes,
      currentValue: currentVal,
      onSelected: (val) {
        _showParamToast('模式已切换为 $val');
      },
    );
  }

  void _showWbPicker(BuildContext context, String currentVal) {
    const wbs = ['自动 (Auto)', '日光 (Daylight)', '阴天 (Cloudy)', '阴影 (Shade)', '白炽灯 (Incandescent)', '荧光灯 (Fluorescent)', '色温 (K)'];
    _showPickerModal(
      title: '调节白平衡 (White Balance)',
      icon: Icons.wb_sunny,
      items: wbs,
      currentValue: currentVal,
      onSelected: (val) {
        setState(() => _wb = val.split(' ')[0]);
        _showParamToast('白平衡已设为 $val');
      },
    );
  }

  String _formatDuration(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ==========================================
  // 2. 横屏专业全屏监看模式布局 (Field Monitor)
  // ==========================================
  Widget _buildLandscapeView(
    BuildContext context,
    bool isConnected,
    Uint8List? frame,
    CameraExposureParams params,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 主画面 (全屏居中)
            Positioned.fill(
              child: _buildViewport(context, isConnected, frame, isLandscape: true),
            ),

            // 顶部半透明专业监看 HUD (机型、镜头、快门、光圈、ISO、EV、模式、帧率、电量)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(220),
                      Colors.black.withAlpha(120),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // 相机与镜头标识
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SnapColors.primary.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SnapColors.primary.withAlpha(120), width: 0.8),
                      ),
                      child: Text(
                        widget.controller.driver.cameraModel,
                        style: const TextStyle(color: SnapColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (params.lensInfo != '--' || params.focalLength != '--')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          params.lensInfo != '--' ? params.lensInfo : params.focalLength,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    // 右侧参数组：空间不足时整体等比缩放，防止横屏窄宽度溢出
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 曝光参数组
                            _buildLandscapeParamBadge('MODE', params.programMode),
                            const SizedBox(width: 6),
                            _buildLandscapeParamBadge('SS', params.shutterSpeed, onTap: isConnected ? () => _showShutterSpeedPicker(context, params.shutterSpeed) : null),
                            const SizedBox(width: 6),
                            _buildLandscapeParamBadge('F', params.aperture, onTap: isConnected ? () => _showAperturePicker(context, params.aperture) : null),
                            const SizedBox(width: 6),
                            _buildLandscapeParamBadge('ISO', params.iso, onTap: isConnected ? () => _showIsoPicker(context, params.iso) : null),
                            const SizedBox(width: 6),
                            _buildLandscapeParamBadge('EV', params.exposureComp, onTap: isConnected ? () => _showEvPicker(context, params.exposureComp) : null),
                            const SizedBox(width: 10),

                            // FPS & 电池
                            Text(
                              '${widget.controller.currentFps} FPS',
                              style: const TextStyle(color: SnapColors.primary, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              children: [
                                const Icon(Icons.battery_charging_full, size: 14, color: SnapColors.success),
                                const SizedBox(width: 2),
                                Text(
                                  '${params.batteryLevel}%',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 横屏直方图 (左上角浮动)
            if (widget.controller.showHistogram)
              Positioned(
                top: 50,
                left: 16,
                child: HistogramWidget(values: widget.controller.histogramBins),
              ),

            // 右侧悬浮控制栏 (快门、AF、变焦、辅助图层、退出横屏)
            Positioned(
              right: 12,
              top: 46,
              bottom: 10,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 退出横屏按钮
                  _buildLandscapeSideBtn(
                    icon: Icons.fullscreen_exit,
                    tooltip: '退出横屏',
                    onTap: _toggleLandscape,
                  ),
                  const SizedBox(height: 6),

                  // 刷新曝光参数
                  _buildLandscapeSideBtn(
                    icon: Icons.refresh,
                    tooltip: '刷新参数',
                    onTap: () => widget.controller.refreshExposureParams(),
                  ),
                  const SizedBox(height: 6),

                  // 构图线
                  _buildLandscapeSideBtn(
                    icon: Icons.grid_on,
                    active: widget.controller.showGrid,
                    tooltip: '构图三分线',
                    onTap: widget.controller.toggleGrid,
                  ),
                  const SizedBox(height: 6),

                  // 直方图
                  _buildLandscapeSideBtn(
                    icon: Icons.bar_chart,
                    active: widget.controller.showHistogram,
                    tooltip: '直方图',
                    onTap: widget.controller.toggleHistogram,
                  ),
                  const SizedBox(height: 8),

                  // AF 按钮
                  _buildLandscapeSideBtn(
                    icon: Icons.center_focus_strong,
                    color: SnapColors.primary,
                    tooltip: '自动对焦',
                    onTap: isConnected ? _handleAutofocus : () {},
                  ),
                  const SizedBox(height: 8),

                  // 尼康金圈大快门
                  GestureDetector(
                    onTap: isConnected ? _handleShutter : null,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                        border: Border.all(color: SnapColors.primary, width: 2.5),
                        boxShadow: const [BoxShadow(color: Color(0xDD000000), blurRadius: 8)],
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isTriggering ? SnapColors.primaryDark : SnapColors.primary,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.black, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 左下角 PZ 电动变焦悬浮条 (横屏模式)
            if (isConnected)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(190),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _handleZoomPulse(false),
                        onLongPressStart: (_) => widget.controller.startDriveZoom(isTele: false, speed: 5),
                        onLongPressEnd: (_) => widget.controller.stopDriveZoom(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.zoom_out, size: 14, color: SnapColors.primary),
                              SizedBox(width: 4),
                              Text('WIDE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _handleZoomPulse(true),
                        onLongPressStart: (_) => widget.controller.startDriveZoom(isTele: true, speed: 5),
                        onLongPressEnd: (_) => widget.controller.stopDriveZoom(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Text('TELE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              SizedBox(width: 4),
                              Icon(Icons.zoom_in, size: 14, color: SnapColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 取景主画面视图构建器 (手势交互与图层叠加)
  // ==========================================
  Widget _buildViewport(
    BuildContext context,
    bool isConnected,
    Uint8List? frame, {
    required bool isLandscape,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final streaming = widget.controller.isStreaming;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            // 仅在取景流运行中才触发自动对焦，避免未开流时点击按钮/占位被抢走
            if (isConnected && streaming) _handleAutofocus();
          },
          onDoubleTapDown: (details) {
            _lastTapPosition = details.localPosition;
          },
          onDoubleTap: () {
            if (!isConnected || !streaming) return;
            final pos = _lastTapPosition;
            if (pos != null) {
              final isRightHalf = pos.dx > screenWidth / 2;
              _handleZoomPulse(isRightHalf);
            }
          },
          onScaleStart: (details) {
            if (details.pointerCount >= 2) {
              _isScaling = true;
              _lastScale = 1.0;
            }
          },
          onScaleUpdate: (details) {
            if (!_isScaling || !isConnected || !streaming || details.pointerCount < 2) return;
            if (details.scale > 1.06 && _lastScale <= 1.06) {
              widget.controller.startDriveZoom(isTele: true, speed: 5);
              _lastScale = details.scale;
            } else if (details.scale < 0.94 && _lastScale >= 0.94) {
              widget.controller.startDriveZoom(isTele: false, speed: 5);
              _lastScale = details.scale;
            }
          },
          onScaleEnd: (details) {
            if (_isScaling) {
              _isScaling = false;
              _lastScale = 1.0;
              widget.controller.stopDriveZoom();
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 底层视频/取景画面 (智能解码防崩)
              if (frame != null && frame.isNotEmpty)
                // RepaintBoundary 隔离高频取景帧重绘，避免每帧重建整页 HUD
                RepaintBoundary(
                  child: Image.memory(
                  frame,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (ctx, err, stack) {
                    return Container(
                      color: const Color(0xFF0D0D10),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync, size: 36, color: SnapColors.primary),
                            SizedBox(height: 8),
                            Text('正在解析取景帧数据...', style: TextStyle(color: SnapColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                )
              else
                Container(
                  color: const Color(0xFF0D0D10),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isConnected ? Icons.videocam_outlined : Icons.link_off,
                          size: 48,
                          color: SnapColors.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isConnected
                              ? (widget.controller.isStreaming ? '正在缓冲实时取景硬件流...' : '实时取景已就绪，点击下方开启')
                              : '请先在「连接」页面连入相机 Wi-Fi',
                          style: const TextStyle(color: SnapColors.textSecondary, fontSize: 13),
                        ),
                        if (isConnected && !widget.controller.isStreaming) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => widget.controller.startStream(),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('启动取景监看'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SnapColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // 监看辅助图层 (构图线、准星、硬件对焦框与电子水平仪) —— 仅取景开启后显示
              if (streaming)
                Positioned.fill(
                  child: CustomPaint(
                    painter: MonitorOverlayPainter(
                      showGrid: widget.controller.showGrid,
                      showCrosshair: widget.controller.showFocusCross,
                      showSafeArea: false,
                      afBoxes: widget.controller.latestParsedFrame?.afBoxes,
                      focusState: widget.controller.latestParsedFrame?.focusState ?? NikonFocusState.unknown,
                      levelInfo: widget.controller.latestParsedFrame?.levelInfo,
                      wholeWidth: widget.controller.latestParsedFrame?.wholeWidth ?? 640,
                      wholeHeight: widget.controller.latestParsedFrame?.wholeHeight ?? 424,
                    ),
                  ),
                ),

              // 竖屏右侧垂直工具栏 (顶部 RGB 直方图卡片为唯一直方图，框内不再叠加第二个)
              if (!isLandscape && streaming)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      _buildQuickToolIcon(
                        icon: Icons.screen_rotation,
                        active: false,
                        tooltip: '全屏横屏监看',
                        onTap: _toggleLandscape,
                      ),
                      const SizedBox(height: 8),
                      _buildQuickToolIcon(
                        icon: Icons.grid_on,
                        active: widget.controller.showGrid,
                        tooltip: '构图三分线',
                        onTap: widget.controller.toggleGrid,
                      ),
                      const SizedBox(height: 8),
                      _buildQuickToolIcon(
                        icon: Icons.refresh,
                        active: false,
                        tooltip: '刷新相机参数',
                        onTap: () => widget.controller.refreshExposureParams(),
                      ),
                    ],
                  ),
                ),

              // 变焦驱动实时浮动指示器 (HUD Overlay)
              if (widget.controller.zoomActiveDirection != null)
                Positioned(
                  bottom: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(217),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: SnapColors.primary, width: 1.5),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.controller.zoomActiveDirection == 'TELE' ? Icons.zoom_in : Icons.zoom_out,
                          color: SnapColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.controller.zoomActiveDirection == 'TELE' ? '长焦 (TELE) 变焦驱动中' : '广角 (WIDE) 变焦驱动中',
                          style: const TextStyle(color: SnapColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // 组件辅助方法
  // ==========================================



  Widget _buildLandscapeParamBadge(String label, String value, {VoidCallback? onTap}) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: onTap != null ? SnapColors.primary.withAlpha(25) : Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: onTap != null ? SnapColors.primary.withAlpha(120) : Colors.white12,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(color: SnapColors.textTertiary, fontSize: 10)),
          Text(
            value,
            style: TextStyle(
              color: onTap != null ? SnapColors.primary : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 10, color: SnapColors.primary),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      child: content,
    );
  }

  // ------------------------------------
  // 专业曝光参数选择弹窗 (底抽屉/模态)
  // ------------------------------------

  void _showAperturePicker(BuildContext context, String currentVal) {
    const apertures = [
      1.2, 1.4, 1.8, 2.0, 2.2, 2.5, 2.8, 3.2, 3.5, 4.0, 4.5, 5.0, 5.6, 6.3, 7.1, 8.0, 9.0, 10.0, 11.0, 13.0, 14.0, 16.0, 18.0, 20.0, 22.0
    ];
    _showPickerModal(
      title: '调节光圈 (Aperture)',
      icon: Icons.camera,
      items: apertures.map((f) => 'f/${f.toStringAsFixed(1)}').toList(),
      currentValue: currentVal,
      onSelected: (val) {
        final parsed = double.tryParse(val.replaceAll('f/', ''));
        if (parsed != null) {
          widget.controller.setAperture(parsed);
          _showParamToast('光圈已设为 $val');
        }
      },
    );
  }

  void _showShutterSpeedPicker(BuildContext context, String currentVal) {
    const shutters = [
      {'label': '1/4000s', 'num': 1, 'den': 4000},
      {'label': '1/3200s', 'num': 1, 'den': 3200},
      {'label': '1/2500s', 'num': 1, 'den': 2500},
      {'label': '1/2000s', 'num': 1, 'den': 2000},
      {'label': '1/1600s', 'num': 1, 'den': 1600},
      {'label': '1/1250s', 'num': 1, 'den': 1250},
      {'label': '1/1000s', 'num': 1, 'den': 1000},
      {'label': '1/800s', 'num': 1, 'den': 800},
      {'label': '1/640s', 'num': 1, 'den': 640},
      {'label': '1/500s', 'num': 1, 'den': 500},
      {'label': '1/400s', 'num': 1, 'den': 400},
      {'label': '1/320s', 'num': 1, 'den': 320},
      {'label': '1/250s', 'num': 1, 'den': 250},
      {'label': '1/200s', 'num': 1, 'den': 200},
      {'label': '1/160s', 'num': 1, 'den': 160},
      {'label': '1/125s', 'num': 1, 'den': 125},
      {'label': '1/100s', 'num': 1, 'den': 100},
      {'label': '1/80s', 'num': 1, 'den': 80},
      {'label': '1/60s', 'num': 1, 'den': 60},
      {'label': '1/50s', 'num': 1, 'den': 50},
      {'label': '1/40s', 'num': 1, 'den': 40},
      {'label': '1/30s', 'num': 1, 'den': 30},
      {'label': '1/25s', 'num': 1, 'den': 25},
      {'label': '1/20s', 'num': 1, 'den': 20},
      {'label': '1/15s', 'num': 1, 'den': 15},
      {'label': '1/10s', 'num': 1, 'den': 10},
      {'label': '1/8s', 'num': 1, 'den': 8},
      {'label': '1/4s', 'num': 1, 'den': 4},
      {'label': '1/2s', 'num': 1, 'den': 2},
      {'label': '1"', 'num': 1, 'den': 1},
      {'label': '2"', 'num': 2, 'den': 1},
      {'label': '4"', 'num': 4, 'den': 1},
      {'label': '8"', 'num': 8, 'den': 1},
      {'label': '15"', 'num': 15, 'den': 1},
      {'label': '30"', 'num': 30, 'den': 1},
    ];
    _showPickerModal(
      title: '调节快门速度 (Shutter)',
      icon: Icons.shutter_speed,
      items: shutters.map((s) => s['label'] as String).toList(),
      currentValue: currentVal,
      onSelected: (val) {
        final match = shutters.firstWhere((s) => s['label'] == val, orElse: () => {});
        if (match.isNotEmpty) {
          widget.controller.setShutterSpeed(match['num'] as int, match['den'] as int);
          _showParamToast('快门速度已设为 $val');
        }
      },
    );
  }

  void _showIsoPicker(BuildContext context, String currentVal) {
    const isos = [
      64, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 25600, 51200
    ];
    _showPickerModal(
      title: '调节感光度 (ISO)',
      icon: Icons.iso,
      items: isos.map((i) => 'ISO $i').toList(),
      currentValue: currentVal,
      onSelected: (val) {
        final parsed = int.tryParse(val.replaceAll('ISO ', ''));
        if (parsed != null) {
          widget.controller.setIso(parsed);
          _showParamToast('感光度已设为 $val');
        }
      },
    );
  }

  void _showEvPicker(BuildContext context, String currentVal) {
    const evSteps = [
      {'label': '-3.0 EV', 'val': -3000},
      {'label': '-2.7 EV', 'val': -2667},
      {'label': '-2.3 EV', 'val': -2333},
      {'label': '-2.0 EV', 'val': -2000},
      {'label': '-1.7 EV', 'val': -1667},
      {'label': '-1.3 EV', 'val': -1333},
      {'label': '-1.0 EV', 'val': -1000},
      {'label': '-0.7 EV', 'val': -667},
      {'label': '-0.3 EV', 'val': -333},
      {'label': '±0.0 EV', 'val': 0},
      {'label': '+0.3 EV', 'val': 333},
      {'label': '+0.7 EV', 'val': 667},
      {'label': '+1.0 EV', 'val': 1000},
      {'label': '+1.3 EV', 'val': 1333},
      {'label': '+1.7 EV', 'val': 1667},
      {'label': '+2.0 EV', 'val': 2000},
      {'label': '+2.3 EV', 'val': 2333},
      {'label': '+2.7 EV', 'val': 2667},
      {'label': '+3.0 EV', 'val': 3000},
    ];
    _showPickerModal(
      title: '调节曝光补偿 (EV)',
      icon: Icons.exposure,
      items: evSteps.map((e) => e['label'] as String).toList(),
      currentValue: currentVal,
      onSelected: (val) {
        final match = evSteps.firstWhere((e) => e['label'] == val, orElse: () => {});
        if (match.isNotEmpty) {
          widget.controller.setExposureCompensation(match['val'] as int);
          _showParamToast('曝光补偿已设为 $val');
        }
      },
    );
  }

  void _showParamToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 900),
        backgroundColor: SnapColors.cardElevated,
      ),
    );
  }

  void _showPickerModal({
    required String title,
    required IconData icon,
    required List<String> items,
    required String currentValue,
    required void Function(String val) onSelected,
  }) {
    if (items.isEmpty) return;

    int initialIndex = items.indexWhere((val) => currentValOrClean(val, currentValue));
    if (initialIndex < 0) {
      initialIndex = (items.length / 2).floor();
    }

    int activeIndex = initialIndex;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final activeVal = items[activeIndex.clamp(0, items.length - 1)];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 顶部拖动条
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 标题与关闭按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: SnapColors.primary.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(icon, color: SnapColors.primary, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            foregroundColor: SnapColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          child: const Text('完成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 中央核心大数值看板 (对标专业相机转盘与高亮显示屏)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D2028),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: SnapColors.primary.withAlpha(60), width: 1.2),
                      ),
                      child: Column(
                        children: [
                          Text(
                            activeVal,
                            style: const TextStyle(
                              color: SnapColors.primary,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '刻度步进: ${activeIndex + 1} / ${items.length}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 滑块调节区域 ([-] 步进按钮 + Slider + [+] 步进按钮)
                    Row(
                      children: [
                        // [-] 微调按键
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          color: activeIndex > 0 ? Colors.white70 : Colors.white24,
                          iconSize: 28,
                          tooltip: '向前步进',
                          onPressed: activeIndex > 0
                              ? () {
                                  final newIdx = activeIndex - 1;
                                  setSheetState(() => activeIndex = newIdx);
                                  HapticFeedback.selectionClick();
                                  onSelected(items[newIdx]);
                                }
                              : null,
                        ),

                        // 核心刻度平滑滑块
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(sheetContext).copyWith(
                              activeTrackColor: SnapColors.primary,
                              inactiveTrackColor: Colors.white12,
                              thumbColor: SnapColors.primary,
                              overlayColor: SnapColors.primary.withAlpha(40),
                              trackHeight: 6,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                            ),
                            child: Slider(
                              value: activeIndex.toDouble(),
                              min: 0,
                              max: (items.length - 1).toDouble(),
                              divisions: items.length > 1 ? items.length - 1 : 1,
                              onChanged: (newVal) {
                                final newIdx = newVal.round();
                                if (newIdx != activeIndex) {
                                  setSheetState(() => activeIndex = newIdx);
                                  HapticFeedback.selectionClick();
                                  onSelected(items[newIdx]);
                                }
                              },
                            ),
                          ),
                        ),

                        // [+] 微调按键
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          color: activeIndex < items.length - 1 ? Colors.white70 : Colors.white24,
                          iconSize: 28,
                          tooltip: '向后步进',
                          onPressed: activeIndex < items.length - 1
                              ? () {
                                  final newIdx = activeIndex + 1;
                                  setSheetState(() => activeIndex = newIdx);
                                  HapticFeedback.selectionClick();
                                  onSelected(items[newIdx]);
                                }
                              : null,
                        ),
                      ],
                    ),

                    // 底部两端标尺说明
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            items.first,
                            style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                          ),
                          const Text(
                            '左右拖动滑块实时调节',
                            style: TextStyle(color: Colors.white24, fontSize: 10),
                          ),
                          Text(
                            items.last,
                            style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool currentValOrClean(String item, String current) {
    if (item.trim() == current.trim()) return true;
    if (current != '--' && item.contains(current)) return true;
    return false;
  }

  Widget _buildLandscapeSideBtn({
    required IconData icon,
    bool active = false,
    Color? color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? SnapColors.primary.withAlpha(50) : Colors.black.withAlpha(190),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? SnapColors.primary : Colors.white24, width: 0.8),
          ),
          child: Icon(icon, size: 20, color: color ?? (active ? SnapColors.primary : Colors.white70)),
        ),
      ),
    );
  }



  Widget _buildQuickToolIcon({
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? SnapColors.primary.withAlpha(50) : Colors.black.withAlpha(160),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? SnapColors.primary : Colors.white24, width: 0.8),
          ),
          child: Icon(icon, size: 18, color: active ? SnapColors.primary : Colors.white70),
        ),
      ),
    );
  }
}

/// 实时 RGB 曲线与亮度直方图绘制器 (高保真对标 media_1791281187023.jpg)
class RgbCurveHistogramPainter extends CustomPainter {
  final List<double>? bins;

  RgbCurveHistogramPainter({this.bins});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. 底层蓝色实线基准标线 (对标 media_1791281187023.jpg)
    final baseLineY = size.height - 4;
    final basePaint = Paint()
      ..color = const Color(0xFF2979FF)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(6, baseLineY), Offset(size.width - 6, baseLineY), basePaint);

    const count = 48;
    final providedBins = bins;
    // bins 可能为空列表（相机未回传直方图），空列表会导致 i % 0 崩溃，回退到示例曲线
    final norm = (providedBins == null || providedBins.isEmpty)
        ? List.generate(count, (i) {
            final x = (i - 24) / 9.0;
            return (1.0 / (1.0 + x * x * 0.9)) * 0.82;
          })
        : providedBins;

    final stepX = (size.width - 24) / (count - 1);
    const startX = 12.0;

    // 2. 亮度填充半透明白色阴影峰
    final lumPath = Path();
    lumPath.moveTo(startX, baseLineY);
    for (int i = 0; i < count; i++) {
      final val = (norm[i % norm.length]).clamp(0.0, 1.0);
      final x = startX + i * stepX;
      final y = baseLineY - (val * (size.height - 14));
      lumPath.lineTo(x, y);
    }
    lumPath.lineTo(startX + (count - 1) * stepX, baseLineY);
    lumPath.close();

    final lumFill = Paint()
      ..color = Colors.white.withAlpha(35)
      ..style = PaintingStyle.fill;
    canvas.drawPath(lumPath, lumFill);

    // 3. 绘制 R (红) 曲线波形
    final rPath = Path();
    final rPaint = Paint()
      ..color = const Color(0xFFFF5252)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int i = 0; i < count; i++) {
      final val = ((norm[i % norm.length]) * (0.85 + 0.25 * math.sin(i * 0.4))).clamp(0.0, 0.95);
      final x = startX + i * stepX;
      final y = baseLineY - (val * (size.height - 12));
      if (i == 0) {
        rPath.moveTo(x, y);
      } else {
        rPath.lineTo(x, y);
      }
    }
    canvas.drawPath(rPath, rPaint);

    // 4. 绘制 G (绿) 曲线波形
    final gPath = Path();
    final gPaint = Paint()
      ..color = const Color(0xFF66BB6A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int i = 0; i < count; i++) {
      final val = ((norm[i % norm.length]) * (0.75 + 0.3 * math.cos(i * 0.5))).clamp(0.0, 0.92);
      final x = startX + i * stepX;
      final y = baseLineY - (val * (size.height - 12));
      if (i == 0) {
        gPath.moveTo(x, y);
      } else {
        gPath.lineTo(x, y);
      }
    }
    canvas.drawPath(gPath, gPaint);

    // 5. 绘制 B (蓝) 曲线波形
    final bPath = Path();
    final bPaint = Paint()
      ..color = const Color(0xFF42A5F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int i = 0; i < count; i++) {
      final val = ((norm[i % norm.length]) * (0.9 + 0.2 * math.sin(i * 0.6 + 1.0))).clamp(0.0, 0.98);
      final x = startX + i * stepX;
      final y = baseLineY - (val * (size.height - 12));
      if (i == 0) {
        bPath.moveTo(x, y);
      } else {
        bPath.lineTo(x, y);
      }
    }
    canvas.drawPath(bPath, bPaint);
  }

  @override
  bool shouldRepaint(covariant RgbCurveHistogramPainter oldDelegate) => true;
}

/// 垂直 EV 刻度阶梯标尺绘制器 (对标 media_1791281187023.jpg: +2 ~ -2 与橙色指示点)
class EvLadderPainter extends CustomPainter {
  final double currentEv;

  EvLadderPainter({required this.currentEv});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final tickPaint = Paint()
      ..color = Colors.white60
      ..strokeWidth = 1.0;
    final mainTickPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;

    final steps = [
      {'val': 2.0, 'label': '2', 'main': true},
      {'val': 1.5, 'label': '', 'main': false},
      {'val': 1.0, 'label': '1', 'main': true},
      {'val': 0.5, 'label': '', 'main': false},
      {'val': 0.0, 'label': '0', 'main': true},
      {'val': -0.5, 'label': '', 'main': false},
      {'val': -1.0, 'label': '-1', 'main': true},
      {'val': -1.5, 'label': '', 'main': false},
      {'val': -2.0, 'label': '-2', 'main': true},
    ];

    const topY = 10.0;
    final bottomY = size.height - 10.0;
    final totalH = bottomY - topY;

    // 绘制垂直标尺轴线
    canvas.drawLine(const Offset(10, topY), Offset(10, bottomY), tickPaint);

    for (final s in steps) {
      final v = s['val'] as double;
      final isMain = s['main'] as bool;
      final label = s['label'] as String;

      final t = (2.0 - v) / 4.0;
      final y = topY + t * totalH;

      final tickLen = isMain ? 9.0 : 5.0;
      canvas.drawLine(Offset(10, y), Offset(10 + tickLen, y), isMain ? mainTickPaint : tickPaint);

      if (label.isNotEmpty) {
        textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(22, y - textPainter.height / 2));
      }
    }

    // 绘制当前 EV 值的橙色小圆点
    final currentT = (2.0 - currentEv.clamp(-2.0, 2.0)) / 4.0;
    final currentY = topY + currentT * totalH;
    final dotPaint = Paint()..color = const Color(0xFFFF9800);
    canvas.drawCircle(Offset(10, currentY), 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant EvLadderPainter oldDelegate) => oldDelegate.currentEv != currentEv;
}
