import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/core/constants/ptp_opcodes.dart';
import 'package:snaplink/protocol/ptp_packet.dart';

void main() {
  group('PtpPacket 编解码与小端字节序验证测试', () {
    test('InitCommandRequest 封包格式与头部校验', () {
      final packet = PtpPacket.buildInitCommandRequest(
        clientName: 'SnapLink',
        guid: Uint8List(16),
      );

      expect(packet.type, equals(PtpOpCodes.ptpIpInitCommandRequest));
      expect(packet.length, greaterThan(8));

      // 序列化为二进制流
      final bytes = packet.toBytes();
      expect(bytes.length, equals(packet.length));

      // 解析拆包
      final parsed = PtpPacket.parse(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(1));
      expect(parsed.length, equals(packet.length));
    });

    test('InitEventRequest 封包格式校验', () {
      const connNum = 0x12345678;
      final packet = PtpPacket.buildInitEventRequest(connNum);

      expect(packet.type, equals(PtpOpCodes.ptpIpInitEventRequest));
      expect(packet.payload.length, equals(4));
      expect(packet.getUint32(0), equals(connNum));
    });

    test('OperationRequest 封包参数校验', () {
      final packet = PtpPacket.buildOperationRequest(
        opCode: PtpOpCodes.nikonStartLiveView,
        transactionId: 42,
        params: [1, 2, 3],
      );

      expect(packet.type, equals(PtpOpCodes.ptpIpOperationRequest));
      final bytes = packet.toBytes();
      final parsed = PtpPacket.parse(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.type, equals(6));
    });
  });
}
