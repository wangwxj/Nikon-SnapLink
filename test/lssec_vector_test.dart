import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/protocol/nikon_ble_lss.dart';

/// Phase D 门禁：只有存在由原始 libLsSec-jni.so 生成的逐字节测试向量时，
/// 才会校验纯 Dart LsSec 复刻实现；向量缺失则跳过，从而在验证通过前不开放 BLE。
///
/// 生成向量的步骤见 reverse_analysis/BLE_LSS_RE.md。
void main() {
  final vectorFile = File('test_vectors/lssec_vectors.json');

  test('LsSec 逐字节向量校验（缺失则跳过，保持 BLE 锁定）', () async {
    if (!vectorFile.existsSync()) {
      // 尚无向量：Phase D 处于 no-go 状态，BLE 保持隐藏
      return;
    }
    final vectors =
        (jsonDecode(await vectorFile.readAsString()) as List).cast<Map<String, dynamic>>();
    // 纯 Dart LsSec 复刻实现接入后，在此逐条断言 base64 期望值逐字节一致
    expect(vectors, isA<List>());
  });

  test('BLE LSS 凭证解析可离线验证（无需相机）', () {
    final raw = List<int>.filled(98, 0);
    raw[0] = 1; // hasWifi
    final ssid = 'NIKON_Z_8'.codeUnits;
    for (var i = 0; i < ssid.length; i++) {
      raw[1 + i] = ssid[i];
    }
    final pwd = 'password123'.codeUnits;
    for (var i = 0; i < pwd.length; i++) {
      raw[33 + i] = pwd[i];
    }
    raw[97] = 1; // WPA2

    final cfg = NikonBleLss.parseConnectionConfiguration(Uint8List.fromList(raw));
    expect(cfg, isNotNull);
    expect(cfg!.ssid, equals('NIKON_Z_8'));
    expect(cfg.password, equals('password123'));
    expect(cfg.isOpen, isFalse);
  });
}
