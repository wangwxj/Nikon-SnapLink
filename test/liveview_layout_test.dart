import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/engine/liveview/liveview_controller.dart';
import 'package:snaplink/protocol/nikon_driver.dart';
import 'package:snaplink/ui/screens/liveview_screen.dart';

void main() {
  testWidgets('portrait 360x800 with bottom nav', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final driver = NikonDriver();
    final controller = LiveViewController(driver: driver);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveViewScreen(controller: controller),
          bottomNavigationBar: const SizedBox(height: 80),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 无 RenderFlex 溢出异常即通过；再核对取景框紧贴直方图卡片下方、参数矩阵在其下方
    final card = tester.getRect(find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == 'RgbCurveHistogramPainter',
    ));
    final viewport = tester.getRect(find.byKey(const ValueKey('liveviewViewport')));
    final matrix = tester.getRect(find.text('取景模式'));
    debugPrint('portrait card=$card viewport=$viewport matrix=$matrix');
    expect(viewport.top - card.bottom, inInclusiveRange(0, 24),
        reason: 'viewport must sit right below histogram card (got gap ${viewport.top - card.bottom})');
    expect(viewport.bottom, lessThan(matrix.top),
        reason: '参数矩阵必须位于取景框下方');
  });

  testWidgets('landscape 800x360 fullscreen', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final driver = NikonDriver();
    final controller = LiveViewController(driver: driver);
    await tester.pumpWidget(
      MaterialApp(home: LiveViewScreen(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 物理横屏：应渲染横屏监看布局（右上参数徽章组存在），无溢出异常
    expect(find.textContaining('FPS'), findsWidgets);
    debugPrint('landscape ok');
  });
}
