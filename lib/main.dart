import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/network/kugou_providers.dart';
import 'core/network/kugou_session.dart';
import 'features/settings/application/settings_controller.dart';
import 'routing/app_router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// TX Music 应用入口（文档 §3.2 main.dart）。
///
/// 职责：
/// 1. 初始化 media_kit 音频引擎（libmpv）；
/// 2. 从 `.local/kugou_cookie.json` 恢复酷狗登录态，游客态也能启动；
/// 3. 桌面窗口初始化（尺寸 / 最小尺寸 / 标题），仅桌面平台执行；
/// 4. 挂载 [ProviderScope]，全局状态与路由实例只创建一次；
/// 5. 按设置项切换主题（默认深色），路由交给 GoRouter。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final KugouSession session = await KugouSession.load();
  debugPrint(
    session.isLoggedIn
        ? '酷狗登录态已恢复：${session.nickname}（dfid=${session.dfid}）'
        : '未检测到酷狗登录态，将以游客模式运行（仅 60 秒试听）',
  );

  await _setupDesktopWindow();

  runApp(
    ProviderScope(
      overrides: [
        // NotifierProvider 不支持 overrideWithValue，
        // 用 KugouSessionController 的初始值构造重写（详见 kugou_providers.dart）。
        kugouSessionProvider.overrideWith(
          () => KugouSessionController(session),
        ),
      ],
      child: const TxMusicApp(),
    ),
  );
}

/// Windows / macOS / Linux 窗口初始化：播放器默认给一个偏宽的横屏窗口。
/// 托盘、快捷键、桌面歌词窗口等能力见文档 §7，待后续里程碑接入。
Future<void> _setupDesktopWindow() async {
  if (kIsWeb) {
    return;
  }
  final bool desktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  if (!desktop) {
    return;
  }

  try {
    await windowManager.ensureInitialized();
    const WindowOptions options = WindowOptions(
      size: Size(1360, 840),
      minimumSize: Size(1024, 680),
      center: true,
      title: 'TX Music',
      backgroundColor: AppColors.background,
      titleBarStyle: TitleBarStyle.normal,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } on Object catch (error) {
    // 窗口插件异常不应阻塞 UI 启动（例如在单元测试或非桌面环境运行）。
    debugPrint('window_manager 初始化失败，使用默认窗口: $error');
  }
}

/// 根组件：主题 + 本地化 + 路由装配。
class TxMusicApp extends ConsumerWidget {
  const TxMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode =
        ref.watch(settingsControllerProvider).themeMode;
    final GoRouter router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'TX Music',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
