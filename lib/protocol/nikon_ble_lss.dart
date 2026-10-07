import 'dart:typed_data';

/// 尼康专有蓝牙服务 LSS (Link Sub-System) 协议常量与编解码器
/// 源自官方 SnapBridge 逆向 (BleLssService.java / AbstractC2052k.java)
class NikonBleLss {
  NikonBleLss._();

  // ==========================================
  // 1. 官方 18 个 GATT UUID 定义 (全小写标准格式)
  // ==========================================
  static const String serviceLss = "0000de00-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charAuthentication = "00002000-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charPowerControl = "00002001-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charClientDeviceName = "00002002-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charServerDeviceName = "00002003-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charConnectionConfiguration = "00002004-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charConnectionEstablishment = "00002005-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charCurrentTime = "00002006-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charLocationInformation = "00002007-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charLssControlPoint = "00002008-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charLssFeature = "00002009-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charBatteryLevel = "00002a19-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charLssSerialNumber = "0000200b-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charLssCategoryInfo = "00002080-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charLssStatusForCapture = "00002081-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charLssStatusForControl = "00002020-3dd4-4255-8d62-6dc7b9bd5561";
  static const String charControlPointForControl = "00002021-3dd4-4255-8d62-6dc7b9bd5561";

  // ==========================================
  // 2. 指令构建器
  // ==========================================

  /// 构建命令相机开启 Wi-Fi AP 的 Control Point 指令 (写入 0x2008)
  /// [subCmd]: 1=启动 Wi-Fi, 2=关闭 Wi-Fi
  static Uint8List buildWifiControlCommand({required bool enable}) {
    return Uint8List.fromList([
      0x01,             // 命令类目: Wi-Fi 启停
      enable ? 0x01 : 0x02, // 1: 开启, 2: 关闭
      0x00, 0x00        // 保留字段
    ]);
  }

  /// 构建时间同步指令 (写入 0x2006)
  static Uint8List buildCurrentTimePayload(DateTime time) {
    final bb = BytesBuilder();
    final bd = ByteData(7);
    bd.setUint16(0, time.year, Endian.little);
    bd.setUint8(2, time.month);
    bd.setUint8(3, time.day);
    bd.setUint8(4, time.hour);
    bd.setUint8(5, time.minute);
    bd.setUint8(6, time.second);
    bb.add(bd.buffer.asUint8List());
    return bb.toBytes();
  }

  // ==========================================
  // 3. 载荷解码器 (读取 0x2004 ConnectionConfiguration)
  // ==========================================

  /// 解码读取到的相机 Wi-Fi AP 凭证
  static NikonBleWifiConfig? parseConnectionConfiguration(Uint8List rawBytes) {
    if (rawBytes.length < 98) return null;

    final mask = rawBytes[0];
    final hasWifi = (mask & 0x01) > 0;
    if (!hasWifi) return null;

    // SSID 位于 1..32 (32 字节以 Null 结尾)
    final ssidBytes = rawBytes.sublist(1, 33);
    final ssid = _decodeNullTerminatedAscii(ssidBytes);

    // 密码位于 33..96 (64 字节以 Null 结尾)
    final pwdBytes = rawBytes.sublist(33, 97);
    final password = _decodeNullTerminatedAscii(pwdBytes);

    // 加密类型位于 97
    final encryptCode = rawBytes[97];

    return NikonBleWifiConfig(
      ssid: ssid,
      password: password,
      encryptMode: encryptCode,
    );
  }

  static String _decodeNullTerminatedAscii(Uint8List bytes) {
    int end = bytes.indexOf(0);
    if (end < 0) end = bytes.length;
    final sub = bytes.sublist(0, end);
    return String.fromCharCodes(sub.where((c) => c >= 32 && c <= 126)).trim();
  }
}

/// 相机 Wi-Fi 配置信息模型
class NikonBleWifiConfig {
  final String ssid;
  final String password;
  final int encryptMode; // 0=Open, 1=WPA2, 2=WPA3, 3=WPA2/WPA3

  const NikonBleWifiConfig({
    required this.ssid,
    required this.password,
    required this.encryptMode,
  });

  bool get isOpen => encryptMode == 0 || password.isEmpty;

  @override
  String toString() => 'NikonBleWifiConfig(ssid: $ssid, isOpen: $isOpen, security: $encryptMode)';
}
