import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/album/presentation/album_detail_page.dart';
import '../features/artist/presentation/artist_detail_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/discover/presentation/discover_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/lyric/presentation/desktop_lyric_page.dart';
import '../features/player/presentation/player_page.dart';
import '../features/playlist/presentation/playlist_detail_page.dart';
import '../features/rank/presentation/rank_detail_page.dart';
import '../features/rank/presentation/rank_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/presentation/main_shell.dart';
import '../theme/app_spacing.dart';
import '../theme/app_palette.dart';
import 'app_routes.dart';

/// 全局路由（文档 §9.6）。
///
/// 结构约定：
/// - 主流程页面统一挂在 [ShellRoute] 下，由 [MainShell] 提供侧边导航 / 顶部搜索 / 底部播放条，
///   切换页面时 Shell 不重建，播放状态与播放条保持连续。
/// - 播放详情页与桌面歌词页脱离 Shell：播放详情自身即全屏播放界面，
///   桌面歌词后续由 `window_manager` 作为独立无边框窗口承载（见文档 §7.2）。
class AppRouter {
  const AppRouter._();

  static GoRouter build() {
    return GoRouter(
      initialLocation: AppRoutes.discover,
      debugLogDiagnostics: false,
      redirect: (BuildContext context, GoRouterState state) {
        // 根路径统一落到发现页，避免出现空路由。
        if (state.uri.path == '/') {
          return AppRoutes.discover;
        }
        return null;
      },
      routes: <RouteBase>[
        ShellRoute(
          builder: (
            BuildContext context,
            GoRouterState state,
            Widget child,
          ) {
            return MainShell(
              currentPath: state.uri.path,
              child: KeyedSubtree(
                key: ValueKey<String>(state.uri.path),
                child: child,
              ),
            );
          },
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.discover,
              pageBuilder: _fadePage(const DiscoverPage()),
            ),
            GoRoute(
              path: AppRoutes.rank,
              pageBuilder: _fadePage(const RankPage()),
              routes: <RouteBase>[
                GoRoute(
                  path: ':id',
                  pageBuilder: (BuildContext context, GoRouterState state) {
                    return _fadePage(
                      RankDetailPage(rankId: state.pathParameters['id'] ?? ''),
                    )(context, state);
                  },
                ),
              ],
            ),
            GoRoute(
              path: AppRoutes.library,
              pageBuilder: _fadePage(const LibraryPage()),
            ),
            GoRoute(
              path: AppRoutes.settings,
              pageBuilder: _fadePage(const SettingsPage()),
            ),
            GoRoute(
              path: AppRoutes.search,
              pageBuilder: (BuildContext context, GoRouterState state) {
                return _fadePage(
                  SearchPage(initialQuery: state.uri.queryParameters['q']),
                )(context, state);
              },
            ),
            GoRoute(
              path: '/playlist/:id',
              pageBuilder: (BuildContext context, GoRouterState state) {
                return _fadePage(
                  PlaylistDetailPage(
                    playlistId: state.pathParameters['id'] ?? '',
                  ),
                )(context, state);
              },
            ),
            GoRoute(
              path: '/album/:id',
              pageBuilder: (BuildContext context, GoRouterState state) {
                return _fadePage(
                  AlbumDetailPage(albumId: state.pathParameters['id'] ?? ''),
                )(context, state);
              },
            ),
            GoRoute(
              path: '/artist/:id',
              pageBuilder: (BuildContext context, GoRouterState state) {
                return _fadePage(
                  ArtistDetailPage(artistId: state.pathParameters['id'] ?? ''),
                )(context, state);
              },
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.player,
          pageBuilder: _fadePage(const PlayerPage()),
        ),
        GoRoute(
          path: AppRoutes.desktopLyric,
          pageBuilder: _fadePage(const DesktopLyricPage()),
        ),
        GoRoute(
          path: AppRoutes.login,
          pageBuilder: _fadePage(const LoginPage()),
        ),
      ],
      errorBuilder: (BuildContext context, GoRouterState state) {
        return _RouteErrorPage(location: state.uri.toString());
      },
    );
  }

  /// 统一的淡入淡出转场：桌面端切换更轻，避免默认滑动在宽屏上观感突兀。
  static Page<void> Function(BuildContext, GoRouterState) _fadePage(Widget page) {
    return (BuildContext context, GoRouterState state) {
      return CustomTransitionPage<void>(
        key: state.pageKey,
        child: page,
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      );
    };
  }
}

/// 路由级全局实例：`ProviderScope` 内只创建一次，避免重建导致路由栈丢失。
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>(
  (Ref ref) => AppRouter.build(),
);

/// 未匹配路径兜底页：保证任何情况都不出现白屏。
class _RouteErrorPage extends StatelessWidget {
  const _RouteErrorPage({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.explore_off_rounded,
                size: 40,
                color: context.palette.textDisabled,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('页面不存在', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                location,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => context.go(AppRoutes.discover),
                child: const Text('回到发现页'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
