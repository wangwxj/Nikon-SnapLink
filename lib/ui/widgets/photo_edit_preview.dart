import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../engine/editor/photo_edit_controller.dart';
import '../../engine/editor/photo_edit_engine.dart';
import 'photo_edit_tools.dart';

Rect fittedPhotoRect(Size viewport, Size image) {
  if (image.isEmpty || viewport.isEmpty) return Rect.zero;
  final size = applyBoxFit(BoxFit.contain, image, viewport).destination;
  return Alignment.center.inscribe(size, Offset.zero & viewport);
}

/// 唯一编辑画布；所有手势以真实照片矩形计算，而不是外围留白。
class PhotoEditPreview extends StatefulWidget {
  final PhotoEditController controller;
  final ui.Image? previewImage;
  final PhotoEditTool activeTool;
  final double cropAspect;
  const PhotoEditPreview(
      {super.key,
      required this.controller,
      this.previewImage,
      required this.activeTool,
      this.cropAspect = 0});
  @override
  State<PhotoEditPreview> createState() => _PhotoEditPreviewState();
}

class _PhotoEditPreviewState extends State<PhotoEditPreview> {
  PhotoEditTransform? _start;
  Offset _focal = Offset.zero;
  PhotoEditController get controller => widget.controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final image = widget.previewImage ?? controller.previewImage;
        if (image == null)
          return Center(
              child: Text(
                  controller.renderError ??
                      (controller.loading || controller.sourceWidth > 0
                          ? '正在准备编辑预览…'
                          : '未选择照片'),
                  style:
                      TextStyle(color: SnapColors.of(context).textSecondary)));
        return LayoutBuilder(builder: (context, c) {
          final immediate =
              controller.previewPending && controller.originalPreview != null;
          final sourceWidth =
              controller.originalPreview?.width ?? image.width;
          final sourceHeight =
              controller.originalPreview?.height ?? image.height;
          final omitCrop = widget.activeTool == PhotoEditTool.crop ||
              widget.activeTool == PhotoEditTool.distort;
          final frameTransform = omitCrop
              ? controller.value.copyWith(
                  crop: const CropRect(), cropAspect: 0)
              : controller.value;
          final frame = PhotoEditEngine.frameDimensions(
              sourceWidth, sourceHeight, frameTransform,
              includeCrop: !omitCrop);
          final displaySize =
              Size(frame.width.toDouble(), frame.height.toDouble());
          final rect = fittedPhotoRect(c.biggest, displaySize);
          final usePainter = controller.originalPreview != null &&
              (immediate ||
                  (widget.activeTool == PhotoEditTool.perspective &&
                      controller.value.hasPerspective));
          return Stack(children: [
            Positioned.fromRect(
                rect: rect,
                child: GestureDetector(
                  onScaleStart: widget.activeTool == PhotoEditTool.free
                      ? (d) {
                          _start = controller.value;
                          _focal = d.focalPoint;
                          controller.beginGesture();
                        }
                      : null,
                  onScaleUpdate: widget.activeTool == PhotoEditTool.free
                      ? (d) {
                          final t = _start!;
                          final delta = d.focalPoint - _focal;
                          controller.update(t.copyWith(
                              scale: (t.scale * d.scale).clamp(.5, 2),
                              offsetX: (t.offsetX + delta.dx / rect.width)
                                  .clamp(-.5, .5),
                              offsetY: (t.offsetY + delta.dy / rect.height)
                                  .clamp(-.5, .5)));
                        }
                      : null,
                  onScaleEnd: widget.activeTool == PhotoEditTool.free
                      ? (_) {
                          controller.endGesture();
                          _start = null;
                        }
                      : null,
                  // 透视校正始终走即时画布：后台结果是裁到画框的，
                  // 直接切换会把溢出的梯形突然裁掉。
                  child: usePainter
                      ? CustomPaint(
                          painter: _ImmediateEditPainter(
                              controller.originalPreview!,
                              controller.value,
                              omitCrop))
                      : RawImage(image: image, fit: BoxFit.fill),
                )),
            Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: SnapColors.of(context)
                                    .primary
                                    .withAlpha(180),
                                width: 1.5))))),
            if (widget.activeTool == PhotoEditTool.crop)
              Positioned.fromRect(
                  rect: rect,
                  child: _CropOverlay(
                      controller: controller,
                      aspect: widget.cropAspect,
                      imageAspect: sourceWidth / sourceHeight)),
            if (widget.activeTool == PhotoEditTool.perspective)
              Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                      child: CustomPaint(painter: _CorrectionGridPainter()))),
            if (widget.activeTool == PhotoEditTool.distort)
              Positioned.fromRect(
                  rect: rect, child: _DistortOverlay(controller: controller)),
            if (const [
              PhotoEditTool.rotate,
              PhotoEditTool.flip,
              PhotoEditTool.distort
            ].contains(widget.activeTool))
              Positioned(
                  left: 0,
                  right: 0,
                  top: (rect.top + 8)
                      .clamp(0.0, math.max(0.0, c.maxHeight - 48)),
                  child: Center(child: _shortcutBar(context))),
          ]);
        });
      });

  Widget _shortcutBar(BuildContext context) {
    final colors = SnapColors.of(context), t = controller.value;
    Widget button(String label, IconData icon, VoidCallback command,
            {bool selected = false}) =>
        IconButton(
          tooltip: label,
          onPressed: command,
          icon: Icon(icon, size: 21),
          style: IconButton.styleFrom(
              foregroundColor: selected ? colors.primary : colors.textPrimary,
              backgroundColor:
                  selected ? colors.primary.withAlpha(25) : Colors.transparent),
        );
    final buttons = switch (widget.activeTool) {
      PhotoEditTool.rotate => [
          button('左转 90°', Icons.rotate_left, () => controller.rotateBy(-90)),
          button('右转 90°', Icons.rotate_right, () => controller.rotateBy(90)),
          button('角度归零', Icons.restart_alt,
              () => controller.update(t.copyWith(rotationDegrees: 0))),
        ],
      PhotoEditTool.flip => [
          button(
              '水平翻转',
              Icons.swap_horiz,
              () => controller
                  .update(t.copyWith(flipHorizontal: !t.flipHorizontal)),
              selected: t.flipHorizontal),
          button(
              '垂直翻转',
              Icons.swap_vert,
              () =>
                  controller.update(t.copyWith(flipVertical: !t.flipVertical)),
              selected: t.flipVertical),
        ],
      _ => [
          button(
              '重置扭曲',
              Icons.restart_alt,
              () => controller.update(t.copyWith(
                  distortTopLeftX: 0,
                  distortTopLeftY: 0,
                  distortTopRightX: 0,
                  distortTopRightY: 0,
                  distortBottomLeftX: 0,
                  distortBottomLeftY: 0,
                  distortBottomRightX: 0,
                  distortBottomRightY: 0)))
        ],
    };
    return Material(
        key: const ValueKey('photo-transform-shortcuts'),
        color: colors.card.withAlpha(235),
        elevation: 2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: buttons));
  }
}

/// GPU 预览仅在后台重算期间使用，投影矩阵与导出引擎共用。
class _ImmediateEditPainter extends CustomPainter {
  final ui.Image image;
  final PhotoEditTransform transform;
  final bool omitCrop;
  _ImmediateEditPainter(this.image, this.transform, this.omitCrop);
  @override
  void paint(Canvas canvas, Size size) {
    final t = transform,
        w = image.width.toDouble(),
        h = image.height.toDouble();
    final dimensions = PhotoEditEngine.frameDimensions(
        image.width, image.height, t,
        includeCrop: false);
    final cw = dimensions.width.toDouble(), ch = dimensions.height.toDouble();
    final crop = PhotoEditEngine.cropBounds(
        dimensions.width, dimensions.height, t.crop, t.cropAspect);
    // 透视要把梯形完整画到画框外（参考效果图），此时不能裁到画框；
    // 其余变换仍严格裁到画框，旋转溢出部分直接牺牲。
    final spill =
        t.hasPerspective && t.crop.isFull && t.cropAspect == 0 && !omitCrop;
    canvas.save();
    // 底层黑幕布：缩放/扭曲露出的区域是黑底，与导出一致，不再垫一张原图。
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    if (!spill) canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / (omitCrop ? cw : crop.width),
        size.height / (omitCrop ? ch : crop.height));
    if (!omitCrop)
      canvas.translate(-crop.left.toDouble(), -crop.top.toDouble());
    if (!spill) canvas.clipRect(Rect.fromLTWH(0, 0, cw, ch));
    canvas.translate(cw / 2 + t.offsetX * cw, ch / 2 + t.offsetY * ch);
    canvas.scale(t.scale, t.scale);
    canvas.scale(t.flipHorizontal ? -1 : 1, t.flipVertical ? -1 : 1);
    final angle = t.rotationDegrees * math.pi / 180;
    final ca = math.cos(angle).abs(), sa = math.sin(angle).abs();
    // 与导出引擎一致：画框四角反推缩放，保证旋转后的图片内接于画框。
    final cover =
        math.max((cw * ca + ch * sa) / w, (cw * sa + ch * ca) / h);
    canvas.scale(cover, cover);
    canvas.rotate(angle);
    canvas.translate(-w / 2, -h / 2);
    if (!spill) canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
    if (t.hasPerspective || t.hasDistortion) {
      final m = PhotoEditEngine.homography(t, width: w, height: h);
      final matrix = Matrix4.identity()
        ..setEntry(0, 0, m[0])
        ..setEntry(0, 1, m[1] * w / h)
        ..setEntry(0, 3, m[2] * w)
        ..setEntry(1, 0, m[3] * h / w)
        ..setEntry(1, 1, m[4])
        ..setEntry(1, 3, m[5] * h)
        ..setEntry(3, 0, m[6] / w)
        ..setEntry(3, 1, m[7] / h);
      canvas.transform(matrix.storage);
    }
    canvas.drawImage(
        image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImmediateEditPainter old) =>
      old.image != image ||
      old.transform != transform ||
      old.omitCrop != omitCrop;
}

class _CorrectionGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 1; i < 3; i++) {
      path
        ..moveTo(size.width * i / 3, 0)
        ..lineTo(size.width * i / 3, size.height)
        ..moveTo(0, size.height * i / 3)
        ..lineTo(size.width, size.height * i / 3);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_CorrectionGridPainter old) => false;
}

class _CropOverlay extends StatelessWidget {
  final PhotoEditController controller;
  final double aspect, imageAspect;
  const _CropOverlay(
      {required this.controller,
      required this.aspect,
      required this.imageAspect});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final crop = controller.value.crop;
        final rect = Rect.fromLTRB(
            crop.left * c.maxWidth,
            crop.top * c.maxHeight,
            crop.right * c.maxWidth,
            crop.bottom * c.maxHeight);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
              child: IgnorePointer(
                  child: CustomPaint(painter: _CropMaskPainter(rect)))),
          Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => controller.beginGesture(),
                onPanUpdate: (d) {
                  final r = controller.value.crop;
                  final dx =
                      (d.delta.dx / c.maxWidth).clamp(-r.left, 1 - r.right);
                  final dy =
                      (d.delta.dy / c.maxHeight).clamp(-r.top, 1 - r.bottom);
                  controller.update(controller.value.copyWith(
                      crop: CropRect(
                          left: r.left + dx,
                          top: r.top + dy,
                          right: r.right + dx,
                          bottom: r.bottom + dy)));
                },
                onPanEnd: (_) => controller.endGesture(),
                onPanCancel: controller.endGesture,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: SnapColors.nikonYellow, width: 1.5))),
              )),
          for (var i = 0; i < 4; i++)
            _handle(
                i,
                [
                  rect.topLeft,
                  rect.topRight,
                  rect.bottomLeft,
                  rect.bottomRight
                ][i],
                c),
        ]);
      });
  Widget _handle(int i, Offset p, BoxConstraints c) => Positioned(
      left: p.dx.clamp(math.min(14, c.maxWidth / 2),
              math.max(c.maxWidth - 14, c.maxWidth / 2)) -
          14,
      top: p.dy.clamp(math.min(14, c.maxHeight / 2),
              math.max(c.maxHeight - 14, c.maxHeight / 2)) -
          14,
      child: GestureDetector(
        key: ValueKey('crop-handle-$i'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => controller.beginGesture(),
        onPanEnd: (_) => controller.endGesture(),
        onPanCancel: controller.endGesture,
        onPanUpdate: (d) {
          final t = controller.value, r = t.crop;
          final left = i == 0 || i == 2, top = i < 2;
          var l = r.left, rt = r.right, tp = r.top, b = r.bottom;
          if (left) {
            l = (l + d.delta.dx / c.maxWidth).clamp(0, rt - .04);
          } else {
            rt = (rt + d.delta.dx / c.maxWidth).clamp(l + .04, 1);
          }
          if (top) {
            tp = (tp + d.delta.dy / c.maxHeight).clamp(0, b - .04);
          } else {
            b = (b + d.delta.dy / c.maxHeight).clamp(tp + .04, 1);
          }
          if (aspect > 0) {
            final ratio = aspect / imageAspect;
            final maxW = left ? r.right : 1 - r.left,
                maxH = top ? r.bottom : 1 - r.top;
            final fromX = rt - l, fromY = (b - tp) * ratio;
            final width = (d.delta.dx.abs() >= d.delta.dy.abs() ? fromX : fromY)
                .clamp(math.min(.04, math.min(maxW, maxH * ratio)),
                    math.min(maxW, maxH * ratio));
            final height = width / ratio;
            l = left ? r.right - width : r.left;
            rt = left ? r.right : r.left + width;
            tp = top ? r.bottom - height : r.top;
            b = top ? r.bottom : r.top + height;
          }
          controller.update(t.copyWith(
              crop: CropRect(left: l, top: tp, right: rt, bottom: b)));
        },
        child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
                child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: SnapColors.nikonYellow,
                        border: Border.all(color: Colors.black54))))),
      ));
}

class _DistortOverlay extends StatelessWidget {
  final PhotoEditController controller;
  const _DistortOverlay({required this.controller});
  // 显示点经过旋转/翻转/自由变换；手势反向映射到原始四角坐标。
  Offset _map(Offset p, PhotoEditTransform t, {bool inverse = false}) {
    final a = t.rotationDegrees * math.pi / 180,
        co = math.cos(a),
        si = math.sin(a);
    final w = controller.sourceWidth.toDouble(),
        h = controller.sourceHeight.toDouble();
    final rw = w * co.abs() + h * si.abs(), rh = w * si.abs() + h * co.abs();
    if (inverse) {
      var x = p.dx / t.scale, y = p.dy / t.scale;
      if (t.flipHorizontal) x = -x;
      if (t.flipVertical) y = -y;
      return Offset(
          (x * rw * co + y * rh * si) / w, (-x * rw * si + y * rh * co) / h);
    }
    var x = ((p.dx - .5) * w * co - (p.dy - .5) * h * si) / rw + .5;
    var y = ((p.dx - .5) * w * si + (p.dy - .5) * h * co) / rh + .5;
    if (t.flipHorizontal) x = 1 - x;
    if (t.flipVertical) y = 1 - y;
    return Offset(.5 + (x - .5) * t.scale + t.offsetX,
        .5 + (y - .5) * t.scale + t.offsetY);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final t = controller.value;
        final corners = PhotoEditEngine.corners(t,
                width: controller.sourceWidth.toDouble(),
                height: controller.sourceHeight.toDouble())
            .map((p) => _map(Offset(p.x, p.y), t))
            .toList();
        return Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < 4; i++)
            Positioned(
                left: (corners[i].dx * c.maxWidth).clamp(
                        math.min(16, c.maxWidth / 2),
                        math.max(c.maxWidth - 16, c.maxWidth / 2)) -
                    16,
                top: (corners[i].dy * c.maxHeight).clamp(
                        math.min(16, c.maxHeight / 2),
                        math.max(c.maxHeight - 16, c.maxHeight / 2)) -
                    16,
                child: GestureDetector(
                  key: ValueKey('distort-handle-$i'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => controller.beginGesture(),
                  onPanEnd: (_) => controller.endGesture(),
                  onPanCancel: controller.endGesture,
                  onPanUpdate: (d) {
                    final t = controller.value;
                    final delta = _map(
                        Offset(
                            d.delta.dx / c.maxWidth, d.delta.dy / c.maxHeight),
                        t,
                        inverse: true);
                    final next = switch (i) {
                      0 => t.copyWith(
                          distortTopLeftX:
                              (t.distortTopLeftX + delta.dx).clamp(-.45, .45),
                          distortTopLeftY:
                              (t.distortTopLeftY + delta.dy).clamp(-.45, .45)),
                      1 => t.copyWith(
                          distortTopRightX:
                              (t.distortTopRightX + delta.dx).clamp(-.45, .45),
                          distortTopRightY:
                              (t.distortTopRightY + delta.dy).clamp(-.45, .45)),
                      2 => t.copyWith(
                          distortBottomRightX:
                              (t.distortBottomRightX + delta.dx)
                                  .clamp(-.45, .45),
                          distortBottomRightY:
                              (t.distortBottomRightY + delta.dy)
                                  .clamp(-.45, .45)),
                      _ => t.copyWith(
                          distortBottomLeftX: (t.distortBottomLeftX + delta.dx)
                              .clamp(-.45, .45),
                          distortBottomLeftY: (t.distortBottomLeftY + delta.dy)
                              .clamp(-.45, .45)),
                    };
                    if (PhotoEditEngine.validQuad(next,
                        width: controller.sourceWidth.toDouble(),
                        height: controller.sourceHeight.toDouble()))
                      controller.update(next);
                  },
                  child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                          child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                  color: SnapColors.info,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white))))),
                )),
        ]);
      });
}

class _CropMaskPainter extends CustomPainter {
  final Rect rect;
  _CropMaskPainter(this.rect);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(path, Paint()..color = Colors.black.withAlpha(100));
  }

  @override
  bool shouldRepaint(_CropMaskPainter old) => old.rect != rect;
}
