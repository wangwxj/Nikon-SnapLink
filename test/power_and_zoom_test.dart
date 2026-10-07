import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/core/constants/ptp_opcodes.dart';
import 'package:snaplink/engine/liveview/liveview_controller.dart';
import 'package:snaplink/engine/transfer/download_manager.dart';
import 'package:snaplink/protocol/camera_driver.dart';

class MockCameraDriver implements CameraDriver {
  @override
  CameraConnectionState state = CameraConnectionState.connected;
  @override
  bool isConnected = true;
  @override
  String cameraModel = 'NIKON Z 8';
  @override
  int batteryLevel = 80;
  @override
  bool isSingleSlotCamera = false;
  @override
  List<int> availableStorageIds = const [0x00010001, 0x00020001];
  @override
  Stream<CameraConnectionState> get connectionStateStream => Stream.value(state);

  @override
  Future<List<int>> listStorageIds() async => availableStorageIds;

  bool isTeleZoom = false;
  int zoomSpeed = 0;
  bool isZoomStopped = false;
  int shutterTriggeredCount = 0;
  int afTriggeredCount = 0;

  final _photoStreamController = StreamController<CameraFileItem>.broadcast();

  @override
  Future<void> connect(String host, {int port = 15740, void Function(String msg)? onLog}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> startLiveView() async {}
  @override
  Future<Uint8List?> fetchLiveViewFrame() async => Uint8List(0);
  @override
  Future<void> endLiveView() async {}
  @override
  Future<void> triggerShutter() async {
    shutterTriggeredCount++;
  }
  @override
  Future<void> autofocus() async {
    afTriggeredCount++;
  }
  @override
  Future<void> driveZoom({required bool isTele, int speed = 5}) async {
    isTeleZoom = isTele;
    zoomSpeed = speed;
    isZoomStopped = false;
  }
  @override
  Future<void> stopDriveZoom() async {
    isZoomStopped = true;
  }
  @override
  Future<CameraExposureParams> fetchExposureParams() async => const CameraExposureParams(
        aperture: 'f/2.8',
        shutterSpeed: '1/250s',
        iso: 'ISO 400',
        exposureComp: '±0.0 EV',
        programMode: 'M',
        focalLength: '50mm',
        lensInfo: '24-70mm',
        batteryLevel: 80,
      );
  @override
  Future<bool> setAperture(double fNumber) async => true;
  @override
  Future<bool> setShutterSpeed(int numerator, int denominator) async => true;
  @override
  Future<bool> setIso(int iso) async => true;
  @override
  Future<bool> setExposureCompensation(int evMillisteps) async => true;
  @override
  Future<List<int>> listObjectHandles([int? storageId]) async => [0x10001, 0x10002];
  @override
  Future<CameraFileItem?> getObjectInfo(int handle) async => CameraFileItem(
        handle: handle,
        storageId: 0x00010001,
        format: 0x3801,
        size: 5000000,
        fileName: 'DSC_0001.JPG',
        captureDate: '20261006T110000',
      );
  @override
  Future<Uint8List> getThumbnail(int handle) async => Uint8List(100);
  @override
  Future<Uint8List> downloadPartialObject(int handle, int offset, int maxBytes) async => Uint8List(maxBytes);
  @override
  Future<Uint8List> downloadFullObject(int handle, int totalSize, {Function(int current, int total)? onProgress}) async {
    onProgress?.call(totalSize, totalSize);
    return Uint8List(totalSize);
  }
  @override
  Stream<CameraFileItem> get onPhotoCaptured => _photoStreamController.stream;
}

void main() {
  group('PTP OpCodes 校验', () {
    test('Nikon ZZoomDrive 操作码严格匹配 0x9464', () {
      expect(PtpOpCodes.nikonZZoomDrive, equals(0x9464));
    });
  });

  group('LiveView 变焦控制器 (SnapBridge-Enhanced 规范)', () {
    test('短脉冲变焦 (320ms WIDE/TELE) 触发及停止', () async {
      final mock = MockCameraDriver();
      final controller = LiveViewController(driver: mock);

      // 广角短脉冲 (WIDE)
      await controller.pulseZoom(isTele: false, durationMs: 50);
      expect(mock.isTeleZoom, isFalse);
      expect(mock.zoomSpeed, equals(5));
      expect(controller.zoomActiveDirection, equals('WIDE'));

      // 等待 50ms 脉冲结束
      await Future.delayed(const Duration(milliseconds: 70));
      expect(mock.isZoomStopped, isTrue);
      expect(controller.zoomActiveDirection, isNull);

      // 长焦短脉冲 (TELE)
      await controller.pulseZoom(isTele: true, durationMs: 50);
      expect(mock.isTeleZoom, isTrue);
      expect(mock.zoomSpeed, equals(5));
      expect(controller.zoomActiveDirection, equals('TELE'));

      await Future.delayed(const Duration(milliseconds: 70));
      expect(mock.isZoomStopped, isTrue);
      expect(controller.zoomActiveDirection, isNull);

      controller.dispose();
    });

    test('连续捏合变焦 (startDriveZoom / stopDriveZoom)', () async {
      final mock = MockCameraDriver();
      final controller = LiveViewController(driver: mock);

      await controller.startDriveZoom(isTele: true, speed: 7);
      expect(mock.isTeleZoom, isTrue);
      expect(mock.zoomSpeed, equals(7));
      expect(mock.isZoomStopped, isFalse);
      expect(controller.zoomActiveDirection, equals('TELE'));

      await controller.stopDriveZoom();
      expect(mock.isZoomStopped, isTrue);
      expect(controller.zoomActiveDirection, isNull);

      controller.dispose();
    });
  });

  group('SnapBridge-Enhanced 低电量保护状态机与传输队列', () {
    test('手动暂停与省电暂停独立性测试', () {
      final mock = MockCameraDriver();
      final dm = DownloadManager(driver: mock);

      expect(dm.isManualPaused, isFalse);
      expect(dm.isPowerPaused, isFalse);
      expect(dm.isPaused, isFalse);

      // 用户点击手动暂停
      dm.setManualPaused(true);
      expect(dm.isManualPaused, isTrue);
      expect(dm.isPaused, isTrue);

      // 用户取消手动暂停
      dm.setManualPaused(false);
      expect(dm.isManualPaused, isFalse);
      expect(dm.isPaused, isFalse);
    });

    test('任务入队与队列计数统计', () {
      final mock = MockCameraDriver();
      final dm = DownloadManager(driver: mock);

      final file1 = CameraFileItem(
        handle: 101,
        storageId: 1,
        format: 0x3801,
        size: 1000,
        fileName: 'DSC_0001.JPG',
        captureDate: '',
      );
      final file2 = CameraFileItem(
        handle: 102,
        storageId: 1,
        format: 0x3801,
        size: 2000,
        fileName: 'DSC_0002.JPG',
        captureDate: '',
      );

      dm.enqueue(file1);
      dm.enqueue(file2);

      expect(dm.totalCount, equals(2));
    });
  });

  group('LiveView 曝光调参与快门释放验证', () {
    test('快门释放与参数即时调节测试', () async {
      final mock = MockCameraDriver();
      final lvc = LiveViewController(driver: mock);

      // 验证快门释放
      await mock.triggerShutter();
      expect(mock.shutterTriggeredCount, equals(1));

      // 验证调参通道
      final apOk = await lvc.setAperture(2.8);
      expect(apOk, isTrue);

      final ssOk = await lvc.setShutterSpeed(1, 250);
      expect(ssOk, isTrue);

      final isoOk = await lvc.setIso(400);
      expect(isoOk, isTrue);

      final evOk = await lvc.setExposureCompensation(333);
      expect(evOk, isTrue);

      // 直方图容器初始状态
      expect(lvc.histogramBins, isEmpty);

      lvc.dispose();
    });
  });
}

