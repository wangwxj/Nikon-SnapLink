import 'dart:async';
import 'dart:typed_data';

import 'camera_native_bridge.dart';
import 'ptp_packet.dart';
import 'ptp_transport.dart';

/// USB (PTP over OTG) 传输实现：把 PTP 指令经由平台通道转发给原生 UsbPtpSession，
/// 与 Wi-Fi 的 [PtpIpClient] 共用同一套上层业务逻辑。
class UsbPtpTransport implements PtpTransport {
  final String deviceName;
  final void Function(String message)? onLog;

  UsbPtpTransport({required this.deviceName, this.onLog});

  String? _deviceId;
  bool _connected = false;
  final StreamController<PtpPacket> _eventController =
      StreamController<PtpPacket>.broadcast();

  @override
  bool get isConnected => _connected && _deviceId != null;

  @override
  Stream<PtpPacket> get events => _eventController.stream;

  /// USB 通道后续如需 ObjectAdded 推送，可由原生事件通道补齐；首期为空流。
  String? get deviceId => _deviceId;

  @override
  Future<void> connect() async {
    final granted = await CameraNativeBridge.requestUsbPermission(deviceName);
    if (!granted) {
      throw StateError('USB 授权被拒绝或超时');
    }
    final id = await CameraNativeBridge.usbOpenSession(deviceName);
    if (id == null || id.isEmpty) {
      throw StateError('USB PTP 会话建立失败');
    }
    _deviceId = id;
    _connected = true;
    onLog?.call('USB PTP 会话已建立: $id');
  }

  @override
  Future<void> disconnect() async {
    final id = _deviceId;
    _connected = false;
    _deviceId = null;
    if (id != null) {
      await CameraNativeBridge.usbCloseSession(id);
    }
    onLog?.call('USB PTP 会话已关闭');
  }

  String get _requireId {
    final id = _deviceId;
    if (id == null) throw StateError('USB 会话未建立');
    return id;
  }

  @override
  Future<void> executeOperation(int opCode, [List<int> params = const []]) {
    return CameraNativeBridge.usbExecuteOperation(_requireId, opCode, params);
  }

  @override
  Future<Uint8List> executeDataIn(int opCode, [List<int> params = const []]) {
    return CameraNativeBridge.usbExecuteDataIn(_requireId, opCode, params);
  }

  @override
  Future<void> executeDataOut(int opCode, Uint8List data, [List<int> params = const []]) {
    return CameraNativeBridge.usbExecuteDataOut(_requireId, opCode, data, params);
  }

  void dispose() {
    _eventController.close();
  }
}
