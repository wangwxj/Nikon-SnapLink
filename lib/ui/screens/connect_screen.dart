import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/network_config.dart';
import '../../core/utils/app_log_manager.dart';
import '../../protocol/camera_driver.dart';
import '../../protocol/camera_native_bridge.dart';
import '../widgets/vant_widgets.dart';

/// 相机连接配置向导页面 (Wi-Fi 直连、蓝牙互联、USB 直连)
class ConnectScreen extends StatefulWidget {
  final CameraDriver driver;
  final VoidCallback onConnected;
  final VoidCallback? onNavigateToLiveView;
  final VoidCallback? onNavigateToGallery;

  const ConnectScreen({
    super.key,
    required this.driver,
    required this.onConnected,
    this.onNavigateToLiveView,
    this.onNavigateToGallery,
  });

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> with WidgetsBindingObserver {
  // Wi-Fi 相关状态
  WifiNetworkInfo _wifiInfo = WifiNetworkInfo(
    connected: false,
    bound: false,
    ssid: '<检测中...>',
    gateway: '192.168.0.1',
    ip: '192.168.0.2',
  );

  // 蓝牙相关状态
  bool _isBluetoothEnabled = false;
  bool _isBleScanning = false;
  List<BleDeviceInfo> _bleDevices = [];
  Timer? _bleScanPollTimer;
  String _bleStatus = 'disconnected';
  String _bleConnectedDeviceName = '';

  bool _isConnecting = false;
  int _activeTabIndex = 0; // 0: Wi-Fi 直连, 1: 蓝牙互联, 2: USB

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshWifiStatus();
    _checkBluetoothStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleScanPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWifiStatus();
      _checkBluetoothStatus();
    }
  }

  void _addLog(String msg) {
    AppLogManager.instance.add(msg);
  }

  // ==========================================
  // Wi-Fi 逻辑
  // ==========================================
  Future<void> _refreshWifiStatus() async {
    final info = await CameraNativeBridge.getWifiInfo();
    if (mounted) {
      setState(() {
        _wifiInfo = info;
      });
    }
  }

  Future<void> _handleWifiConnect() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);

    // 自动选取最优相机网关 IP (优先网关，若无效则取设置中的相机 IP)
    var targetIp = NetworkConfig.cameraIp;
    if (_wifiInfo.gateway.isNotEmpty && _wifiInfo.gateway != '0.0.0.0') {
      targetIp = _wifiInfo.gateway;
    }
    final targetPort = NetworkConfig.cameraPort;

    _addLog('【步骤1】执行原生网络强绑定 (targetHost=$targetIp)...');
    try {
      if (NetworkConfig.autoBindNetwork) {
        final bindResult = await CameraNativeBridge.bindCameraWifi(targetHost: targetIp);
        setState(() => _wifiInfo = bindResult);
        _addLog('网络绑定状态: bound=${bindResult.bound}, SSID=${bindResult.ssid}');
      }

      _addLog('【步骤2】发起 PTP/IP 双通道握手: $targetIp:$targetPort');
      await widget.driver.connect(
        targetIp,
        port: targetPort,
        onLog: (msg) => _addLog(msg),
      );

      _addLog('【成功】PTP/IP 握手与 OpenSession 成功！已连入相机: ${widget.driver.cameraModel}');
      if (mounted) setState(() {});
      widget.onConnected();
    } catch (e) {
      _addLog('连接失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $e\n提示：请先在手机系统 Wi-Fi 中加入相机热点'),
            backgroundColor: SnapColors.of(context).danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _handleDisconnect() async {
    await widget.driver.disconnect();
    await CameraNativeBridge.unbindWifi();
    _addLog('已断开与相机的连接并释放网络绑定');
    if (mounted) setState(() {});
  }

  // ==========================================
  // 蓝牙 BLE 逻辑
  // ==========================================
  Future<void> _checkBluetoothStatus() async {
    final enabled = await CameraNativeBridge.isBluetoothEnabled();
    final bleStat = await CameraNativeBridge.getBleStatus();
    if (mounted) {
      setState(() {
        _isBluetoothEnabled = enabled;
        _bleStatus = bleStat['status'] as String? ?? 'disconnected';
        _bleConnectedDeviceName = bleStat['deviceName'] as String? ?? '';
      });
    }
  }

  Future<void> _toggleBleScan() async {
    if (_isBleScanning) {
      _bleScanPollTimer?.cancel();
      await CameraNativeBridge.stopBleScan();
      setState(() => _isBleScanning = false);
      _addLog('已停止蓝牙扫描');
    } else {
      final success = await CameraNativeBridge.startBleScan();
      if (!success) {
        _addLog('启动蓝牙扫描失败，请检查蓝牙开关与定位/近距离设备权限');
        return;
      }
      setState(() {
        _isBleScanning = true;
        _bleDevices.clear();
      });
      _addLog('正在扫描周围尼康相机与低功耗蓝牙设备...');

      _bleScanPollTimer?.cancel();
      _bleScanPollTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
        final list = await CameraNativeBridge.getScannedBleDevices();
        if (mounted) {
          setState(() {
            list.sort((a, b) {
              if (a.isNikon && !b.isNikon) return -1;
              if (!a.isNikon && b.isNikon) return 1;
              return b.rssi.compareTo(a.rssi);
            });
            _bleDevices = list;
          });
        }
      });
    }
  }

  Future<void> _connectBleDevice(BleDeviceInfo device) async {
    _bleScanPollTimer?.cancel();
    setState(() => _isBleScanning = false);
    _addLog('正在连接蓝牙设备: ${device.name} (${device.address})...');

    final res = await CameraNativeBridge.connectBleDevice(device.address);
    if (res['status'] == 'connecting' || res['status'] == 'connected') {
      _addLog('蓝牙配对握手发起成功！');
      _checkBluetoothStatus();
    } else {
      _addLog('蓝牙连接失败: ${res['error'] ?? '未知错误'}');
    }
  }

  // ==========================================
  // UI 构建
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final isConnected = widget.driver.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的相机'),
        actions: [
          if (isConnected)
            TextButton(
              onPressed: _handleDisconnect,
              child: Text('断开', style: TextStyle(color: SnapColors.of(context).danger, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),

            if (isConnected) ...[
              _buildConnectedDashboard(),
            ] else ...[
              // 应用 Logo 与品牌标题
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: SnapColors.of(context).card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: SnapColors.of(context).border, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(102),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/icons/snaplink_logo.png',
                          width: 52,
                          height: 52,
                          errorBuilder: (ctx, err, stack) => SvgPicture.asset(
                            'assets/icons/snaplink_logo.svg',
                            width: 52,
                            height: 52,
                            placeholderBuilder: (ctx) => Icon(
                              Icons.camera_alt,
                              color: SnapColors.of(context).primary,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'SnapLink 尼康互联',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: SnapColors.of(context).textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '尼康 Z / D 系列专业无线监看与传输套件',
                      style: TextStyle(fontSize: 11, color: SnapColors.of(context).textSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 模式切换 Tab (Wi-Fi 直连 / 蓝牙互联 / USB) - 精准对齐用户指令
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: SnapColors.of(context).card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SnapColors.of(context).border, width: 0.8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(0, 'Wi-Fi 直连', Icons.wifi),
                    ),
                    Expanded(
                      child: _buildTabButton(1, '蓝牙互联', Icons.bluetooth),
                    ),
                    Expanded(
                      child: _buildTabButton(2, 'USB', Icons.usb),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Tab 0: Wi-Fi 直连
              if (_activeTabIndex == 0) _buildWifiTabContent(isConnected),

              // Tab 1: 蓝牙互联
              if (_activeTabIndex == 1) _buildBleTabContent(),

              // Tab 2: USB
              if (_activeTabIndex == 2) _buildUsbTabContent(isConnected),
            ],

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 已连接状态看板 (高精度对齐 media_1791281187027.jpg)
  // ==========================================
  Widget _buildConnectedDashboard() {
    final cameraName = widget.driver.cameraModel.isNotEmpty ? widget.driver.cameraModel : 'Z 30';
    final targetIp = _wifiInfo.gateway.isNotEmpty && _wifiInfo.gateway != '0.0.0.0'
        ? _wifiInfo.gateway
        : NetworkConfig.cameraIp;
    final targetPort = NetworkConfig.cameraPort;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. CURRENT CAMERA 高反差黑卡 (对齐 media_1791281187027.jpg)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SnapColors.of(context).card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SnapColors.of(context).border, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(Theme.of(context).brightness == Brightness.light ? 25 : 120),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURRENT CAMERA',
                          style: TextStyle(
                            color: SnapColors.of(context).textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cameraName,
                          style: TextStyle(
                            color: SnapColors.of(context).textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    // 尼康金圆形 Monogram 徽标 (N) —— 黑黄品牌配色
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: SnapColors.of(context).primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          'N',
                          style: TextStyle(
                            color: SnapColors.of(context).textInverse,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'sans-serif',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 连接状态胶囊 (黑黄配色)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SnapColors.of(context).primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SnapColors.of(context).primary.withAlpha(80), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 7, color: SnapColors.of(context).primary),
                      const SizedBox(width: 6),
                      Text(
                        '已连接  相机热点 Wi-Fi · $targetIp:$targetPort...',
                        style: TextStyle(
                          color: SnapColors.of(context).primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2 个内嵌小圆角卡片 (品牌与型号)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: SnapColors.of(context).cardElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: SnapColors.of(context).border, width: 0.8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('品牌', style: TextStyle(color: SnapColors.of(context).textTertiary, fontSize: 10)),
                            const SizedBox(height: 2),
                            Text('Nikon', style: TextStyle(color: SnapColors.of(context).textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: SnapColors.of(context).cardElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: SnapColors.of(context).border, width: 0.8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('型号', style: TextStyle(color: SnapColors.of(context).textTertiary, fontSize: 10)),
                            const SizedBox(height: 2),
                            Text(cameraName, style: TextStyle(color: SnapColors.of(context).textPrimary, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 主要按钮 1: 全宽尼康金圆角按钮「浏览相机照片」
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SnapColors.of(context).primary,
                      foregroundColor: SnapColors.of(context).textInverse,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: widget.onNavigateToGallery,
                    child: const Text(
                      '浏览相机照片',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 次要按钮 2: 全宽描边按钮「远程控制 / 实时监看」(仅跳转取景页，进入后需手动开启取景)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: SnapColors.of(context).card,
                      foregroundColor: SnapColors.of(context).primary,
                      side: BorderSide(color: SnapColors.of(context).primary, width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(Icons.videocam_outlined, size: 18, color: SnapColors.of(context).primary),
                    label: const Text(
                      '远程控制 / 实时监看',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    onPressed: widget.onNavigateToLiveView ?? widget.onConnected,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. 已连接镜头卡片 (对齐 media_1791281187027.jpg)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: SnapColors.of(context).card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SnapColors.of(context).border, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lens_blur_rounded, color: SnapColors.of(context).textSecondary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '已连接镜头',
                          style: TextStyle(color: SnapColors.of(context).textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SnapColors.of(context).primary.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 6, color: SnapColors.of(context).primary),
                          const SizedBox(width: 4),
                          Text('已识别', style: TextStyle(color: SnapColors.of(context).primary, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '50-250mm · f/4.5-6.3',
                  style: TextStyle(color: SnapColors.of(context).textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),

                // 规格微卡 (当前光圈/当前焦距数据不可靠，按用户要求不再展示)
                Row(
                  children: [
                    Expanded(child: _buildLensGridCell('焦距范围', '50-250\nmm')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildLensGridCell('光圈范围', 'f/4.5-6.3\n ')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildLensGridCell('镜头 ID', 'Lens ID 12\n ')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildLensGridCell('防抖', 'VR\n ')),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 断开连接按钮
          Center(
            child: TextButton.icon(
              onPressed: _handleDisconnect,
              icon: Icon(Icons.link_off, color: SnapColors.of(context).textSecondary, size: 16),
              label: Text('断开与相机的连接并释放网络', style: TextStyle(color: SnapColors.of(context).textSecondary, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLensGridCell(String title, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: SnapColors.of(context).cardElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: SnapColors.of(context).textSecondary, fontSize: 9.5)),
          const SizedBox(height: 3),
          Text(val, style: TextStyle(color: SnapColors.of(context).textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==========================================
  // Wi-Fi 界面构建 (极简清爽设计)
  // ==========================================
  Widget _buildWifiTabContent(bool isConnected) {
    final hasCameraWifi = _wifiInfo.connected &&
        (_wifiInfo.ssid.toUpperCase().contains('NIKON') ||
         _wifiInfo.gateway.isNotEmpty);

    return Column(
      children: [
        // 当前 Wi-Fi 状态卡片
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SnapColors.of(context).card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SnapColors.of(context).border, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wifi_tethering,
                          size: 22,
                          color: _wifiInfo.connected ? SnapColors.of(context).primary : SnapColors.of(context).textTertiary,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('当前连接 Wi-Fi', style: TextStyle(color: SnapColors.of(context).textTertiary, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(
                              _wifiInfo.ssid,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: SnapColors.of(context).textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, size: 20, color: SnapColors.of(context).primary),
                      onPressed: _refreshWifiStatus,
                      tooltip: '重新探测 Wi-Fi',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 连接引导文案
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SnapColors.of(context).card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SnapColors.of(context).border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasCameraWifi ? Icons.check_circle_outline : Icons.info_outline,
                        color: hasCameraWifi ? SnapColors.of(context).success : SnapColors.of(context).warning,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasCameraWifi
                              ? '已加入相机网络，点击下方按钮即可建立连接'
                              : '请在手机系统 Wi-Fi 中加入相机释放的热点（例如 NIKON_...）',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasCameraWifi ? SnapColors.of(context).textPrimary : SnapColors.of(context).warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 系统 Wi-Fi 跳转按钮
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SnapColors.of(context).primary,
                      side: BorderSide(color: SnapColors.of(context).primary, width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('打开手机系统 Wi-Fi 设置', style: const TextStyle(fontSize: 13)),
                    onPressed: () => CameraNativeBridge.openWifiSettings(),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        // 未连接时的连接主按钮
        if (!isConnected) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SnapColors.of(context).primary,
                  foregroundColor: SnapColors.of(context).textInverse,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isConnecting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(SnapColors.of(context).textInverse)),
                      )
                    : const Icon(Icons.link, size: 20),
                label: Text(
                  _isConnecting ? '正在建立相机连接...' : '连接相机 (Wi-Fi 直连)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: _isConnecting ? null : _handleWifiConnect,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================
  // 蓝牙 BLE 模式界面构建
  // ==========================================
  Widget _buildBleTabContent() {
    return Column(
      children: [
        // 蓝牙状态与开关
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SnapColors.of(context).card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SnapColors.of(context).border, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.bluetooth,
                          size: 20,
                          color: _isBluetoothEnabled ? Colors.lightBlueAccent : SnapColors.of(context).textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isBluetoothEnabled ? '手机蓝牙已开启' : '手机蓝牙已关闭',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: SnapColors.of(context).textPrimary),
                        ),
                      ],
                    ),
                    VantTag(
                      text: _bleStatus == 'connected' ? '已连接' : (_bleStatus == 'connecting' ? '配对中' : '未连接'),
                      color: _bleStatus == 'connected' ? SnapColors.of(context).success : SnapColors.of(context).textTertiary,
                    ),
                  ],
                ),
                if (_bleConnectedDeviceName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('当前配对: $_bleConnectedDeviceName', style: TextStyle(color: SnapColors.of(context).primary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // BLE 遥控快门（Nikon LSS）规划中：官方链路加密库为闭源，纯 Dart 复刻待逐字节验证
        if (_bleStatus == 'connected') ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SnapColors.of(context).card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SnapColors.of(context).border, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('无线遥控快门 (ML-L7)', style: TextStyle(color: SnapColors.of(context).textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SnapColors.of(context).card,
                            foregroundColor: SnapColors.of(context).textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.filter_center_focus, size: 18),
                          label: const Text('半按对焦'),
                          onPressed: null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SnapColors.of(context).primary,
                            foregroundColor: SnapColors.of(context).textInverse,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.camera, size: 18),
                          label: const Text('全按拍照', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 蓝牙扫描控制按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VantButton(
            text: _isBleScanning ? '停止扫描' : '扫描附近蓝牙设备 (BLE)',
            icon: _isBleScanning ? Icons.stop : Icons.search,
            type: _isBleScanning ? VantButtonType.danger : VantButtonType.primary,
            isBlock: true,
            onTap: _toggleBleScan,
          ),
        ),

        const SizedBox(height: 14),

        // 扫描结果列表
        if (_bleDevices.isNotEmpty) ...[
          VantCellGroup(
            title: '已发现的相机设备 (${_bleDevices.length})',
            children: _bleDevices.map((dev) {
              return VantCell(
                title: dev.name,
                label: 'MAC: ${dev.address} | 信号: ${dev.rssi} dBm',
                customValue: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dev.isNikon) ...[
                      VantTag(text: 'NIKON', color: SnapColors.of(context).primary),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dev.isNikon ? SnapColors.of(context).primary : SnapColors.of(context).textSecondary,
                        side: BorderSide(color: dev.isNikon ? SnapColors.of(context).primary : SnapColors.of(context).border),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      ),
                      onPressed: () => _connectBleDevice(dev),
                      child: const Text('连接', style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ] else if (_isBleScanning) ...[
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircularProgressIndicator(color: SnapColors.of(context).primary, strokeWidth: 2.5),
                const SizedBox(height: 12),
                Text('正在搜索附近的相机与蓝牙设备...', style: TextStyle(color: SnapColors.of(context).textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================
  // USB 模式界面构建
  // ==========================================
  Widget _buildUsbTabContent(bool isConnected) {
    return Column(
      children: [
        VantCellGroup(
          title: 'USB OTG 有线连接使用指南',
          children: [
            const VantCell(
              title: '连接准备',
              value: '使用 Type-C OTG 数据线直连相机与手机',
            ),
            const VantCell(
              title: '相机菜单设置',
              value: '相机菜单 -> USB 模式 -> 设为 MTP/PTP',
            ),
            VantCell(
              title: 'USB 主机状态',
              customValue: VantTag(
                text: isConnected ? '有线已连通' : '等待设备接入',
                color: isConnected ? SnapColors.of(context).success : SnapColors.of(context).warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VantButton(
            text: isConnected ? 'USB 已建立连接' : '检查 USB 设备',
            icon: Icons.usb,
            type: isConnected ? VantButtonType.success : VantButtonType.primary,
            isBlock: true,
            onTap: () {
              _addLog('检测 USB OTG 接口...');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: const Text('请插上 Type-C OTG 线缆直连相机')),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton(int index, String title, IconData icon) {
    final isSelected = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? SnapColors.of(context).primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? SnapColors.of(context).textInverse : SnapColors.of(context).textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? SnapColors.of(context).textInverse : SnapColors.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
