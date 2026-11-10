import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/desktop/desktop_host.dart';
import 'core/network/kugou_providers.dart';
import 'core/network/kugou_session.dart';
import 'features/settings/application/settings_controller.dart';
import 'routing/app_router.dart';
import 'shared/widgets/app_window_frame.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// TX Music 应用入口（文档 §3.2 main.dart）。
///
/// 职责：
/// 1. 初始化 media_kit 音频引擎（libmpv）；
/// 2. 从 `.local/kugou_cookie.json` 恢复酷狗登录态，游客态也能启动；
/// 3. 桌面窗口初始化：无边框（自绘标题栏）+ 关闭收进托盘；
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

/// 桌面窗口初始化：去掉系统标题栏（改由 [WindowTitleBar] 自绘），
/// 关闭按钮由 [DesktopHost] 拦截为「收进托盘」。
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
      // 初始底色按默认主题（深色）设定；运行期由 AppWindowFrame 依据
      // 当前主题的 palette.background 通过 DesktopHost 动态同步。
      backgroundColor: AppColors.background,
      titleBarStyle: TitleBarStyle.hidden,
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
      scaffoldMessengerKey: DesktopHost.instance.messengerKey,
      // 所有路由统一叠加自绘标题栏，避免逐页改动。
      builder: (BuildContext context, Widget? child) => AppWindowFrame(
        child: child ?? const SizedBox.shrink(),
      ),
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
