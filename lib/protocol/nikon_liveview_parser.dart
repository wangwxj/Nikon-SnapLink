import 'dart:typed_data';

/// 对焦状态 (UI 渲染对焦框颜色)
enum NikonFocusState {
  unknown,  // 测距中 / 未知 (灰色)
  deviated, // 未合焦 (红色)
  match,    // 准确合焦 (绿色)
}

/// 画面旋转朝向
enum NikonRotationDirection {
  noRotation,       // 正常横向 (0°)
  counterClockwise, // 逆时针 90°
  clockwise,        // 顺时针 90° (竖幅拍摄)
  upsideDown,       // 倒置 180°
}

/// 对焦区域框 (以相机取景坐标系为基准)
class NikonAfBox {
  final int x;
  final int y;
  final int width;
  final int height;

  const NikonAfBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  String toString() => 'NikonAfBox(x: $x, y: $y, w: $width, h: $height)';
}

/// 电子水平仪数据
class NikonLevelInfo {
  final double rollAngle;  // 横滚角 (左右倾斜度)
  final double pitchAngle; // 俯仰角 (前后俯仰度)
  final double yawAngle;   // 偏航角

  const NikonLevelInfo({
    this.rollAngle = 0.0,
    this.pitchAngle = 0.0,
    this.yawAngle = 0.0,
  });
}

/// 尼康 LiveView 取景解析后的完整数据帧模型
class NikonLiveViewFrame {
  final Uint8List jpegData;
  final int version; // 1 = 经典 DSLR (384B 头), 2 = 微单 Z系列 (1024B 头)
  final int jpegWidth;
  final int jpegHeight;
  final int wholeWidth;
  final int wholeHeight;
  final NikonFocusState focusState;
  final bool isFocusDriving;
  final List<NikonAfBox> afBoxes;
  final int activeAfIndex;
  final NikonRotationDirection rotation;
  final NikonLevelInfo levelInfo;
  final int audioNowL;
  final int audioNowR;

  const NikonLiveViewFrame({
    required this.jpegData,
    required this.version,
    this.jpegWidth = 0,
    this.jpegHeight = 0,
    this.wholeWidth = 0,
    this.wholeHeight = 0,
    this.focusState = NikonFocusState.unknown,
    this.isFocusDriving = false,
    this.afBoxes = const [],
    this.activeAfIndex = 0,
    this.rotation = NikonRotationDirection.noRotation,
    this.levelInfo = const NikonLevelInfo(),
    this.audioNowL = 0,
    this.audioNowR = 0,
  });
}

/// 尼康专有 LiveView 二进制数据帧解包器
/// 100% 还原官方 SnapBridge b8.java (Ver 2) 与 a8.java (Ver 1) 逆向逻辑
class NikonLiveViewParser {
  NikonLiveViewParser._();

  /// 解包完整的取景二进制字节流 (支持 Version 2、Version 1 与直接 JPEG 流智能容错)
  static NikonLiveViewFrame? parse(Uint8List rawPayload) {
    if (rawPayload.length < 2) return null;

    // 0. 快速路径: 若开头直接就是 JPEG 魔数 0xFF 0xD8 (如纯 JPEG 抓流、WMU 模式或部分机型直出)
    if (rawPayload[0] == 0xFF && rawPayload[1] == 0xD8) {
      final eoi = _findJpegEoi(rawPayload, 2);
      final jpegBytes = (eoi > 2 && eoi <= rawPayload.length)
          ? rawPayload.sublist(0, eoi)
          : rawPayload;
      return NikonLiveViewFrame(
        jpegData: jpegBytes,
        version: 0,
      );
    }

    if (rawPayload.length < 384) {
      // 容错: 搜索任意偏移处的 JPEG SOI
      final soi = _findJpegSoi(rawPayload, 0);
      if (soi != -1) {
        final eoi = _findJpegEoi(rawPayload, soi + 2);
        final jpegBytes = (eoi > soi && eoi <= rawPayload.length)
            ? rawPayload.sublist(soi, eoi)
            : rawPayload.sublist(soi);
        return NikonLiveViewFrame(
          jpegData: jpegBytes,
          version: 0,
        );
      }
      return null;
    }

    final bd = ByteData.sublistView(rawPayload);
    final majorVer = bd.getUint16(0, Endian.little);

    // ==========================================
    // 分支 1: Version 2 (Z系列微单: Z9/Z8/Z6III/Z7II/Zfc/Z50 等)
    // 头部固定 1024 字节
    // ==========================================
    if (majorVer == 2 && rawPayload.length >= 1024) {
      final jpegLen = bd.getUint32(12, Endian.little);
      final jpegW = bd.getUint16(16, Endian.little);
      final jpegH = bd.getUint16(18, Endian.little);
      final wholeW = bd.getUint16(20, Endian.little);
      final wholeH = bd.getUint16(22, Endian.little);

      final focusDriveVal = rawPayload[35];
      final isDriving = focusDriveVal == 1;

      final focusStateVal = rawPayload[36];
      NikonFocusState focusState = NikonFocusState.unknown;
      if (focusStateVal == 1) focusState = NikonFocusState.deviated;
      if (focusStateVal == 2) focusState = NikonFocusState.match;

      final afCount = rawPayload[38];
      final afFacialIndex = rawPayload[39];

      // 读取对焦框 (96 个槽位，每个 8 字节: [X: 2B] [Y: 2B] [W: 2B] [H: 2B])
      final afList = <NikonAfBox>[];
      final validCount = afCount > 96 ? 96 : afCount;
      for (int i = 0; i < validCount; i++) {
        final boxOffset = 40 + (i * 8);
        if (boxOffset + 8 <= 1024) {
          final x = bd.getInt16(boxOffset, Endian.little);
          final y = bd.getInt16(boxOffset + 2, Endian.little);
          final w = bd.getInt16(boxOffset + 4, Endian.little);
          final h = bd.getInt16(boxOffset + 6, Endian.little);
          if (w > 0 && h > 0) {
            afList.add(NikonAfBox(x: x, y: y, width: w, height: h));
          }
        }
      }

      // 音频电平与水平仪 (偏移 808 起)
      final audioL = rawPayload[808];
      final audioR = rawPayload[809];
      final rotVal = rawPayload[812];
      NikonRotationDirection rotation = NikonRotationDirection.noRotation;
      if (rotVal == 1) rotation = NikonRotationDirection.counterClockwise;
      if (rotVal == 2) rotation = NikonRotationDirection.clockwise;
      if (rotVal == 3) rotation = NikonRotationDirection.upsideDown;

      // 提取 JPEG 图像流: 智能动态嗅探 SOI (0xFF 0xD8)，避免固件头填充偏移导致解码黑屏
      int soiIdx = _findJpegSoi(rawPayload, 1020);
      if (soiIdx == -1) {
        soiIdx = _findJpegSoi(rawPayload, 384);
      }
      if (soiIdx == -1) {
        soiIdx = _findJpegSoi(rawPayload, 0);
      }

      Uint8List jpegBytes;
      if (soiIdx != -1) {
        int endIdx = rawPayload.length;
        if (jpegLen > 0 && soiIdx + jpegLen <= rawPayload.length) {
          endIdx = soiIdx + jpegLen;
        } else {
          final eoiIdx = _findJpegEoi(rawPayload, soiIdx + 2);
          if (eoiIdx != -1) endIdx = eoiIdx;
        }
        jpegBytes = rawPayload.sublist(soiIdx, endIdx);
      } else {
        const headerLen = 1024;
        if (rawPayload.length >= headerLen + jpegLen && jpegLen > 0) {
          jpegBytes = rawPayload.sublist(headerLen, headerLen + jpegLen);
        } else {
          jpegBytes = rawPayload.sublist(headerLen);
        }
      }

      return NikonLiveViewFrame(
        jpegData: jpegBytes,
        version: 2,
        jpegWidth: jpegW,
        jpegHeight: jpegH,
        wholeWidth: wholeW,
        wholeHeight: wholeH,
        focusState: focusState,
        isFocusDriving: isDriving,
        afBoxes: afList,
        activeAfIndex: afFacialIndex,
        rotation: rotation,
        audioNowL: audioL,
        audioNowR: audioR,
      );
    }

    // ==========================================
    // 分支 2: Version 1 (经典单反: D850/D780/D750/D7200/D5300 等)
    // 头部固定 384 字节
    // ==========================================
    if (majorVer == 1 && rawPayload.length >= 384) {
      final jpegLenV1 = bd.getUint32(4, Endian.little);
      final rotByte = rawPayload[28] & 0x03;
      NikonRotationDirection rot = NikonRotationDirection.noRotation;
      if (rotByte == 1) rot = NikonRotationDirection.counterClockwise;
      if (rotByte == 2) rot = NikonRotationDirection.clockwise;
      if (rotByte == 3) rot = NikonRotationDirection.upsideDown;

      int soiIdx = _findJpegSoi(rawPayload, 380);
      if (soiIdx == -1) {
        soiIdx = _findJpegSoi(rawPayload, 0);
      }

      Uint8List jpegBytesV1;
      if (soiIdx != -1) {
        int endIdx = rawPayload.length;
        if (jpegLenV1 > 0 && soiIdx + jpegLenV1 <= rawPayload.length) {
          endIdx = soiIdx + jpegLenV1;
        } else {
          final eoiIdx = _findJpegEoi(rawPayload, soiIdx + 2);
          if (eoiIdx != -1) endIdx = eoiIdx;
        }
        jpegBytesV1 = rawPayload.sublist(soiIdx, endIdx);
      } else {
        const headerLenV1 = 384;
        if (rawPayload.length >= headerLenV1 + jpegLenV1 && jpegLenV1 > 0) {
          jpegBytesV1 = rawPayload.sublist(headerLenV1, headerLenV1 + jpegLenV1);
        } else {
          jpegBytesV1 = rawPayload.sublist(headerLenV1);
        }
      }

      return NikonLiveViewFrame(
        jpegData: jpegBytesV1,
        version: 1,
        rotation: rot,
      );
    }

    // ==========================================
    // 分支 3: 全局保底智能嗅探 (非标准固件头/厂商混合封包)
    // ==========================================
    final soiFallback = _findJpegSoi(rawPayload, 0);
    if (soiFallback != -1) {
      final eoiFallback = _findJpegEoi(rawPayload, soiFallback + 2);
      final validJpeg = (eoiFallback > soiFallback && eoiFallback <= rawPayload.length)
          ? rawPayload.sublist(soiFallback, eoiFallback)
          : rawPayload.sublist(soiFallback);
      return NikonLiveViewFrame(
        jpegData: validJpeg,
        version: 0,
      );
    }

    // 无法定位任何 JPEG 标志时返回 null
    return null;
  }

  /// 搜索 JPEG 起始标记 SOI (0xFF, 0xD8)
  static int _findJpegSoi(Uint8List bytes, [int startOffset = 0]) {
    final start = startOffset.clamp(0, bytes.length);
    for (int i = start; i < bytes.length - 1; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
        return i;
      }
    }
    return -1;
  }

  /// 逆向搜索 JPEG 结束标记 EOI (0xFF, 0xD9)
  static int _findJpegEoi(Uint8List bytes, [int startOffset = 0]) {
    final start = startOffset.clamp(0, bytes.length);
    for (int i = bytes.length - 2; i >= start; i--) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
        return i + 2;
      }
    }
    return -1;
  }
}
