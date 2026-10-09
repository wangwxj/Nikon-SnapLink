import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/colors.dart';
import '../../core/settings/app_settings.dart';
import '../../core/utils/app_log_manager.dart';
import '../../engine/update/app_update_manager.dart';
import '../../protocol/camera_native_bridge.dart';
import '../widgets/vant_widgets.dart';

/// 系统偏好与设置页面 (Settings Screen)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _showIpEditDialog() {
    final controller = TextEditingController(text: AppSettings.instance.cameraIp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnapColors.cardElevated,
        title: const Text('配置相机 IP 地址', style: TextStyle(color: SnapColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('尼康相机热点默认网关为 192.168.0.1，部分发射器为 192.168.1.1', style: TextStyle(color: SnapColors.textTertiary, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: SnapColors.textPrimary, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'IP 地址',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: SnapColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SnapColors.primary, foregroundColor: Colors.black),
            onPressed: () {
              final newIp = controller.text.trim();
              if (newIp.isNotEmpty) {
                AppSettings.instance.setCameraIp(newIp);
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showPortEditDialog() {
    final controller = TextEditingController(text: AppSettings.instance.cameraPort.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnapColors.cardElevated,
        title: const Text('配置 PTP/IP 端口', style: TextStyle(color: SnapColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('尼康 PTP/IP 硬件标准通信端口为 15740', style: TextStyle(color: SnapColors.textTertiary, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: SnapColors.textPrimary, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: '端口号',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: SnapColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SnapColors.primary, foregroundColor: Colors.black),
            onPressed: () {
              final port = int.tryParse(controller.text.trim());
              if (port != null && port > 0) {
                AppSettings.instance.setCameraPort(port);
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showLogsViewerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D0D10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final logs = AppLogManager.instance.logs;
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('底层协议通信与握手日志', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18, color: SnapColors.primary),
                            tooltip: '复制全部日志',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: logs.join('\n')));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制全部通信日志至剪贴板')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: SnapColors.danger),
                            tooltip: '清空日志',
                            onPressed: () {
                              AppLogManager.instance.clear();
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF060608),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: logs.isEmpty
                          ? const Center(
                              child: Text('暂无通信日志', style: TextStyle(color: Colors.white38, fontSize: 12)),
                            )
                          : ListView.builder(
                              itemCount: logs.length,
                              itemBuilder: (c, i) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  logs[i],
                                  style: TextStyle(
                                    color: logs[i].contains('失败') || logs[i].contains('异常')
                                        ? const Color(0xFFFF5252)
                                        : (logs[i].contains('成功')
                                            ? const Color(0xFF00E676)
                                            : const Color(0xFFB0BEC5)),
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统设置'),
      ),
      body: ListView(
        children: [
          // 1. 高级网络与相机参数配置
          VantCellGroup(
            title: '高级网络与相机连接参数',
            children: [
              VantCell(
                title: '默认相机 IP 地址',
                value: AppSettings.instance.cameraIp,
                isLink: true,
                onTap: _showIpEditDialog,
              ),
              VantCell(
                title: 'PTP/IP 通信端口',
                value: '${AppSettings.instance.cameraPort}',
                isLink: true,
                onTap: _showPortEditDialog,
              ),
              VantCell(
                title: '快捷预设: 尼康默认热点 (192.168.0.1)',
                value: '应用',
                isLink: true,
                onTap: () {
                  setState(() {
                    AppSettings.instance.setCameraIp('192.168.0.1');
                    AppSettings.instance.setCameraPort(15740);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已恢复尼康默认相机热点地址 (192.168.0.1:15740)')),
                  );
                },
              ),
              VantCell(
                title: '快捷预设: 局域网/WT发射器 (192.168.1.1)',
                value: '应用',
                isLink: true,
                onTap: () {
                  setState(() {
                    AppSettings.instance.setCameraIp('192.168.1.1');
                    AppSettings.instance.setCameraPort(15740);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已设置为局域网发射器地址 (192.168.1.1:15740)')),
                  );
                },
              ),
              VantCell(
                title: 'Android 进程网卡强绑定',
                customValue: Switch(
                  value: AppSettings.instance.autoBindNetwork,
                  activeThumbColor: SnapColors.primary,
                  onChanged: (val) {
                    AppSettings.instance.setAutoBindNetwork(val);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),

          // 2. 底层协议通信与诊断日志
          VantCellGroup(
            title: '协议通信诊断与系统日志',
            children: [
              VantCell(
                title: '查看协议握手与通信日志',
                value: '${AppLogManager.instance.logs.length} 条记录',
                isLink: true,
                onTap: _showLogsViewerSheet,
              ),
              VantCell(
                title: '清空通信诊断日志',
                value: '清空',
                isLink: true,
                onTap: () {
                  setState(() => AppLogManager.instance.clear());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清空全部日志')),
                  );
                },
              ),
            ],
          ),

          // 3. 无线与传输设置
          VantCellGroup(
            title: '无线与传输设置',
            children: [
              VantCell(
                title: '后台保持相机 Wi-Fi 连接',
                customValue: Switch(
                  value: AppSettings.instance.autoKeepAlive,
                  activeThumbColor: SnapColors.primary,
                  onChanged: (val) {
                    AppSettings.instance.setAutoKeepAlive(val);
                    setState(() {});
                  },
                ),
              ),
              const VantCell(
                title: 'PTP/IP 心跳间隔',
                value: '15 秒 (防止相机自动休眠)',
              ),
              VantCell(
                title: '边拍边传同步 RAW 格式',
                customValue: Switch(
                  value: AppSettings.instance.downloadRaw,
                  activeThumbColor: SnapColors.primary,
                  onChanged: (val) {
                    AppSettings.instance.setDownloadRaw(val);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),

          // 4. LiveView 取景偏好
          VantCellGroup(
            title: 'LiveView 取景偏好',
            children: [
              VantCell(
                title: '默认取景目标帧率',
                value: '${AppSettings.instance.preferredFps} FPS',
                isLink: true,
                onTap: () {
                  final opts = AppSettings.fpsOptions;
                  final idx = opts.indexOf(AppSettings.instance.preferredFps);
                  AppSettings.instance.setPreferredFps(opts[(idx + 1) % opts.length]);
                  setState(() {});
                },
              ),
              const VantCell(
                title: 'Nikon 0x9428 取流协议',
                value: '自适应智能回退 0x9203',
              ),
              const VantCell(
                title: '横屏监视模式',
                value: '支持全屏 3:2 导演监看与 HUD',
              ),
            ],
          ),

          // 5. 低电量传输保护 (SnapBridge-Enhanced)
          VantCellGroup(
            title: '低电量传输保护 (SnapBridge-Enhanced)',
            children: [
              VantCell(
                title: '启用低电量传输保护',
                customValue: Switch(
                  value: AppSettings.instance.powerProtectionEnabled,
                  activeThumbColor: SnapColors.primary,
                  onChanged: (val) {
                    AppSettings.instance.setPowerProtectionEnabled(val);
                    setState(() {});
                  },
                ),
              ),
              VantCell(
                title: '电量暂停保护阈值',
                value: '${AppSettings.instance.powerThreshold}%',
                isLink: true,
                onTap: () {
                  final opts = AppSettings.powerThresholdOptions;
                  final idx = opts.indexOf(AppSettings.instance.powerThreshold);
                  AppSettings.instance.setPowerThreshold(opts[(idx + 1) % opts.length]);
                  setState(() {});
                },
              ),
              const VantCell(
                title: '迟滞恢复机制 (+5%)',
                value: '电量回升至阈值+5%自动恢复',
              ),
              const VantCell(
                title: '正在传输任务',
                value: '完成当前文件写入后再暂停 (不截断)',
              ),
            ],
          ),

          // 6. LiveView 变焦手势
          const VantCellGroup(
            title: 'LiveView 变焦手势 (对齐 Enhanced 规范)',
            children: [
              VantCell(
                title: '双击左半屏',
                value: '广角 (WIDE) 320ms 短脉冲',
              ),
              VantCell(
                title: '双击右半屏',
                value: '长焦 (TELE) 320ms 短脉冲',
              ),
              VantCell(
                title: '双指缩放 (Pinch)',
                value: '张开长焦 / 捏合广角 (抬手即停)',
              ),
              VantCell(
                title: '单指单击画面',
                value: '自动对焦 (AF Drive)',
              ),
            ],
          ),

          // 7. 关于 SnapLink
          VantCellGroup(
            title: '关于 SnapLink',
            children: [
              VantCell(
                title: '应用版本',
                value: 'v${AppUpdateManager.currentVersion} (Build ${AppUpdateManager.currentVersionCode})',
              ),
              VantCell(
                title: '检查新版本',
                value: '在线检测 (Gitee / GitHub)',
                isLink: true,
                onTap: () {
                  AppUpdateManager.checkManually(context);
                },
              ),
              const VantCell(
                title: '驱动架构',
                value: 'Wi-Fi PTP/IP + USB PTP (Dart/Kotlin)',
              ),
              const VantCell(
                title: 'UI 体系',
                value: 'Flutter Vant UI 摄影监看系统',
              ),
              VantCell(
                title: '开源与许可',
                value: 'Gitee / MIT License',
                isLink: true,
                onTap: () {
                  CameraNativeBridge.openUrlInBrowser('https://gitee.com/lyb82ndkkkl/Nikon-SnapLink');
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}


