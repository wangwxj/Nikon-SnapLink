import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../engine/editor/photo_edit_controller.dart';
import '../../engine/editor/photo_edit_engine.dart';

/// 编辑工具类型（编辑器与水印工坊共用）。
enum PhotoEditTool { rotate, flip, perspective, distort, free, crop }

extension PhotoEditToolInfo on PhotoEditTool {
  String get label => switch (this) {
        PhotoEditTool.rotate => '旋转',
        PhotoEditTool.flip => '翻转',
        PhotoEditTool.perspective => '透视',
        PhotoEditTool.distort => '扭曲',
        PhotoEditTool.free => '自由变换',
        PhotoEditTool.crop => '裁切',
      };

  IconData get icon => switch (this) {
        PhotoEditTool.rotate => Icons.rotate_right,
        PhotoEditTool.flip => Icons.flip,
        PhotoEditTool.perspective => Icons.picture_in_picture_alt,
        PhotoEditTool.distort => Icons.grid_on,
        PhotoEditTool.free => Icons.open_with,
        PhotoEditTool.crop => Icons.crop,
      };
}

/// 图片编辑工具条 + 参数面板。
///
/// 只负责“参数编辑”，不负责预览与保存，因此编辑器与工坊可共用同一套 UI。
class PhotoEditToolsPanel extends StatelessWidget {
  final PhotoEditController controller;
  final PhotoEditTool activeTool;
  final ValueChanged<PhotoEditTool> onToolChanged;
  final double cropAspect;
  final ValueChanged<double> onCropAspectSelected;

  const PhotoEditToolsPanel({
    super.key,
    required this.controller,
    required this.activeTool,
    required this.onToolChanged,
    required this.cropAspect,
    required this.onCropAspectSelected,
  });

  void _commit(PhotoEditTransform next) => controller.update(next);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(builder: (context, constraints) {
          final preferred =
              MediaQuery.orientationOf(context) == Orientation.landscape
                  ? 156.0
                  : 220.0;
          final height = math.min(preferred, constraints.maxHeight);
          return SizedBox(
              height: height,
              child: Column(children: [
                SizedBox(height: 56, child: _toolBar(context)),
                Expanded(
                    child: ColoredBox(
                        color: SnapColors.of(context).card,
                        child: SingleChildScrollView(
                          key: ValueKey(activeTool),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: SizedBox(
                              width: double.infinity,
                              child: _panel(context, controller.value)),
                        ))),
              ]));
        });
      },
    );
  }

  Widget _panel(BuildContext context, PhotoEditTransform t) =>
      switch (activeTool) {
        PhotoEditTool.rotate => _rotatePanel(context, t),
        PhotoEditTool.flip => const SizedBox.shrink(),
        PhotoEditTool.perspective => _perspectivePanel(context, t),
        PhotoEditTool.distort => const SizedBox.shrink(),
        PhotoEditTool.free => _freePanel(context, t),
        PhotoEditTool.crop => _cropPanel(context),
      };

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(
              color: SnapColors.of(context).textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold),
        ),
      );

  Widget _slider(
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
  ) =>
      Slider(
        min: min,
        max: max,
        divisions: divisions,
        value: value.clamp(min, max),
        activeColor: SnapColors.nikonYellow,
        onChangeStart: (_) => controller.beginGesture(),
        onChangeEnd: (_) => controller.endGesture(),
        onChanged: onChanged,
      );

  Widget _rotatePanel(BuildContext context, PhotoEditTransform t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, '旋转 ' + t.rotationDegrees.toStringAsFixed(0) + '°'),
        _slider(t.rotationDegrees, -180, 180, 72,
            (v) => _commit(t.copyWith(rotationDegrees: v))),
      ],
    );
  }

  Widget _perspectivePanel(BuildContext context, PhotoEditTransform t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, '水平校正 ${(t.perspectiveHorizontal * 100).round()}'),
        _slider(t.perspectiveHorizontal, -1, 1, 40,
            (v) => _commit(t.copyWith(perspectiveHorizontal: v))),
        _title(context, '垂直校正 ${(t.perspectiveVertical * 100).round()}'),
        _slider(t.perspectiveVertical, -1, 1, 40,
            (v) => _commit(t.copyWith(perspectiveVertical: v))),
      ],
    );
  }

  Widget _freePanel(BuildContext context, PhotoEditTransform t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, '缩放 ' + (t.scale * 100).toStringAsFixed(0) + '%'),
        _slider(t.scale, 0.5, 2.0, 60, (v) => _commit(t.copyWith(scale: v))),
        _title(context, '水平平移 ' + (t.offsetX * 100).toStringAsFixed(0) + '%'),
        _slider(
            t.offsetX, -0.5, 0.5, 40, (v) => _commit(t.copyWith(offsetX: v))),
        _title(context, '垂直平移 ' + (t.offsetY * 100).toStringAsFixed(0) + '%'),
        _slider(
            t.offsetY, -0.5, 0.5, 40, (v) => _commit(t.copyWith(offsetY: v))),
      ],
    );
  }

  Widget _cropPanel(BuildContext context) {
    const landscape = ['原图', '1:1', '4:3', '3:2', '16:9'];
    const portrait = ['3:4', '2:3', '9:16', '自定义'];
    final activeKey =
        activeCropAspectKey(cropAspect, controller.value.crop);
    Widget chip(String name) {
      final active = name == activeKey;
      return InkWell(
        key: ValueKey('crop-ratio-$name'),
        borderRadius: BorderRadius.circular(9),
        onTap: () => onCropAspectSelected(cropAspectPresets[name]!),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? SnapColors.nikonYellow : SnapColors.of(context).surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: SnapColors.of(context).border),
          ),
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name,
                style: TextStyle(
                    color: active
                        ? Colors.black
                        : SnapColors.of(context).textSecondary,
                    fontSize: 12),
              )),
        ),
      );
    }

    Widget row(List<String> names) => Row(
        children: names
            .map((n) => Expanded(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: chip(n))))
            .toList());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, '裁切比例'),
        row(landscape),
        const SizedBox(height: 6),
        row(portrait),
      ],
    );
  }

  Widget _toolBar(BuildContext context) {
    return DecoratedBox(
        decoration: BoxDecoration(
            color: SnapColors.of(context).surface,
            border: Border(
                bottom: BorderSide(color: SnapColors.of(context).border))),
        child: Row(
          children: PhotoEditTool.values.map((tool) {
            final active = tool == activeTool;
            return Expanded(
                child: Tooltip(
                    message: tool.label,
                    child: InkWell(
                      key: ValueKey('edit-tool-${tool.name}'),
                      onTap: () => onToolChanged(tool),
                      child: ColoredBox(
                        color: active
                            ? SnapColors.of(context).cardElevated
                            : Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(tool.icon,
                                size: 20,
                                color: active
                                    ? SnapColors.of(context).primary
                                    : SnapColors.of(context).textSecondary),
                            const SizedBox(height: 3),
                            Flexible(
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      tool.label,
                                      style: TextStyle(
                                        color: active
                                            ? SnapColors.of(context).primary
                                            : SnapColors.of(context)
                                                .textSecondary,
                                        fontSize: 11,
                                        fontWeight: active
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ))),
                          ],
                        ),
                      ),
                    )));
          }).toList(),
        ));
  }
}

/// 裁切比例预设：0 = 原图全幅；-1 = 自定义（解锁比例、保留当前窗口）。
const cropAspectPresets = <String, double>{
  '原图': 0,
  '1:1': 1.0,
  '4:3': 4 / 3,
  '3:2': 3 / 2,
  '16:9': 16 / 9,
  '3:4': 3 / 4,
  '2:3': 2 / 3,
  '9:16': 9 / 16,
  '自定义': -1,
};

/// 当前变换对应的高亮按钮：锁定比例显示预设，手动改过窗口显示自定义。
String activeCropAspectKey(double cropAspect, CropRect crop) {
  if (cropAspect > 0) {
    for (final e in cropAspectPresets.entries) {
      if (e.value == cropAspect) return e.key;
    }
    return '自定义';
  }
  return crop.isFull ? '原图' : '自定义';
}

/// 应用比例按钮：>0 按全图几何重算裁切框；0 恢复原图；-1 解锁比例。
/// 必须用未裁切的原图尺寸换算——用已裁切画框（canvasWidth）会把新
/// 比例套在旧窗口上，显示的窗口不是目标比例（导出会被 cropBounds
/// 修回正确比例，造成预览与成品不一致）。
void applyCropAspect(PhotoEditController controller, double aspect) {
  final t = controller.value;
  if (aspect == -1) {
    if (t.cropAspect != 0) controller.update(t.copyWith(cropAspect: 0));
    return;
  }
  if (aspect <= 0) {
    controller.update(t.copyWith(crop: const CropRect(), cropAspect: 0));
    return;
  }
  final w = controller.sourceWidth, h = controller.sourceHeight;
  if (w <= 0 || h <= 0) return;
  controller.update(t.copyWith(
      crop: cropRectForAspect(aspect, w, h), cropAspect: aspect));
}

/// 根据图片尺寸把裁切比例换算成归一化裁切框。
CropRect cropRectForAspect(double aspect, int width, int height) {
  if (aspect <= 0 || width <= 0 || height <= 0) return const CropRect();
  final imageAspect = width / height;
  double w = 1.0, h = 1.0;
  if (imageAspect > aspect) {
    w = aspect / imageAspect;
  } else {
    h = imageAspect / aspect;
  }
  final l = (1 - w) / 2;
  final tp = (1 - h) / 2;
  return CropRect(left: l, top: tp, right: l + w, bottom: tp + h);
}
