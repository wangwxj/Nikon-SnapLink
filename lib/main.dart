import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/vant_theme.dart';
import 'ui/root_scaffold.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp(
      title: 'SnapLink - Nikon Camera Control',
      debugShowCheckedModeBanner: false,
      theme: VantTheme.darkTheme,
      home: const RootScaffold(),
    );
  }
}
