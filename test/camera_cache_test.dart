import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/protocol/camera_driver.dart';

void main() {
  test('CameraFileItem JSON 往返 (相册列表持久缓存与增量加载基础)', () {
    final item = CameraFileItem(
      handle: 0x12345678,
      storageId: 0x00010001,
      format: 0x3000,
      size: 5 * 1024 * 1024,
      fileName: 'DSC_0100.MP4',
      captureDate: '2026:10:07 15:41:00',
    );

    final restored = CameraFileItem.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(item.toJson())) as Map),
    );

    expect(restored.handle, equals(item.handle));
    expect(restored.storageId, equals(item.storageId));
    expect(restored.format, equals(item.format));
    expect(restored.size, equals(item.size));
    expect(restored.fileName, equals(item.fileName));
    expect(restored.captureDate, equals(item.captureDate));
    expect(restored.isVideo, isTrue, reason: 'MP4 必须被识别为视频');
    expect(restored.sizeFormatted, equals('5.0 MB'));
  });
}
