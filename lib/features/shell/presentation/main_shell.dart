import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/app_breakpoints.dart';
import '../../../routing/navigation_history.dart';
import '../application/shell_state.dart';
import '../../../theme/app_palette.dart';
import '../../vip/application/daily_vip_controller.dart';
import 'widgets/app_side_nav.dart';
import 'widgets/mini_player_bar.dart';
import 'widgets/top_search_bar.dart';

/// 启动壳：左侧导航栏 + 顶部搜索栏 + 内容区 + 底部播放控制条。
/// 所有主流程页面作为 ShellRoute 子路由渲染到 [child]，切换页面不重建播放条（文档 §9.6.3）。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child, required this.currentPath});

  final Widget child;
  final String currentPath;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    // 启动即检查「每日领 VIP」：登录态由 main() 从本地恢复，这里负责
    // 首轮触发 + 起跨天定时器（内部按日期幂等，同一天不会重复请求接口）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(dailyVipControllerProvider.notifier).bootstrap());
    });
    // 全局快捷键 Alt+← / Alt+→（以及鼠标侧键 back/forward）走前进后退。
    // 用 HardwareKeyboard 全局钩子而不是 Shortcuts，避免焦点跑进输入框后失效。
    HardwareKeyboard.instance.addHandler(_handleNavigationKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleNavigationKey);
    super.dispose();
  }

  bool _handleNavigationKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool isBrowserBack = key == LogicalKeyboardKey.browserBack;
    final bool isBrowserForward = key == LogicalKeyboardKey.browserForward;
    if (!isBrowserBack && !isBrowserForward) {
      if (!HardwareKeyboard.instance.isAltPressed) {
        return false;
      }
      if (key != LogicalKeyboardKey.arrowLeft &&
          key != LogicalKeyboardKey.arrowRight) {
        return false;
      }
    }
    final NavigationHistoryController controller = ref.read(
      navigationHistoryProvider.notifier,
    );
    if (isBrowserBack || key == LogicalKeyboardKey.arrowLeft) {
      controller.goBack();
    } else {
      controller.goForward();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ShellState shellState = ref.watch(shellControllerProvider);
    final double width = MediaQuery.sizeOf(context).width;
    final bool collapsed =
        shellState.navCollapsed || AppBreakpoints.navCollapsedByDefault(width);

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Row(
        children: <Widget>[
          AppSideNav(
            currentPath: widget.currentPath,
            collapsed: collapsed,
            onToggle: () =>
                ref.read(shellControllerProvider.notifier).toggleNav(),
            onNavigate: (String path) {
              if (path != widget.currentPath) {
                context.go(path);
              }
            },
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                TopSearchBar(),
                Expanded(child: ClipRect(child: widget.child)),
                const MiniPlayerBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
