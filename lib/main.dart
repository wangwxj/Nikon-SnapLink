import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/settings_scope.dart';
import 'core/theme/vant_theme.dart';
import 'ui/root_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动前加载持久化设置（失败时静默使用默认值），保证 IP/端口等立即生效
  await AppSettings.instance.load();

  // 设置沉浸式透明状态栏
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF141416),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const SnapLinkApp());
}

class SnapLinkApp extends StatelessWidget {
  const SnapLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: AppSettings.instance,
      child: MaterialApp(
        title: 'SnapLink - Nikon Camera Control',
        debugShowCheckedModeBanner: false,
        theme: VantTheme.darkTheme,
        home: const RootScaffold(),
      ),
    );
  }
}
