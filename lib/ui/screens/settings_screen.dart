import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/colors.dart';
import '../../core/settings/app_settings.dart';
import '../../core/utils/app_log_manager.dart';
import '../../engine/update/app_update_manager.dart';
import '../../protocol/camera_native_bridge.dart';
import '../widgets/vant_widgets.dart';

/// 系统偏好与设置页面：一级分类菜单，具体配置在二级详情页。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _showIpEditDialog(BuildContext context) {
    final controller = TextEditingController(text: AppSettings.instance.cameraIp);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置相机 IP 地址', style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '尼康相机热点默认网关为 192.168.0.1，部分发射器为 192.168.1.1',
              style: TextStyle(color: SnapColors.of(ctx).textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'IP 地址',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final newIp = controller.text.trim();
              if (newIp.isNotEmpty) {
                AppSettings.instance.setCameraIp(newIp);
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showPortEditDialog(BuildContext context) {
    final controller = TextEditingController(text: AppSettings.instance.cameraPort.toString());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置 PTP/IP 端口', style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '尼康 PTP/IP 硬件标准通信端口为 15740',
              style: TextStyle(color: SnapColors.of(ctx).textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: '端口号',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final port = int.tryParse(controller.text.trim());
              if (port != null && port > 0) {
                AppSettings.instance.setCameraPort(port);
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _openDetail(Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return Scaffold(
          appBar: AppBar(title: const Text('系统设置')),
          body: ListView(
            children: [
              VantCellGroup(
                title: '偏好设置',
                children: [
                  VantCell(
                    title: '外观与显示',
                    label: '跟随系统、浅色或深色',
                    value: _themeLabel(settings.themeMode),
                    icon: Icons.palette_outlined,
                    isLink: true,
                    onTap: () => _openDetail(_AppearanceDetail()),
                  ),
                  VantCell(
                    title: '相机连接',
                    label: 'IP、端口与网卡绑定',
                    value: '${settings.cameraIp}:${settings.cameraPort}',
                    icon: Icons.wifi_tethering_outlined,
                    isLink: true,
                    onTap: () => _openDetail(
                      _CameraConnectionDetail(
                        onEditIp: () => _showIpEditDialog(context),
                        onEditPort: () => _showPortEditDialog(context),
                      ),
                    ),
                  ),
                  VantCell(
                    title: '无线与传输',
                    label: '保活与边拍边传',
                    value: '${settings.autoKeepAlive ? '保活开' : '保活关'} · RAW ${settings.downloadRaw ? '开' : '关'}',
                    icon: Icons.sync_alt,
                    isLink: true,
                    onTap: () => _openDetail(_WirelessDetail()),
                  ),
                  VantCell(
                    title: '取景与拍摄',
                    label: '帧率、监看与手势',
                    value: '${settings.preferredFps} FPS · 横屏',
                    icon: Icons.videocam_outlined,
                    isLink: true,
                    onTap: () => _openDetail(_LiveViewDetail()),
                  ),
                  VantCell(
                    title: '电池与传输保护',
                    label: '低电量暂停与恢复',
                    value: settings.powerProtectionEnabled
                        ? '${settings.powerThreshold}% 阈值'
                        : '已关闭',
                    icon: Icons.battery_saver_outlined,
                    isLink: true,
                    onTap: () => _openDetail(_PowerProtectionDetail()),
                  ),
                ],
              ),
              VantCellGroup(
                title: '系统',
                children: [
                  VantCell(
                    title: '诊断与日志',
                    label: '协议握手与通信记录',
                    value: '${AppLogManager.instance.logs.length} 条记录',
                    icon: Icons.receipt_long_outlined,
                    isLink: true,
                    onTap: () => _openDetail(_DiagnosticsDetail()),
                  ),
                  VantCell(
                    title: '关于 SnapLink',
                    label: '版本、更新与开源许可',
                    value: 'v${AppUpdateManager.currentVersion}',
                    icon: Icons.info_outline,
                    isLink: true,
                    onTap: () => _openDetail(_AboutDetail()),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

const _themeModes = AppThemeMode.values;

String _themeLabel(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => '跟随系统',
      AppThemeMode.light => '浅色',
      AppThemeMode.dark => '深色',
    };

String _themeDescription(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => '随手机系统自动切换',
      AppThemeMode.light => '白底黄点缀，适合明亮环境',
      AppThemeMode.dark => '黑金摄影风格，适合暗光环境',
    };

IconData _themeIcon(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => Icons.brightness_auto_outlined,
      AppThemeMode.light => Icons.light_mode_outlined,
      AppThemeMode.dark => Icons.dark_mode_outlined,
    };

class _SettingsDetailScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  _SettingsDetailScaffold({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        children: [
          ...children,
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _AppearanceDetail extends StatelessWidget {
  _AppearanceDetail();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final current = AppSettings.instance.themeMode;
        return _SettingsDetailScaffold(
          title: '外观与显示',
          children: [
            VantCellGroup(
              title: '外观模式',
              children: _themeModes.map((mode) {
                final selected = mode == current;
                return VantCell(
                  title: _themeLabel(mode),
                  label: _themeDescription(mode),
                  icon: _themeIcon(mode),
                  customValue: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? SnapColors.of(context).primary : SnapColors.of(context).textTertiary,
                    size: 20,
                  ),
                  onTap: () => AppSettings.instance.setThemeMode(mode),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '颜色预览',
                style: TextStyle(
                  color: SnapColors.of(context).textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _PalettePreview(
                      title: '浅色',
                      palette: SnapPalette.light,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PalettePreview(
                      title: '深色',
                      palette: SnapPalette.dark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PalettePreview extends StatelessWidget {
  final String title;
  final SnapPalette palette;

  _PalettePreview({
    required this.title,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: palette.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            children: [
              _Swatch(color: palette.background),
              const SizedBox(width: 6),
              _Swatch(color: palette.card),
              const SizedBox(width: 6),
              _Swatch(color: palette.primary),
            ],
          ),
          const SizedBox(height: 8),
          Text('背景 / 卡片 / 强调色', style: TextStyle(color: palette.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;

  _Swatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: SnapColors.of(context).border),
        ),
      ),
    );
  }
}

class _CameraConnectionDetail extends StatelessWidget {
  final VoidCallback onEditIp;
  final VoidCallback onEditPort;

  _CameraConnectionDetail({
    required this.onEditIp,
    required this.onEditPort,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return _SettingsDetailScaffold(
          title: '相机连接',
          children: [
            VantCellGroup(
              title: 'PTP/IP 网络',
              children: [
                VantCell(
                  title: '默认相机 IP 地址',
                  value: settings.cameraIp,
                  isLink: true,
                  onTap: onEditIp,
                ),
                VantCell(
                  title: 'PTP/IP 通信端口',
                  value: '${settings.cameraPort}',
                  isLink: true,
                  onTap: onEditPort,
                ),
                VantCell(
                  title: '尼康默认热点预设',
                  value: '192.168.0.1:15740',
                  isLink: true,
                  onTap: () {
                    settings.setCameraIp('192.168.0.1');
                    settings.setCameraPort(15740);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: const Text('已恢复尼康默认相机热点地址')),
                    );
                  },
                ),
                VantCell(
                  title: '局域网 / WT 发射器预设',
                  value: '192.168.1.1:15740',
                  isLink: true,
                  onTap: () {
                    settings.setCameraIp('192.168.1.1');
                    settings.setCameraPort(15740);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: const Text('已设置为局域网发射器地址')),
                    );
                  },
                ),
              ],
            ),
            VantCellGroup(
              title: 'Android 网络',
              children: [
                VantCell(
                  title: 'Android 进程网卡强绑定',
                  label: '连接相机热点时优先绑定 Wi-Fi 网卡',
                  customValue: Switch(
                    value: settings.autoBindNetwork,
                    onChanged: settings.setAutoBindNetwork,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _WirelessDetail extends StatelessWidget {
  _WirelessDetail();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return _SettingsDetailScaffold(
          title: '无线与传输',
          children: [
            VantCellGroup(
              title: '连接保持',
              children: [
                VantCell(
                  title: '后台保持相机 Wi-Fi 连接',
                  customValue: Switch(
                    value: settings.autoKeepAlive,
                    onChanged: settings.setAutoKeepAlive,
                  ),
                ),
                const VantCell(
                  title: 'PTP/IP 心跳间隔',
                  value: '15 秒 (防止相机自动休眠)',
                ),
              ],
            ),
            VantCellGroup(
              title: '边拍边传',
              children: [
                VantCell(
                  title: '同步 RAW 格式',
                  label: '同时下载 NEF / NRW 文件',
                  customValue: Switch(
                    value: settings.downloadRaw,
                    onChanged: settings.setDownloadRaw,
                  ),
                ),
              ],
            ),
            VantCellGroup(
              title: '删除与确认',
              children: [
                VantCell(
                  title: '删除前再次确认',
                  label: '关闭后，选定删除范围即执行不可恢复的删除',
                  customValue: Switch(
                    value: settings.confirmDelete,
                    onChanged: settings.setConfirmDelete,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LiveViewDetail extends StatelessWidget {
  _LiveViewDetail();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return _SettingsDetailScaffold(
          title: '取景与拍摄',
          children: [
            VantCellGroup(
              title: 'LiveView 取景偏好',
              children: [
                VantCell(
                  title: '默认取景目标帧率',
                  value: '${settings.preferredFps} FPS',
                  isLink: true,
                  onTap: () {
                    const options = AppSettings.fpsOptions;
                    final index = options.indexOf(settings.preferredFps);
                    settings.setPreferredFps(options[(index + 1) % options.length]);
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
            const VantCellGroup(
              title: 'LiveView 变焦手势',
              children: [
                const VantCell(title: '双击左半屏', value: '广角 (WIDE)'),
                const VantCell(title: '双击右半屏', value: '长焦 (TELE)'),
                const VantCell(title: '双指缩放', value: '张开长焦 / 捏合广角'),
                const VantCell(title: '单指单击画面', value: '自动对焦 (AF Drive)'),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PowerProtectionDetail extends StatelessWidget {
  _PowerProtectionDetail();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return _SettingsDetailScaffold(
          title: '电池与传输保护',
          children: [
            VantCellGroup(
              title: '低电量传输保护',
              children: [
                VantCell(
                  title: '启用低电量传输保护',
                  customValue: Switch(
                    value: settings.powerProtectionEnabled,
                    onChanged: settings.setPowerProtectionEnabled,
                  ),
                ),
                VantCell(
                  title: '电量暂停保护阈值',
                  value: '${settings.powerThreshold}%',
                  isLink: true,
                  onTap: () {
                    const options = AppSettings.powerThresholdOptions;
                    final index = options.indexOf(settings.powerThreshold);
                    settings.setPowerThreshold(options[(index + 1) % options.length]);
                  },
                ),
                const VantCell(
                  title: '迟滞恢复机制 (+5%)',
                  value: '电量回升至阈值 +5% 自动恢复',
                ),
                const VantCell(
                  title: '正在传输任务',
                  value: '完成当前文件写入后再暂停 (不截断)',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DiagnosticsDetail extends StatelessWidget {
  _DiagnosticsDetail();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        return _SettingsDetailScaffold(
          title: '诊断与日志',
          children: [
            VantCellGroup(
              title: '协议通信诊断',
              children: [
                VantCell(
                  title: '查看协议握手与通信日志',
                  value: '${AppLogManager.instance.logs.length} 条记录',
                  isLink: true,
                  onTap: () => _showLogsViewerSheet(context),
                ),
                VantCell(
                  title: '清空通信诊断日志',
                  value: '清空',
                  isLink: true,
                  onTap: () {
                    AppLogManager.instance.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: const Text('已清空全部日志')),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AboutDetail extends StatelessWidget {
  _AboutDetail();

  @override
  Widget build(BuildContext context) {
    return _SettingsDetailScaffold(
      title: '关于 SnapLink',
      children: [
        VantCellGroup(
          title: '版本与更新',
          children: [
            VantCell(
              title: '应用版本',
              value: 'v${AppUpdateManager.currentVersion} (Build ${AppUpdateManager.currentVersionCode})',
            ),
            VantCell(
              title: '检查新版本',
              value: '在线检测 (Gitee / GitHub)',
              isLink: true,
              onTap: () => AppUpdateManager.checkManually(context),
            ),
          ],
        ),
        const VantCellGroup(
          title: '技术信息',
          children: [
            const VantCell(title: '驱动架构', value: 'Wi-Fi PTP/IP + USB PTP (Dart/Kotlin)'),
            const VantCell(title: 'UI 体系', value: 'Flutter Vant UI 摄影监看系统'),
          ],
        ),
        VantCellGroup(
          title: '开源与许可',
          children: [
            VantCell(
              title: 'SnapLink 项目主页',
              value: 'Gitee / MIT License',
              isLink: true,
              onTap: () => CameraNativeBridge.openUrlInBrowser(
                'https://gitee.com/lyb82ndkkkl/Nikon-SnapLink',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

void _showLogsViewerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final context=sheetCtx;
          final logs = AppLogManager.instance.logs;
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(16),
            color: SnapColors.of(context).surface,
            child: Column(
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
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '底层协议通信与握手日志',
                      style: TextStyle(
                        color: SnapColors.of(context).textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.copy, size: 18, color: SnapColors.of(context).primary),
                          tooltip: '复制全部日志',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: logs.join('\n')));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: const Text('已复制全部通信日志至剪贴板')),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: SnapColors.of(context).danger),
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
                      color: SnapColors.of(context).background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SnapColors.of(context).border),
                    ),
                    child: logs.isEmpty
                        ? Center(
                            child: Text(
                              '暂无通信日志',
                              style: TextStyle(color: SnapColors.of(context).textTertiary, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            itemCount: logs.length,
                            itemBuilder: (c, i) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                logs[i],
                                style: TextStyle(
                                  color: logs[i].contains('失败') || logs[i].contains('异常')
                                      ? SnapColors.of(context).danger
                                      : (logs[i].contains('成功')
                                          ? SnapColors.of(context).success
                                          : SnapColors.of(context).textSecondary),
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
