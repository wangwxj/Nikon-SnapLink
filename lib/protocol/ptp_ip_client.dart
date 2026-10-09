import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../core/constants/ptp_opcodes.dart';
import '../core/settings/app_settings.dart';
import '../core/utils/byte_buffer_ext.dart';
import 'ptp_packet.dart';

/// PTP 通信异常
class PtpException implements Exception {
  final int opCode;
  final int responseCode;
  final String message;

  PtpException(this.opCode, this.responseCode, [this.message = 'PTP 操作异常']);

  @override
  String toString() => 'PtpException(opCode: 0x${opCode.toRadixString(16)}, code: 0x${responseCode.toRadixString(16)}, msg: $message)';
}

/// 纯 Dart PTP/IP 双通道 Socket 客户端
/// 100% 对齐原版反编译 CameraSyncForegroundService.java 握手时序与字节流规范
class PtpIpClient {
  final String host;
  final int port;
  final void Function(String message)? onLog;

  Socket? _cmdSocket;
  Socket? _eventSocket;

  int _transactionId = 0;
  int _connectionNumber = 0;
  bool _isConnected = false;
  Timer? _heartbeatTimer;

  final StreamController<PtpPacket> _eventController = StreamController<PtpPacket>.broadcast();
  final BytesBuilder _cmdReceiveBuffer = BytesBuilder();
  final BytesBuilder _eventReceiveBuffer = BytesBuilder();

  Completer<PtpPacket>? _pendingCmdAckCompleter;
  Completer<PtpPacket>? _pendingEventAckCompleter;
  Completer<PtpPacket>? _pendingResponseCompleter;
  BytesBuilder? _incomingDataBuffer;

  PtpIpClient({
    this.host = '192.168.1.1',
    this.port = 15740,
    this.onLog,
  });

  bool get isConnected => _isConnected;
  int get transactionId => _transactionId;
  Stream<PtpPacket> get events => _eventController.stream;

  void _log(String msg) {
    if (onLog != null) {
      onLog!(msg);
    }
  }

  /// 连接相机并执行严格的 PTP/IP 双通道规范握手
  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    if (_isConnected) return;

    _log('【握手1/7】正在连接命令通道 TCP $host:$port ...');
    _cmdSocket = await Socket.connect(host, port, timeout: timeout);
    _cmdSocket!.listen(
      _onCommandData,
      onError: (err) {
        _log('命令通道异常断开: $err');
        disconnect();
      },
      onDone: () {
        _log('命令通道连接关闭');
        disconnect();
      },
    );

    // 发送 InitCommandRequest (Packet Type = 1)
    // 负载: [16B GUID] + [UTF-16LE 友好名] + [2B 0x0000] + [4B 0x00010000]
    _log('【握手2/7】发送 InitCommandRequest (Type 1, 协议版本 1.0) ...');
    final initCmdPacket = PtpPacket.buildInitCommandRequest(clientName: 'Android Device');
    final cmdCompleter = Completer<PtpPacket>();
    _pendingCmdAckCompleter = cmdCompleter;
    _cmdSocket!.add(initCmdPacket.toBytes());

    // 等待 InitCommandAck (Packet Type = 2)
    final ack = await cmdCompleter.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('等待 InitCommandAck 超时 (相机未响应命令通道握手)'),
    );
    _pendingCmdAckCompleter = null;

    if (ack.payload.length < 4) {
      throw PtpException(0, 0, 'InitCommandAck 载荷异常 (长度小于 4 字节)');
    }
    _connectionNumber = ack.getUint32(0);
    _log('【握手3/7】收到 InitCommandAck，分配 ConnectionNumber: 0x${_connectionNumber.toRadixString(16)}');

    // 建立事件通道 Event Socket
    _log('【握手4/7】正在连接事件监听通道 TCP $host:$port ...');
    _eventSocket = await Socket.connect(host, port, timeout: timeout);
    _eventSocket!.listen(
      _onEventData,
      onError: (err) {
        _log('事件通道异常断开: $err');
        disconnect();
      },
      onDone: () {
        _log('事件通道连接关闭');
        disconnect();
      },
    );

    // 发送 InitEventRequest (Packet Type = 3)
    _log('【握手5/7】发送 InitEventRequest (Type 3, 绑定会话编号) ...');
    final initEventPacket = PtpPacket.buildInitEventRequest(_connectionNumber);
    final eventCompleter = Completer<PtpPacket>();
    _pendingEventAckCompleter = eventCompleter;
    _eventSocket!.add(initEventPacket.toBytes());

    // 关键：必须等待相机响应 InitEventAck (Packet Type = 4)
    _log('【握手6/7】等待相机返回 InitEventAck (Type 4) 确认 ...');
    await eventCompleter.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('等待 InitEventAck 超时 (相机未响应事件通道绑定)'),
    );
    _pendingEventAckCompleter = null;
    _log('【握手6/7】事件通道绑定确认成功！双通道握手完成。');

    // 开启 PTP 会话 (0x1002 OpenSession, SessionID = 1)
    _log('【握手7/7】发送 OpenSession (0x1002, SessionID=1) 开启主会话 ...');
    _isConnected = true;
    await executeOperation(PtpOpCodes.openSession, [1]);
    _log('PTP 会话完全就绪！');

    // 启动心跳保活定时器
    _startHeartbeat();
  }

  Future<void>? _currentOpFuture;

  /// 严格的 PTP 命令互斥锁 (FIFO 串行化，防止并发请求冲撞导致 Socket 数据交织)
  Future<T> _synchronized<T>(Future<T> Function() action) async {
    final prev = _currentOpFuture;
    final completer = Completer<void>();
    _currentOpFuture = completer.future;

    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  /// 发送指令并接收 OperationResponse (不带数据包)
  Future<void> executeOperation(int opCode, [List<int> params = const []]) {
    return _synchronized(() async {
      _transactionId++;
      final req = PtpPacket.buildOperationRequest(
        opCode: opCode,
        transactionId: _transactionId,
        params: params,
      );

      final completer = Completer<PtpPacket>();
      _pendingResponseCompleter = completer;
      _cmdSocket!.add(req.toBytes());

      try {
        final resp = await completer.future.timeout(
          const Duration(seconds: 6),
          onTimeout: () => throw TimeoutException('操作 0x${opCode.toRadixString(16)} 响应超时 (6秒未返回)'),
        );
        final respCode = resp.getUint16(0);
        // 对齐 SnapBridge o9.java 规范: 0x2001 (OK) 或 0x201E (SessionAlreadyOpen) 均视为正常
        if (respCode != PtpOpCodes.responseOk) {
          if (opCode == PtpOpCodes.openSession && respCode == PtpOpCodes.responseSessionAlreadyOpen) {
            _log('相机主会话已处于开启状态 (0x201E)，直接复用。');
          } else {
            throw PtpException(opCode, respCode, '相机返回失败代码 0x${respCode.toRadixString(16)}');
          }
        }
      } finally {
        if (_pendingResponseCompleter == completer) {
          _pendingResponseCompleter = null;
        }
      }
    });
  }

  /// 发送指令并接收返回的大块二进制数据 (例如 LiveView JPEG 帧、照片分块)
  Future<Uint8List> executeDataIn(int opCode, [List<int> params = const []]) {
    return _synchronized(() async {
      _transactionId++;
      final req = PtpPacket.buildOperationRequest(
        opCode: opCode,
        transactionId: _transactionId,
        params: params,
      );

      final completer = Completer<PtpPacket>();
      _pendingResponseCompleter = completer;
      _incomingDataBuffer = BytesBuilder();

      _cmdSocket!.add(req.toBytes());

      try {
        final resp = await completer.future.timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException('数据拉取 0x${opCode.toRadixString(16)} 响应超时'),
        );
        final respCode = resp.getUint16(0);
        if (respCode != PtpOpCodes.responseOk) {
          _incomingDataBuffer = null;
          throw PtpException(opCode, respCode, '数据读取指令 0x${opCode.toRadixString(16)} 失败 (代码 0x${respCode.toRadixString(16)})');
        }

        final data = _incomingDataBuffer?.toBytes() ?? Uint8List(0);
        _incomingDataBuffer = null;
        return data;
      } finally {
        if (_pendingResponseCompleter == completer) {
          _pendingResponseCompleter = null;
        }
      }
    });
  }

  /// 发送指令与待写入的数据负载 (Data-Out Phase, 用于 SetDevicePropValue 等属性设置)
  Future<void> executeDataOut(int opCode, Uint8List data, [List<int> params = const []]) {
    return _synchronized(() async {
      _transactionId++;

      // 1. 发送 OperationRequest (Type = 6, DataPhase = 2 代表下发数据)
      final req = PtpPacket.buildOperationRequest(
        opCode: opCode,
        transactionId: _transactionId,
        params: params,
        dataPhase: 2,
      );

      // 2. 构造 StartDataPacket (Type = 9, 20 字节)
      final startDataBuf = PtpByteBuffer();
      startDataBuf.writeUint32(20);
      startDataBuf.writeUint32(PtpOpCodes.ptpIpStartDataPacket);
      startDataBuf.writeUint32(_transactionId);
      startDataBuf.writeUint64(data.length);

      // 3. 构造 EndDataPacket (Type = 12, 12 + data.length 字节)
      final endDataBuf = PtpByteBuffer();
      endDataBuf.writeUint32(12 + data.length);
      endDataBuf.writeUint32(PtpOpCodes.ptpIpEndDataPacket);
      endDataBuf.writeUint32(_transactionId);
      endDataBuf.writeBytes(data);

      final completer = Completer<PtpPacket>();
      _pendingResponseCompleter = completer;

      _cmdSocket!.add(req.toBytes());
      _cmdSocket!.add(startDataBuf.toBytes());
      _cmdSocket!.add(endDataBuf.toBytes());

      try {
        final resp = await completer.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException('数据写入 0x${opCode.toRadixString(16)} 响应超时'),
        );
        final respCode = resp.getUint16(0);
        if (respCode != PtpOpCodes.responseOk) {
          throw PtpException(opCode, respCode, '数据下发指令 0x${opCode.toRadixString(16)} 失败 (代码 0x${respCode.toRadixString(16)})');
        }
      } finally {
        if (_pendingResponseCompleter == completer) {
          _pendingResponseCompleter = null;
        }
      }
    });
  }

  /// 处理命令通道收到的字节流与拆包
  void _onCommandData(Uint8List chunk) {
    _cmdReceiveBuffer.add(chunk);
    var bufferBytes = _cmdReceiveBuffer.toBytes();

    while (bufferBytes.length >= 8) {
      final packet = PtpPacket.parse(bufferBytes);
      if (packet == null) break; // 粘包未完整到达

      final remaining = bufferBytes.sublist(packet.length);
      _cmdReceiveBuffer.clear();
      _cmdReceiveBuffer.add(remaining);
      bufferBytes = remaining;

      // 分发包类型
      if (packet.type == PtpOpCodes.ptpIpInitCommandAck) {
        // InitCommandAck (Type = 2)
        if (_pendingCmdAckCompleter != null && !_pendingCmdAckCompleter!.isCompleted) {
          _pendingCmdAckCompleter!.complete(packet);
        }
      } else if (packet.type == PtpOpCodes.ptpIpStartDataPacket) {
        // 数据流开始
      } else if (packet.type == PtpOpCodes.ptpIpDataPacket || packet.type == PtpOpCodes.ptpIpEndDataPacket) {
        // 数据分片追加 (跳过 4 字节事务 ID)
        if (packet.payload.length > 4) {
          _incomingDataBuffer?.add(packet.payload.sublist(4));
        }
      } else if (packet.type == PtpOpCodes.ptpIpOperationResponse) {
        // 操作完成响应 (Type = 7)
        if (_pendingResponseCompleter != null && !_pendingResponseCompleter!.isCompleted) {
          _pendingResponseCompleter!.complete(packet);
        }
      }
    }
  }

  /// 处理事件通道推送的事件包 (接收 InitEventAck 与异步事件通知)
  void _onEventData(Uint8List chunk) {
    _eventReceiveBuffer.add(chunk);
    var bufferBytes = _eventReceiveBuffer.toBytes();

    while (bufferBytes.length >= 8) {
      final packet = PtpPacket.parse(bufferBytes);
      if (packet == null) break;

      final remaining = bufferBytes.sublist(packet.length);
      _eventReceiveBuffer.clear();
      _eventReceiveBuffer.add(remaining);
      bufferBytes = remaining;

      if (packet.type == PtpOpCodes.ptpIpInitEventAck) {
        // InitEventAck (Type = 4) 握手应答
        if (_pendingEventAckCompleter != null && !_pendingEventAckCompleter!.isCompleted) {
          _pendingEventAckCompleter!.complete(packet);
        }
      } else if (packet.type == PtpOpCodes.ptpIpEvent) {
        // 相机推送的事件 (如 ObjectAdded 0x4002 拍摄完成)
        _eventController.add(packet);
      }
    }
  }

  /// 心跳定时保活（可由设置页关闭，默认 15 秒）
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!AppSettings.instance.autoKeepAlive) {
      _log('心跳保活已按设置关闭');
      return;
    }
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!_isConnected) {
        timer.cancel();
        return;
      }
      try {
        await executeOperation(PtpOpCodes.getStorageIDs);
      } catch (_) {}
    });
  }

  /// 断开连接并释放资源
  Future<void> disconnect() async {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    try {
      if (_cmdSocket != null) {
        await executeOperation(PtpOpCodes.closeSession);
      }
    } catch (_) {}

    await _cmdSocket?.close();
    await _eventSocket?.close();
    _cmdSocket = null;
    _eventSocket = null;
    _cmdReceiveBuffer.clear();
    _eventReceiveBuffer.clear();

    if (_pendingCmdAckCompleter != null && !_pendingCmdAckCompleter!.isCompleted) {
      _pendingCmdAckCompleter!.completeError(Exception('连接已断开'));
    }
    if (_pendingEventAckCompleter != null && !_pendingEventAckCompleter!.isCompleted) {
      _pendingEventAckCompleter!.completeError(Exception('连接已断开'));
    }
    if (_pendingResponseCompleter != null && !_pendingResponseCompleter!.isCompleted) {
      _pendingResponseCompleter!.completeError(Exception('连接已断开'));
    }
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}
