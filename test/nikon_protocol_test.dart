import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/protocol/nikon_ble_lss.dart';
import 'package:snaplink/protocol/nikon_driver.dart';
import 'package:snaplink/protocol/nikon_liveview_parser.dart';

void main() {
  group('Nikon LiveView Parser 逆向解析算法验证', () {
    test('Version 2 (Z系列微单 1024 字节头) 解析验证', () {
      final buffer = Uint8List(1024 + 100);
      final bd = ByteData.sublistView(buffer);

      // MajorVersion = 2
      bd.setUint16(0, 2, Endian.little);
      // JpegLength = 100
      bd.setUint32(12, 100, Endian.little);
      // Dimensions
      bd.setUint16(16, 1024, Endian.little);
      bd.setUint16(18, 768, Endian.little);
      // Focus states
      buffer[35] = 1; // Driving
      buffer[36] = 2; // Match (合焦)
      buffer[38] = 2; // 2 个对焦框
      buffer[39] = 1; // 人脸索引 1

      // 第 1 个对焦框
      bd.setInt16(40, 100, Endian.little);
      bd.setInt16(42, 150, Endian.little);
      bd.setInt16(44, 80, Endian.little);
      bd.setInt16(46, 80, Endian.little);

      // 旋转方向
      buffer[812] = 2; // Clockwise 90度 (竖拍)

      // 填充模拟 JPEG 数据
      buffer[1024] = 0xFF;
      buffer[1025] = 0xD8; // JPEG SOI
      buffer[1024 + 99] = 0xFF;

      final frame = NikonLiveViewParser.parse(buffer);
      expect(frame, isNotNull);
      expect(frame!.version, equals(2));
      expect(frame.jpegWidth, equals(1024));
      expect(frame.jpegHeight, equals(768));
      expect(frame.isFocusDriving, isTrue);
      expect(frame.focusState, equals(NikonFocusState.match));
      expect(frame.rotation, equals(NikonRotationDirection.clockwise));
      expect(frame.afBoxes.length, greaterThanOrEqualTo(1));
      expect(frame.afBoxes[0].x, equals(100));
      expect(frame.afBoxes[0].y, equals(150));
      expect(frame.jpegData.length, equals(100));
      expect(frame.jpegData[0], equals(0xFF));
      expect(frame.jpegData[1], equals(0xD8));
    });

    test('Version 1 (经典单反 384 字节头) 解析验证', () {
      final buffer = Uint8List(384 + 50);
      final bd = ByteData.sublistView(buffer);

      bd.setUint16(0, 1, Endian.little);
      bd.setUint32(4, 50, Endian.little); // Jpeg length

      // 填充模拟 JPEG
      buffer[384] = 0xFF;
      buffer[385] = 0xD8;

      final frame = NikonLiveViewParser.parse(buffer);
      expect(frame, isNotNull);
      expect(frame!.version, equals(1));
      expect(frame.jpegData.length, equals(50));
      expect(frame.jpegData[0], equals(0xFF));
    });

    test('纯 JPEG 图像流 (WMU 模式或直接直出) 快速解析验证', () {
      final rawJpeg = Uint8List(500);
      rawJpeg[0] = 0xFF;
      rawJpeg[1] = 0xD8;
      rawJpeg[498] = 0xFF;
      rawJpeg[499] = 0xD9;

      final frame = NikonLiveViewParser.parse(rawJpeg);
      expect(frame, isNotNull);
      expect(frame!.version, equals(0));
      expect(frame.jpegData.length, equals(500));
      expect(frame.jpegData[0], equals(0xFF));
      expect(frame.jpegData[1], equals(0xD8));
      expect(frame.jpegData[498], equals(0xFF));
      expect(frame.jpegData[499], equals(0xD9));
    });

    test('Version 2 带前置对齐填充偏移的容错解析验证', () {
      final buffer = Uint8List(1024 + 4 + 80);
      final bd = ByteData.sublistView(buffer);
      bd.setUint16(0, 2, Endian.little);
      bd.setUint32(12, 80, Endian.little);

      // 前置 4 字节 0x00 填充，SOI 位于 1028
      buffer[1028] = 0xFF;
      buffer[1029] = 0xD8;
      buffer[1028 + 78] = 0xFF;
      buffer[1028 + 79] = 0xD9;

      final frame = NikonLiveViewParser.parse(buffer);
      expect(frame, isNotNull);
      expect(frame!.version, equals(2));
      expect(frame.jpegData[0], equals(0xFF));
      expect(frame.jpegData[1], equals(0xD8));
    });
  });

  group('Nikon BLE LSS 凭证解析验证', () {
    test('解析 ConnectionConfiguration (0x2004) Wi-Fi SSID 与密码', () {
      final payload = Uint8List(128);
      payload[0] = 0x01; // hasWifiSetting = true

      // 写入 SSID: "NIKON_Z6III_TEST"
      const ssidStr = "NIKON_Z6III_TEST";
      for (int i = 0; i < ssidStr.length; i++) {
        payload[1 + i] = ssidStr.codeUnitAt(i);
      }

      // 写入密码: "nikon12345"
      const pwdStr = "nikon12345";
      for (int i = 0; i < pwdStr.length; i++) {
        payload[33 + i] = pwdStr.codeUnitAt(i);
      }


      payload[97] = 1; // WPA2

      final config = NikonBleLss.parseConnectionConfiguration(payload);
      expect(config, isNotNull);
      expect(config!.ssid, equals("NIKON_Z6III_TEST"));
      expect(config.password, equals("nikon12345"));
      expect(config.encryptMode, equals(1));
      expect(config.isOpen, isFalse);
    });

    test('构建 BLE 开启 Wi-Fi AP 控制指令', () {
      final cmd = NikonBleLss.buildWifiControlCommand(enable: true);
      expect(cmd.length, equals(4));
      expect(cmd[0], equals(0x01));
      expect(cmd[1], equals(0x01)); // 开启
    });
  });

  group('尼康机型与卡槽架构识别测试', () {
    test('Nikon Z 30 机型归一化识别与单卡槽判定', () {
      expect(NikonDeviceInfo.normalizeModelName('NIKON Z 30'), equals('NIKON Z 30'));
      expect(NikonDeviceInfo.normalizeModelName('Z30'), equals('NIKON Z 30'));
      expect(NikonDeviceInfo.normalizeModelName('NIKON DSC Z 30'), equals('NIKON Z 30'));
      expect(NikonDeviceInfo.normalizeModelName('NIKON_Z_30_1024'), equals('NIKON Z 30'));

      expect(NikonDeviceInfo.normalizeModelName('Z fc'), equals('NIKON Z fc'));
      expect(NikonDeviceInfo.normalizeModelName('Z50'), equals('NIKON Z 50'));
      expect(NikonDeviceInfo.normalizeModelName('NIKON Z 8'), equals('NIKON Z 8'));
    });
  });
}
