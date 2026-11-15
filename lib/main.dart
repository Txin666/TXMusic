import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/desktop/desktop_host.dart';
import 'core/desktop/kugou_service_launcher.dart';
import 'core/diagnostics/boot_log.dart';
import 'core/desktop/panel/tray_panel_host.dart';
import 'core/desktop/panel/tray_panel_window.dart';
import 'core/network/kugou_config.dart';
import 'core/network/kugou_providers.dart';
import 'core/network/kugou_session.dart';
import 'features/player/application/player_controller.dart';
import 'features/settings/application/settings_controller.dart';
import 'routing/app_router.dart';
import 'shared/widgets/app_window_frame.dart';
import 'shared/widgets/desktop_scroll_behavior.dart';
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
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  bootLog('--- boot 开始, args=$args');

  // 托盘悬浮面板是 desktop_multi_window 拉起的独立引擎：只跑面板 UI，
  // 不初始化音频引擎与登录态，省下整套 libmpv 内存与启动耗时。
  //
  // 判定只看入口参数，不能在这里调 WindowController.fromCurrentEngine()：
  // 子引擎的 Dart 入口早于插件注册执行，release 下必然抛 MissingPluginException，
  // 一旦误判成主引擎就会多建一个托盘图标，且面板 UI 永远不启动。
  if (!kIsWeb && TrayPanelHost.isPanelEngine(args)) {
    bootLog('=> 本引擎判定为【托盘面板】，只跑面板 UI');
    await runTrayPanelWindow();
    return;
  }
  bootLog('=> 本引擎判定为【主窗口】，继续完整启动');

  MediaKit.ensureInitialized();

  // 先把窗口亮出来，再拉内嵌服务：node 冷启动要 1~3 秒，
  // 别让用户开个软件先对着白屏干等。
  await _setupDesktopWindow();

  await _startLocalMusicService();

  final KugouSession session = await KugouSession.load();
  debugPrint(
    session.isLoggedIn
        ? '酷狗登录态已恢复：${session.nickname}（dfid=${session.dfid}）'
        : '未检测到酷狗登录态，将以游客模式运行（仅 60 秒试听）',
  );

  final String? autoTest =
      kIsWeb ? null : Platform.environment['TX_PANEL_AUTOTEST'];
  if (autoTest == '1' || autoTest == '2') {
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4), () async {
        await TrayPanelHost.instance.toggle();
        bootLog('autotest: 第一次 toggle 完成');
        if (autoTest == '2') {
          await Future<void>.delayed(const Duration(seconds: 4));
          await TrayPanelHost.instance.toggle();
          bootLog('autotest: 第二次 toggle 完成');
        }
      }),
    );
  }

  // 显式建容器：退出前要能从容器里取到播放控制器，把听歌进度落盘。
  final ProviderContainer container = ProviderContainer(
    overrides: [
      // NotifierProvider 不支持 overrideWithValue，
      // 用 KugouSessionController 的初始值构造重写（详见 kugou_providers.dart）。
      kugouSessionProvider.overrideWith(
        () => KugouSessionController(session),
      ),
    ],
  );

  // 退出前收尾：托盘「退出 TX Music」会 await 本回调，保证进度已写盘，
  // 同时回收随包拉起的本地音乐服务进程，不留孤儿 node。
  DesktopHost.instance.onBeforeQuit = () async {
    try {
      await container.read(playerControllerProvider.notifier).flushProgress();
    } on Object catch (error) {
      debugPrint('退出前保存播放进度失败: $error');
    }
    await KugouApiService.current?.shutdown();
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TxMusicApp(),
    ),
  );
}

/// 拉起随包的 KuGouMusicApi 服务，并把真实端口注入 [KugouConfig]。
///
/// 失败不阻塞启动：界面照常出来、由页面按网络错误提示用户，
/// 总比整个软件打不开强。
Future<void> _startLocalMusicService() async {
  if (kIsWeb) {
    return;
  }
  try {
    final KugouApiService service = await KugouApiService.ensureRunning();
    KugouConfig.setRuntimeBaseUrl(service.baseUrl);
    bootLog('=> 本地音乐服务就绪 ${service.baseUrl}');
  } on KugouServiceException catch (error) {
    bootLog('!! 本地音乐服务不可用: ${error.message}');
    debugPrint('本地音乐服务不可用: ${error.message}');
  } on Object catch (error) {
    bootLog('!! 本地音乐服务启动异常: $error');
    debugPrint('本地音乐服务启动异常: $error');
  }
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
      // 窗口 / 任务栏图标：与托盘共用同一份 ico，替换掉默认的 Flutter 图标。
      // window_manager 会把相对路径拼到 `data/flutter_assets` 下读取。
      try {
        await windowManager.setIcon(DesktopHost.windowIconAsset);
      } on Object catch (error) {
        // 图标设置失败不能连累后面的 show()，否则窗口根本不出来。
        debugPrint('窗口图标设置失败（不影响启动）: $error');
      }
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
    final ThemeMode themeMode = ref.watch(settingsControllerProvider).themeMode;
    final GoRouter router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'TX Music',
      debugShowCheckedModeBanner: false,
      // 桌面端要能用鼠标拖 PageView/横向列表，默认 dragDevices 不含鼠标。
      scrollBehavior: const DesktopScrollBehavior(),
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      scaffoldMessengerKey: DesktopHost.instance.messengerKey,
      // 所有路由统一叠加自绘标题栏，避免逐页改动。
      builder: (BuildContext context, Widget? child) =>
          AppWindowFrame(child: child ?? const SizedBox.shrink()),
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
