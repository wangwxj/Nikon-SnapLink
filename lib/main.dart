import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/colors.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/settings_scope.dart';
import 'core/theme/vant_theme.dart';
import 'ui/root_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动前加载持久化设置（失败时静默使用默认值），保证 IP/端口等立即生效
  await AppSettings.instance.load();

  runApp(const SnapLinkApp());
}

class SnapLinkApp extends StatelessWidget {
  const SnapLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: AppSettings.instance,
      child: Builder(
        builder: (context) {
          final settings = SettingsScope.of(context);
          return MaterialApp(
            title: 'SnapLink - Nikon Camera Control',
            debugShowCheckedModeBanner: false,
            theme: VantTheme.lightTheme,
            darkTheme: VantTheme.darkTheme,
            themeMode: settings.materialThemeMode,
            builder: (context, child) {
              // 不能读取 Theme.of(context).brightness：AnimatedTheme 动画期间
              // 它会短暂返回旧亮度，设置页等静态语义色会卡在上一套调色板。
              final brightness = VantTheme.brightnessFor(
                settings.materialThemeMode,
                MediaQuery.platformBrightnessOf(context),
              );
              SnapColors.use(brightness);
              _applySystemBars(brightness);
              return child ?? const SizedBox.shrink();
            },
            home: const RootScaffold(),
          );
        },
      ),
    );
  }

  void _applySystemBars(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: dark ? const Color(0xFF141416) : const Color(0xFFFFFFFF),
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));
  }
}

