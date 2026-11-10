import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/app_breakpoints.dart';
import '../../../routing/app_routes.dart';
import '../application/shell_state.dart';
import '../../../theme/app_palette.dart';
import 'widgets/app_side_nav.dart';
import 'widgets/mini_player_bar.dart';
import 'widgets/top_search_bar.dart';

/// 启动壳：左侧导航栏 + 顶部搜索栏 + 内容区 + 底部播放控制条。
/// 所有主流程页面作为 ShellRoute 子路由渲染到 [child]，切换页面不重建播放条（文档 §9.6.3）。
class MainShell extends ConsumerWidget {
  const MainShell({
    super.key,
    required this.child,
    required this.currentPath,
  });

  final Widget child;
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ShellState shellState = ref.watch(shellControllerProvider);
    final double width = MediaQuery.sizeOf(context).width;
    final bool collapsed =
        shellState.navCollapsed || AppBreakpoints.navCollapsedByDefault(width);

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Row(
        children: <Widget>[
          AppSideNav(
            currentPath: currentPath,
            collapsed: collapsed,
            onToggle: () => ref.read(shellControllerProvider.notifier).toggleNav(),
            onNavigate: (String path) {
              if (path != currentPath) {
                context.go(path);
              }
            },
            onOpenDesktopLyric: () => context.push(AppRoutes.desktopLyric),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                TopSearchBar(
                  onOpenDesktopLyric: () => context.push(AppRoutes.desktopLyric),
                ),
                Expanded(
                  child: ClipRect(child: child),
                ),
                const MiniPlayerBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
