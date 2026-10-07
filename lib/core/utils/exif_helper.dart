import 'dart:typed_data';
import 'package:exif/exif.dart';

/// 照片拍摄元数据实体模型 (EXIF)
class PhotoMetadata {
  final String cameraMake;
  final String cameraModel;
  final String lensModel;
  final String shutterSpeed;
  final String aperture;
  final String iso;
  final String focalLength;
  final String capturedDate;
  final int orientation;
  final int width;
  final int height;

  const PhotoMetadata({
    this.cameraMake = 'Nikon',
    this.cameraModel = 'Z 30',
    this.lensModel = 'NIKKOR Z 40mm f/2',
    this.shutterSpeed = '1/250s',
    this.aperture = 'f/2.0',
    this.iso = 'ISO 100',
    this.focalLength = '40mm',
    this.capturedDate = '2026.10.06 14:32',
    this.orientation = 1,
    this.width = 6000,
    this.height = 4000,
  });

  /// 是否包含有效的相机或曝光信息
  bool get hasValidExif {
    return (cameraModel.isNotEmpty && cameraModel != 'Camera') ||
           shutterSpeed.isNotEmpty ||
           aperture.isNotEmpty ||
           iso.isNotEmpty;
  }

  /// 返回标题栏简洁格式: "NIKON Z 30"
  String get titleText {
    final make = cameraMake.replaceAll(RegExp(r'NIKON CORPORATION|NIKON', caseSensitive: false), 'NIKON').trim();
    var model = cameraModel.replaceAll(RegExp(make, caseSensitive: false), '').trim();
    if (model.isEmpty) model = 'CAMERA';
    return '$make $model'.trim().toUpperCase();
  }

  /// 返回曝光核心四参数组合: "40mm · f/2.0 · 1/250s · ISO 100"
  String get exposureSummary {
    final parts = <String>[];
    if (focalLength.isNotEmpty) parts.add(focalLength);
    if (aperture.isNotEmpty) parts.add(aperture);
    if (shutterSpeed.isNotEmpty) parts.add(shutterSpeed);
    if (iso.isNotEmpty) parts.add(iso);
    return parts.join(' · ');
  }

  /// 返回空格等宽分隔的曝光参数 (对标 build_apk: "40mm  f/2.0  1/250s  ISO 100")
  String get exposureMonospace {
    final parts = <String>[];
    if (focalLength.isNotEmpty) parts.add(focalLength);
    if (aperture.isNotEmpty) parts.add(aperture);
    if (shutterSpeed.isNotEmpty) parts.add(shutterSpeed);
    if (iso.isNotEmpty) parts.add(iso);
    return parts.join('   ');
  }

  PhotoMetadata copyWith({
    String? cameraMake,
    String? cameraModel,
    String? lensModel,
    String? shutterSpeed,
    String? aperture,
    String? iso,
    String? focalLength,
    String? capturedDate,
    int? orientation,
    int? width,
    int? height,
  }) {
    return PhotoMetadata(
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
      lensModel: lensModel ?? this.lensModel,
      shutterSpeed: shutterSpeed ?? this.shutterSpeed,
      aperture: aperture ?? this.aperture,
      iso: iso ?? this.iso,
      focalLength: focalLength ?? this.focalLength,
      capturedDate: capturedDate ?? this.capturedDate,
      orientation: orientation ?? this.orientation,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// EXIF 数据解析与格式化工具
class ExifHelper {
  ExifHelper._();

  /// 从图像二进制字节中解析全套 EXIF 标签
  static Future<PhotoMetadata> parseBytes(Uint8List imageBytes) async {
    try {
      final tags = await readExifFromBytes(imageBytes);
      if (tags.isEmpty) {
        return const PhotoMetadata();
      }

      // 1. 提取相机制造商与机型
      var make = tags['Image Make']?.printable ?? 'Nikon';
      var model = tags['Image Model']?.printable ?? 'Z Series';
      
      make = make.replaceAll(RegExp(r'NIKON CORPORATION|NIKON', caseSensitive: false), 'Nikon').trim();
      model = model.replaceAll(RegExp(make, caseSensitive: false), '').trim();
      if (model.isEmpty) model = 'Camera';

      // 2. 提取镜头规格
      final lens = tags['EXIF LensModel']?.printable ??
                   tags['EXIF LensSpecification']?.printable ??
                   '';

      // 3. 提取曝光三要素
      final rawShutter = tags['EXIF ExposureTime']?.printable ?? '';
      final formattedShutter = rawShutter.isNotEmpty ? _formatShutterSpeed(rawShutter) : '1/250s';

      final rawAperture = tags['EXIF FNumber']?.printable ?? '';
      final formattedAperture = rawAperture.isNotEmpty ? _formatAperture(rawAperture) : 'f/2.8';

      final rawIso = tags['EXIF ISOSpeedRatings']?.printable ??
                     tags['EXIF PhotographicSensitivity']?.printable ??
                     '';
      final formattedIso = rawIso.isNotEmpty ? 'ISO $rawIso' : 'ISO 100';

      // 4. 焦距与拍摄时间
      final rawFocal = tags['EXIF FocalLength']?.printable ?? '';
      final formattedFocal = rawFocal.isNotEmpty ? _formatFocalLength(rawFocal) : '';

      final date = tags['EXIF DateTimeOriginal']?.printable ??
                   tags['Image DateTime']?.printable ??
                   '';
      final formattedDate = _formatDateTime(date);

      final orientation = tags['Image Orientation']?.values.toList().firstOrNull as int? ?? 1;

      return PhotoMetadata(
        cameraMake: make,
        cameraModel: model,
        lensModel: lens.trim(),
        shutterSpeed: formattedShutter,
        aperture: formattedAperture,
        iso: formattedIso,
        focalLength: formattedFocal,
        capturedDate: formattedDate,
        orientation: orientation,
      );
    } catch (_) {
      return const PhotoMetadata();
    }
  }

  static String _formatShutterSpeed(String raw) {
    if (raw.contains('/')) return '${raw}s';
    final val = double.tryParse(raw);
    if (val != null) {
      if (val >= 1.0) {
        return '${val.toStringAsFixed(val == val.roundToDouble() ? 0 : 1)}s';
      } else if (val > 0) {
        final denom = (1.0 / val).round();
        return '1/${denom}s';
      }
    }
    return '${raw}s';
  }

  static String _formatAperture(String raw) {
    if (raw.startsWith('f/') || raw.startsWith('F/')) return raw.toLowerCase();
    if (raw.contains('/')) {
      final parts = raw.split('/');
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den != 0) {
        final f = num / den;
        return 'f/${f.toStringAsFixed(1)}';
      }
    }
    final val = double.tryParse(raw);
    if (val != null) {
      return 'f/${val.toStringAsFixed(1)}';
    }
    return 'f/$raw';
  }

  static String _formatFocalLength(String raw) {
    if (raw.endsWith('mm')) return raw;
    if (raw.contains('/')) {
      final parts = raw.split('/');
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den != 0) {
        final f = num / den;
        return '${f.round()}mm';
      }
    }
    final val = double.tryParse(raw.replaceAll('mm', '').trim());
    if (val != null) {
      return '${val.round()}mm';
    }
    return '${raw}mm';
  }

  static String _formatDateTime(String raw) {
    if (raw.isEmpty) return '';
    // 原格式通常为 "YYYY:MM:DD HH:MM:SS"
    // 转换为 "YYYY.MM.DD HH:MM"
    final parts = raw.split(' ');
    if (parts.length >= 2) {
      final datePart = parts[0].replaceAll(':', '.');
      final timeParts = parts[1].split(':');
      final timePart = timeParts.length >= 2 ? '${timeParts[0]}:${timeParts[1]}' : parts[1];
      return '$datePart $timePart';
    }
    var clean = raw.replaceAll(':', '.');
    if (clean.length >= 16) {
      clean = clean.substring(0, 16);
    }
    return clean;
  }
}
