import 'dart:async';
import 'package:flutter/services.dart';

/// 蓝牙设备元数据模型
class BleDeviceInfo {
  final String name;
  final String address;
  final int rssi;
  final bool isNikon;

  BleDeviceInfo({
    required this.name,
    required this.address,
    required this.rssi,
    required this.isNikon,
  });

  factory BleDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return BleDeviceInfo(
      name: map['name'] as String? ?? '未知设备',
      address: map['address'] as String? ?? '',
      rssi: (map['rssi'] as num?)?.toInt() ?? -100,
      isNikon: map['isNikon'] as bool? ?? false,
    );
  }
}

/// Wi-Fi 网络状态模型
class WifiNetworkInfo {
  final bool connected;
  final bool bound;
  final String ssid;
  final String gateway;
  final String ip;

  WifiNetworkInfo({
    required this.connected,
    required this.bound,
    required this.ssid,
    required this.gateway,
    required this.ip,
  });

  factory WifiNetworkInfo.fromMap(Map<dynamic, dynamic> map) {
    return WifiNetworkInfo(
      connected: map['connected'] as bool? ?? false,
      bound: map['bound'] as bool? ?? false,
      ssid: map['ssid'] as String? ?? '<未知>',
      gateway: map['gateway'] as String? ?? '192.168.0.1',
      ip: map['ip'] as String? ?? '192.168.0.2',
    );
  }
}

/// SnapLink 原生相机与系统能力桥接
/// 包含：Wi-Fi 进程强绑定、网关嗅探、系统设置跳转、蓝牙 BLE 扫描与快门遥控
class CameraNativeBridge {
  static const MethodChannel _channel = MethodChannel('com.nikon.snaplink/native_camera');

  // ========================================================
  // Wi-Fi 进程绑定与网络探测
  // ========================================================

  /// 绑定当前进程到相机 Wi-Fi 热点网卡（解决 Android 10+ 自动跳蜂窝数据问题）
  static Future<WifiNetworkInfo> bindCameraWifi({String? targetHost}) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('bindCameraWifi', {
        if (targetHost != null) 'targetHost': targetHost,
      });
      if (res != null) {
        return WifiNetworkInfo.fromMap(res);
      }
    } catch (_) {}
    return WifiNetworkInfo(
      connected: false,
      bound: false,
      ssid: '<未知>',
      gateway: '192.168.1.1',
      ip: '192.168.1.2',
    );
  }

  /// 获取当前 Wi-Fi 信息 (SSID, Gateway IP, 本机 IP)
  static Future<WifiNetworkInfo> getWifiInfo() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getWifiInfo');
      if (res != null) {
        return WifiNetworkInfo.fromMap(res);
      }
    } catch (_) {}
    return WifiNetworkInfo(
      connected: false,
      bound: false,
      ssid: '<未知>',
      gateway: '192.168.0.1',
      ip: '192.168.0.2',
    );
  }

  /// 解除进程网络绑定并释放 Wi-Fi 性能锁
  static Future<void> unbindWifi() async {
    try {
      await _channel.invokeMethod('unbindWifi');
    } catch (_) {}
  }

  /// 打开 Android 系统 Wi-Fi 设置界面
  static Future<void> openWifiSettings() async {
    try {
      await _channel.invokeMethod('openWifiSettings');
    } catch (_) {}
  }

  // ========================================================
  // 蓝牙 BLE 扫描与遥控
  // ========================================================

  /// 检查蓝牙是否已开启
  static Future<bool> isBluetoothEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isBluetoothEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开 Android 系统蓝牙设置
  static Future<void> openBluetoothSettings() async {
    try {
      await _channel.invokeMethod('openBluetoothSettings');
    } catch (_) {}
  }

  /// 开始扫描低功耗蓝牙 (BLE) 设备
  static Future<bool> startBleScan() async {
    try {
      final res = await _channel.invokeMethod<bool>('startBleScan');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 停止扫描 BLE 设备
  static Future<void> stopBleScan() async {
    try {
      await _channel.invokeMethod('stopBleScan');
    } catch (_) {}
  }

  /// 获取已扫描到的 BLE 设备列表
  static Future<List<BleDeviceInfo>> getScannedBleDevices() async {
    try {
      final list = await _channel.invokeMethod<List<dynamic>>('getScannedBleDevices');
      if (list != null) {
        return list
            .map((item) => BleDeviceInfo.fromMap(item as Map<dynamic, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// 连接指定的 BLE 蓝牙设备
  static Future<Map<String, dynamic>> connectBleDevice(String address) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('connectBleDevice', {
        'address': address,
      });
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      return {'status': 'error', 'error': e.toString()};
    }
    return {'status': 'error'};
  }

  /// 断开蓝牙连接
  static Future<void> disconnectBleDevice() async {
    try {
      await _channel.invokeMethod('disconnectBleDevice');
    } catch (_) {}
  }

  /// 发送快门控制指令 ('half_press', 'shutter', 'record_video', 'release')
  static Future<bool> sendBleShutterCommand(String command) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('sendBleShutterCommand', {
        'command': command,
      });
      return res?['success'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 查询当前蓝牙连接状态
  static Future<Map<String, dynamic>> getBleStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getBleStatus');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {'status': 'disconnected', 'deviceName': ''};
  }

  // ========================================================
  // 设备电量与省电保护
  // ========================================================

  /// 获取手机电池电量与省电模式 (SnapBridge-Enhanced 规范)
  static Future<Map<String, dynamic>> getDevicePowerInfo() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDevicePowerInfo');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {
      'level': 100,
      'isCharging': false,
      'isPowerSaveMode': false,
    };
  }

  /// 通知系统媒体库扫描新下载的照片/视频，使其立即出现在系统相册中
  static Future<void> notifyMediaScan(String path) async {
    try {
      await _channel.invokeMethod('notifyMediaScan', {'path': path});
    } catch (_) {}
  }

  /// 从手机本地相册选择一张图片，返回该图片的本地缓存路径
  static Future<String?> pickImageFromGallery() async {
    try {
      final res = await _channel.invokeMethod<String>('pickImage');
      return res;
    } catch (_) {
      return null;
    }
  }

  /// 将离线渲染或导出的照片保存至系统公共相册 (Pictures/SnapLink)，并触发媒体扫描
  static Future<String?> saveImageToGallery(String srcPath) async {
    try {
      final res = await _channel.invokeMethod<String>('saveImageToGallery', {'srcPath': srcPath});
      return res;
    } catch (_) {
      return null;
    }
  }

  /// 将相机下载到的临时文件按内容类型保存到系统公共媒体库（图片/视频/RAW）。
  /// 成功返回 MediaStore Uri（或旧系统路径），失败返回 null。
  static Future<String?> saveMediaToGallery(String srcPath, String fileName) async {
    try {
      final res = await _channel.invokeMethod<String>('saveMediaToGallery', {
        'srcPath': srcPath,
        'fileName': fileName,
      });
      return res;
    } catch (_) {
      return null;
    }
  }

  /// 调起 Android 原生包安装器安装指定的本地 APK 文件
  static Future<bool> installApk(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 唤起系统默认外部浏览器打开指定 URL
  static Future<bool> openUrlInBrowser(String url) async {
    try {
      final res = await _channel.invokeMethod<bool>('openUrlInBrowser', {'url': url});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
  // ========================================================
  // USB PTP over OTG
  // ========================================================

  /// 枚举已接入的 USB 设备（含授权状态与尼康厂商识别）。
  static Future<List<UsbDeviceInfo>> listUsbDevices() async {
    try {
      final list = await _channel.invokeMethod<List<dynamic>>('listUsbDevices');
      if (list != null) {
        return list.map((e) => UsbDeviceInfo.fromMap(e as Map<dynamic, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 请求指定 USB 设备的访问权限，返回是否授权成功。
  static Future<bool> requestUsbPermission(String deviceName) async {
    try {
      final res =
          await _channel.invokeMethod<bool>('requestUsbPermission', {'deviceName': deviceName});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开 USB PTP 会话（claim 接口 + OpenSession），返回会话 ID。
  static Future<String?> usbOpenSession(String deviceName) async {
    try {
      return await _channel.invokeMethod<String>('usbOpenSession', {'deviceName': deviceName});
    } catch (_) {
      return null;
    }
  }

  static Future<void> usbCloseSession(String deviceId) async {
    try {
      await _channel.invokeMethod('usbCloseSession', {'deviceId': deviceId});
    } catch (_) {}
  }

  /// 读取相机 DeviceInfo 原始负载（与 Wi-Fi 通道 0x1001 返回一致）。
  static Future<Uint8List?> usbQueryDeviceInfo(String deviceId) async {
    try {
      return await _channel.invokeMethod<Uint8List>('usbQueryDeviceInfo', {'deviceId': deviceId});
    } catch (_) {
      return null;
    }
  }

  /// 无数据阶段 PTP 指令。
  static Future<void> usbExecuteOperation(
    String deviceId,
    int opCode, [
    List<int> params = const [],
  ]) async {
    await _channel.invokeMethod('usbExecuteOperation', {
      'deviceId': deviceId,
      'opCode': opCode,
      'params': params,
    });
  }

  /// 数据输入阶段 PTP 指令（相机 -> 手机）。
  static Future<Uint8List> usbExecuteDataIn(
    String deviceId,
    int opCode, [
    List<int> params = const [],
  ]) async {
    final res = await _channel.invokeMethod<Uint8List>('usbExecuteDataIn', {
      'deviceId': deviceId,
      'opCode': opCode,
      'params': params,
    });
    return res ?? Uint8List(0);
  }

  /// 数据输出阶段 PTP 指令（手机 -> 相机）。
  static Future<void> usbExecuteDataOut(
    String deviceId,
    int opCode,
    Uint8List data, [
    List<int> params = const [],
  ]) async {
    await _channel.invokeMethod('usbExecuteDataOut', {
      'deviceId': deviceId,
      'opCode': opCode,
      'data': data,
      'params': params,
    });
  }
}

/// USB 设备元数据模型
class UsbDeviceInfo {
  final String deviceName;
  final int vendorId;
  final int productId;
  final String name;
  final bool hasPermission;
  final bool isNikon;

  UsbDeviceInfo({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.name,
    required this.hasPermission,
    required this.isNikon,
  });

  factory UsbDeviceInfo.fromMap(Map<dynamic, dynamic> map) => UsbDeviceInfo(
        deviceName: (map['deviceName'] as String?) ?? '',
        vendorId: (map['vendorId'] as num?)?.toInt() ?? 0,
        productId: (map['productId'] as num?)?.toInt() ?? 0,
        name: (map['name'] as String?) ?? 'USB Camera',
        hasPermission: map['hasPermission'] as bool? ?? false,
        isNikon: map['isNikon'] as bool? ?? false,
      );

  String get vendorProductHex =>
      '0x${vendorId.toRadixString(16).padLeft(4, '0').toUpperCase()}:'
      '0x${productId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}