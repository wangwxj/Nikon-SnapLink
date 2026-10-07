import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/engine/liveview/liveview_controller.dart';
import 'package:snaplink/engine/liveview/monitor_overlay.dart';
import 'package:snaplink/protocol/nikon_driver.dart';
import 'package:snaplink/ui/screens/liveview_screen.dart';

void main() {
  test('监看覆盖层不参与命中测试 (不拦截下层按钮)', () {
    final painter = MonitorOverlayPainter();
    expect(painter.hitTest(Offset.zero), isFalse,
        reason: 'CustomPainter.hitTest 默认 true 会吞掉「启动取景监看」按钮的点击');
  });

  testWidgets('未开启取景流时不显示监看元素', (tester) async {
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

    expect(controller.isStreaming, isFalse);

    // 九宫格/准星覆盖层不渲染
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MonitorOverlayPainter),
      findsNothing,
      reason: '未开流不应显示九宫格等监看图层',
    );
    // EV 曝光条不渲染
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is EvLadderPainter),
      findsNothing,
    );
    // 框内黑白直方图不渲染 (竖屏只保留顶部 RGB 卡片)
    expect(find.byType(HistogramWidget), findsNothing);
    // 顶部 RGB 直方图卡片保留
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == 'RgbCurveHistogramPainter'),
      findsOneWidget,
    );
    // 中心对焦白框不渲染 (占位提示仍在)
    expect(find.byIcon(Icons.link_off), findsOneWidget); // 未连接占位图标
    expect(find.text('请先在「连接」页面连入相机 Wi-Fi'), findsOneWidget);
  });
}
