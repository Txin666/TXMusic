import 'package:flutter/material.dart';

import '../../../../core/responsive/app_breakpoints.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/app_logo.dart';
import '../../../../theme/app_spacing.dart';
import '../../../../theme/app_palette.dart';

/// 单个导航项定义。
class NavEntry {
  const NavEntry({
    required this.path,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// 左侧导航栏：可折叠为图标模式（窄窗口自动收起）。
/// 路由跳转统一走 `context.go`，保证 Shell 不重建、播放状态不受影响。
class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.currentPath,
    required this.collapsed,
    required this.onToggle,
    required this.onNavigate,
  });

  final String currentPath;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<String> onNavigate;

  static const List<NavEntry> primary = <NavEntry>[
    NavEntry(
      path: AppRoutes.discover,
      label: '发现',
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
    ),
    NavEntry(
      path: AppRoutes.rank,
      label: '排行榜',
      icon: Icons.leaderboard_outlined,
      activeIcon: Icons.leaderboard_rounded,
    ),
    NavEntry(
      path: AppRoutes.library,
      label: '我的音乐',
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
    ),
    NavEntry(
      path: AppRoutes.profile,
      label: '个人信息',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
    NavEntry(
      path: AppRoutes.settings,
      label: '设置',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
    ),
  ];

  static const NavEntry searchEntry = NavEntry(
    path: AppRoutes.search,
    label: '搜索',
    icon: Icons.search_rounded,
    activeIcon: Icons.search_rounded,
  );

  bool _isActive(String path) {
    if (path == AppRoutes.discover) {
      return currentPath == path;
    }
    return currentPath.startsWith(path);
  }

  @override
  Widget build(BuildContext context) {
    final double width = collapsed
        ? AppSpacing.sideNavCollapsedWidth
        : AppSpacing.sideNavWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(right: BorderSide(color: context.palette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildBrand(context),
          const SizedBox(height: AppSpacing.lg),
          if (!collapsed)
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                '音乐库',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: context.palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ...primary.map((NavEntry entry) => _buildItem(context, entry)),
          const SizedBox(height: AppSpacing.lg),
          if (!collapsed)
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                '快捷入口',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: context.palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _buildItem(context, searchEntry),
          const Spacer(),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.lg,
        collapsed ? AppSpacing.md : AppSpacing.sm,
        0,
      ),
      child: Row(
        children: <Widget>[
          const AppLogo(size: 32, radius: 9),
          if (!collapsed) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'TX MUSIC',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Windows 桌面播放器',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: context.palette.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '收起导航',
              onPressed: onToggle,
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              color: context.palette.textSecondary,
            ),
          ] else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, NavEntry entry) {
    final bool active = _isActive(entry.path);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Tooltip(
        message: collapsed ? entry.label : '',
        child: Material(
          color: active ? context.palette.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => onNavigate(entry.path),
            child: Container(
              height: 42,
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : AppSpacing.md,
              ),
              alignment: collapsed ? Alignment.center : Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    active ? entry.activeIcon : entry.icon,
                    size: 20,
                    color: active
                        ? context.palette.emphasized
                        : context.palette.textSecondary,
                  ),
                  if (!collapsed) ...<Widget>[
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      entry.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? context.palette.textPrimary
                            : context.palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: collapsed
          ? IconButton(
              tooltip: '展开导航',
              onPressed: onToggle,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              color: context.palette.textDisabled,
            )
          : Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: context.palette.textDisabled,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'TX MUSIC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: context.palette.textDisabled),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 窄窗口下侧边导航收起判定（供 Shell 调用）。
bool shouldCollapseNav(BuildContext context) =>
    AppBreakpoints.navCollapsedByDefault(MediaQuery.sizeOf(context).width);
