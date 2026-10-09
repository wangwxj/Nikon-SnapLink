import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/core/settings/app_settings.dart';
import 'package:snaplink/core/utils/lru_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings 默认值与归一化', () {
    setUp(() => AppSettings.instance.resetForTest());

    test('默认目标帧率与控制器一致为 15，且 lowPower 默认 15%', () {
      expect(AppSettings.defaultPreferredFps, equals(15));
      expect(AppSettings.instance.preferredFps, equals(15));
      expect(AppSettings.instance.powerThreshold, equals(15));
      expect(AppSettings.instance.powerProtectionEnabled, isTrue);
      expect(AppSettings.instance.downloadRaw, isFalse);
      expect(AppSettings.instance.cameraIp, equals('192.168.0.1'));
      expect(AppSettings.instance.cameraPort, equals(15740));
    });

    test('非法帧率/阈值被归一化到合法集合', () {
      AppSettings.instance.setPreferredFps(7);
      AppSettings.instance.setPowerThreshold(99);
      expect(AppSettings.fpsOptions.contains(AppSettings.instance.preferredFps), isTrue);
      expect(AppSettings.powerThresholdOptions.contains(AppSettings.instance.powerThreshold), isTrue);
    });

    test('相机端口拒绝非法值', () {
      AppSettings.instance.setCameraPort(0);
      expect(AppSettings.instance.cameraPort, equals(15740));
      AppSettings.instance.setCameraPort(70000);
      expect(AppSettings.instance.cameraPort, equals(15740));
      AppSettings.instance.setCameraPort(15741);
      expect(AppSettings.instance.cameraPort, equals(15741));
    });
  });

  group('LruImageCache 容量约束与跨卡槽键', () {
    test('超过 maxEntries 时淘汰最久未使用项', () {
      final cache = LruImageCache(maxEntries: 2, maxBytes: 1 << 30);
      cache['a'] = Uint8List.fromList([1]);
      cache['b'] = Uint8List.fromList([2]);
      // 访问 a 使其变为最近使用
      expect(cache['a'], isNotNull);
      cache['c'] = Uint8List.fromList([3]);
      expect(cache.containsKey('b'), isFalse, reason: 'b 应被淘汰');
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('c'), isTrue);
    });

    test('超过 maxBytes 时按字节淘汰', () {
      final cache = LruImageCache(maxEntries: 100, maxBytes: 10);
      cache['a'] = Uint8List(6);
      cache['b'] = Uint8List(6);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
    });

    test('cameraCacheKey 组合 storageId 与 handle', () {
      expect(cameraCacheKey(0x00010001, 100), equals('65537_100'));
      expect(cameraCacheKey(0x00020002, 100), isNot(equals(cameraCacheKey(0x00010001, 100))));
    });
  });

  // 说明：AppSettings 的落盘/重启保持需要 path_provider 平台通道，
  // 在纯单测环境无法直接跑通，改由真机验收覆盖（见方案 Test Plan）。
}
