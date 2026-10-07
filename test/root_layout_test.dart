import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/ui/root_scaffold.dart';

void main() {
  testWidgets('root scaffold liveview layout', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: RootScaffold()));
    await tester.pump(const Duration(milliseconds: 100));

    // 切到「监看取景」tab (index 1)
    await tester.tap(find.text('监看取景'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    void dump(String label, Finder f) {
      if (f.evaluate().isEmpty) {
        debugPrint('[$label] NOT FOUND');
        return;
      }
      debugPrint('[$label] ${tester.getRect(f.first)}');
    }

    final histCard = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == 'RgbCurveHistogramPainter',
    );
    final overlay = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == 'MonitorOverlayPainter',
    );

    dump('header(相机已连接)', find.text('相机已连接'));
    dump('histCard', histCard);
    dump('viewport(overlay)', overlay);
    dump('placeholder', find.text('请先在「连接」页面连入相机 Wi-Fi'));
    dump('matrix(取景模式)', find.text('取景模式'));
    dump('tools(自动对焦)', find.text('自动对焦 · AF'));
    dump('dock(图库)', find.text('图库'));
    dump('nav(监看取景)', find.text('监看取景'));
  });
}
