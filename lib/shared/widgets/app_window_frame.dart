import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/desktop/desktop_host.dart';
import '../../features/player/application/player_controller.dart';
import '../../theme/app_palette.dart';
import 'window_title_bar.dart';

/// 应用外壳：在所有路由之上统一叠加自绘标题栏，并挂载托盘 / 窗口原生能力。
///
/// 通过 `MaterialApp.router.builder` 注入，避免逐页改动；非桌面平台直接透传。
class AppWindowFrame extends ConsumerStatefulWidget {
  const AppWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends ConsumerState<AppWindowFrame> {
  @override
  void initState() {
    super.initState();

    final DesktopHost host = DesktopHost.instance;
    host.onMinimizedToTray = _notifyMinimizedToTray;

    unawaited(host.attachWindow());
    unawaited(
      host.initTray(
        onTogglePlayPause: () =>
            ref.read(playerControllerProvider.notifier).togglePlayPause(),
        onSkipPrevious: () =>
            ref.read(playerControllerProvider.notifier).skipPrevious(),
        onSkipNext: () => ref.read(playerControllerProvider.notifier).skipNext(),
      ),
    );
  }

  @override
  void dispose() {
    if (DesktopHost.instance.onMinimizedToTray == _notifyMinimizedToTray) {
      DesktopHost.instance.onMinimizedToTray = null;
    }
    super.dispose();
  }

  void _notifyMinimizedToTray() {
    final ScaffoldMessengerState? messenger =
        DesktopHost.instance.messengerKey.currentState;
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已最小化到托盘，仍在后台播放'),
          duration: Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final Color windowColor = context.palette.background;

    if (!DesktopHost.isDesktopPlatform) {
      return widget.child;
    }

    // 窗口原生底色跟随当前主题：浅色主题下缩放 / 重绘时边缘不再露出深色底。
    // 宿主内部做了去重与异常兜底，这里异步触发不阻塞 UI。
    unawaited(DesktopHost.instance.setWindowBackgroundColor(windowColor));

    return Column(
      children: <Widget>[
        const WindowTitleBar(),
        Expanded(child: widget.child),
      ],
    );
  }
}
