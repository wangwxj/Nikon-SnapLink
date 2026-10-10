import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/core/constants/colors.dart';
import 'package:snaplink/core/settings/app_settings.dart';
import 'package:snaplink/core/settings/settings_scope.dart';
import 'package:snaplink/core/theme/vant_theme.dart';
import 'package:snaplink/ui/screens/settings_screen.dart';
import 'package:snaplink/ui/widgets/vant_widgets.dart';

void main() {
  setUp(() => AppSettings.instance.resetForTest());

  testWidgets('设置一级页只显示七个分类入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    for (final title in const [
      '外观与显示',
      '相机连接',
      '无线与传输',
      '取景与拍摄',
      '电池与传输保护',
      '诊断与日志',
      '关于 SnapLink',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '$title 应在一级页');
    }

    expect(find.byType(Switch), findsNothing, reason: '一级页不应直接展示开关');
    expect(find.text('默认相机 IP 地址'), findsNothing, reason: '一级页不应展示详情控件');
  });

  testWidgets('外观详情可切换主题模式', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('外观与显示'));
    await tester.pumpAndSettle();

    expect(find.text('颜色预览'), findsOneWidget);
    await tester.tap(find.text('浅色').first);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.themeMode, equals(AppThemeMode.light));

    await tester.tap(find.text('深色').first);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.themeMode, equals(AppThemeMode.dark));
  });

  testWidgets('开始为深色，切到浅色后设置项立即用浅色', (tester) async {
    AppSettings.instance.setThemeMode(AppThemeMode.dark);
    SnapColors.use(Brightness.dark);
    await tester.pumpWidget(SettingsScope(
      settings: AppSettings.instance,
      child: Builder(builder: (context) {
        final settings = SettingsScope.of(context);
        return MaterialApp(
          theme: VantTheme.lightTheme,
          darkTheme: VantTheme.darkTheme,
          themeMode: settings.materialThemeMode,
          builder: (context, child) {
            SnapColors.use(VantTheme.brightnessFor(
              settings.materialThemeMode,
              MediaQuery.platformBrightnessOf(context),
            ));
            return child ?? const SizedBox.shrink();
          },
          home: const SettingsScreen(),
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('系统设置'))).brightness, Brightness.dark);
    expect(SnapColors.textPrimary, SnapPalette.dark.textPrimary);

    AppSettings.instance.setThemeMode(AppThemeMode.light);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('系统设置'))).brightness, Brightness.light);
    expect(SnapColors.card, SnapPalette.light.card);
    expect(SnapColors.textPrimary, SnapPalette.light.textPrimary);
    final cellTitle = tester.widget<Text>(find.text('外观与显示'));
    expect(cellTitle.style!.color, SnapPalette.light.textPrimary);

    // 一级设置页的选项卡片背景必须同步为白色，而不是残留深色。
    final groupContainer = tester.widget<Container>(
      find.descendant(of: find.byType(VantCellGroup), matching: find.byType(Container)).first,
    );
    final groupDecoration = groupContainer.decoration! as BoxDecoration;
    expect(groupDecoration.color, SnapPalette.light.card);
  });
}
