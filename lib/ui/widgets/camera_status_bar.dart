import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../protocol/camera_driver.dart';

/// 顶部专业相机状态指示栏 (Camera StatusBar)
class CameraStatusBar extends StatelessWidget {
  final CameraDriver driver;
  final int fps;

  const CameraStatusBar({
    super.key,
    required this.driver,
    this.fps = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = driver.isConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SnapColors.surface,
        border: Border(bottom: BorderSide(color: SnapColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          // 状态指示圆点
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? SnapColors.success : SnapColors.danger,
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? SnapColors.success : SnapColors.danger).withAlpha(100),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 相机型号
          Text(
            isConnected ? driver.cameraModel : '相机未连接',
            style: TextStyle(
              color: SnapColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          const Spacer(),

          if (isConnected) ...[
            // FPS 指示器
            if (fps > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SnapColors.cardElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$fps FPS',
                  style: TextStyle(
                    color: SnapColors.primary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // 存储卡指示
            Icon(Icons.sd_card_outlined, size: 14, color: SnapColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              driver.isSingleSlotCamera ? 'SD卡' : 'SLOT 1',
              style: TextStyle(color: SnapColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(width: 10),

            // 电量指示
            Icon(Icons.battery_5_bar, size: 16, color: SnapColors.success),
            Text(
              '${driver.batteryLevel}%',
              style: TextStyle(color: SnapColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
            ),
          ] else ...[
            Text(
              '点击连接',
              style: TextStyle(color: SnapColors.primary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
