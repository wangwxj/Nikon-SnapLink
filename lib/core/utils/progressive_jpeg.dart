import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// 渐进式 JPEG 预览工具。
///
/// 相机端 PTP `GetPartialObject` 可以只取文件前 N 字节，而 `image` 包
/// 对截断的 JPEG 具备容错解码能力（Scan 未写完时仍能解出前半幅画面）。
/// 这样无需等待整张原图传输完成，即可先呈现一张可辨认的预览，
/// 显著缩短相机相册大图预览的首帧等待时间。
class ProgressiveJpeg {
  ProgressiveJpeg._();

  /// 先取前 [fraction] 比例字节做低清预览的默认比例。
  static const double defaultFraction = 0.35;

  /// 用 [bytes]（允许是截断的 JPEG 片段）尽力解码为 Flutter 位图。
  ///
  /// 解码失败或不是 JPEG 时返回 null，调用方应回退到缩略图或完整原图。
  static Future<ui.Image?> decodeLenient(Uint8List bytes) async {
    if (bytes.length < 4) return null;
    // 仅处理 JPEG（SOI 0xFFD8），RAW/PNG 走原有完整下载路径
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

    img.Image? decoded;
    try {
      decoded = img.decodeJpg(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return null;

    try {
      // 烘焙 EXIF 方向：RawImage 不会像 Image.memory 那样自动应用方向，
      // 必须先按 EXIF Orientation 旋转像素，竖拍片段才不会是躺倒的。
      decoded = img.bakeOrientation(decoded);
      final rgba = decoded.convert(numChannels: 4);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba.getBytes(order: img.ChannelOrder.rgba),
        rgba.width,
        rgba.height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return await completer.future;
    } catch (_) {
      return null;
    }
  }
}
