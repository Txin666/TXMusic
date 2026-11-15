import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/desktop/desktop_host.dart';
import '../../core/desktop/panel/tray_panel_host.dart';
import '../../core/desktop/panel/tray_panel_models.dart';
import '../../core/desktop/taskbar_thumbnail_toolbar.dart';
import '../../core/network/kugou_client.dart';
import '../../features/library/application/library_providers.dart';
import '../../features/player/application/player_controller.dart';
import '../../features/player/domain/playback_state.dart';
import '../../features/song/domain/song.dart';
import '../../routing/app_router.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_palette.dart';
import 'window_title_bar.dart';
import 'app_snack_bar.dart';

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
    unawaited(_initDesktopIntegration(host));
  }

  /// 桌面侧原生集成：托盘点击弹自定义面板、任务栏缩略图工具栏、面板状态同步。
  ///
  /// 全部初始化只在主窗口做一次；面板窗口是独立引擎，不会走到这里。
  Future<void> _initDesktopIntegration(DesktopHost host) async {
    if (!DesktopHost.isSupported) {
      return;
    }

    await TrayPanelHost.instance.bind(onAction: _handlePanelAction);

    await host.initTray(
      onTrayIconClicked: (Rect? trayBounds) =>
          unawaited(TrayPanelHost.instance.toggle(trayBounds: trayBounds)),
    );

    final PlaybackSnapshot snapshot = ref.read(playerControllerProvider);
    await TaskbarThumbnailToolbar.register(
      onPrevious: _skipPrevious,
      onTogglePlayPause: _togglePlayPause,
      onNext: _skipNext,
      isPlaying: snapshot.isPlaying,
    );

    await _syncPanelState(snapshot);
  }

  void _togglePlayPause() =>
      ref.read(playerControllerProvider.notifier).togglePlayPause();

  void _skipPrevious() =>
      ref.read(playerControllerProvider.notifier).skipPrevious();

  void _skipNext() => ref.read(playerControllerProvider.notifier).skipNext();

  /// 面板动作统一入口：面板只负责 UI，真正的播放/导航都在主引擎执行。
  void _handlePanelAction(TrayPanelAction action, num? value) {
    final PlayerController controller = ref.read(
      playerControllerProvider.notifier,
    );
    switch (action) {
      case TrayPanelAction.togglePlayPause:
        controller.togglePlayPause();
      case TrayPanelAction.skipPrevious:
        controller.skipPrevious();
      case TrayPanelAction.skipNext:
        controller.skipNext();
      case TrayPanelAction.seek:
        if (value != null) {
          controller.seek(Duration(milliseconds: value.round()));
        }
      case TrayPanelAction.toggleFavorite:
        unawaited(_toggleFavorite());
      case TrayPanelAction.cycleRepeatMode:
        controller.cycleRepeatMode();
      case TrayPanelAction.toggleMute:
        controller.toggleMute();
      case TrayPanelAction.showMainWindow:
        unawaited(DesktopHost.instance.showWindow());
      case TrayPanelAction.openPlayer:
        _openRoute(AppRoutes.player);
      case TrayPanelAction.openLibrary:
        _openRoute(AppRoutes.library);
      case TrayPanelAction.openSettings:
        _openRoute(AppRoutes.settings);
      case TrayPanelAction.quit:
        unawaited(DesktopHost.instance.quitApp());
    }
  }

  void _openRoute(String path) {
    unawaited(DesktopHost.instance.showWindow());
    ref.read(appRouterProvider).go(path);
  }

  Future<void> _toggleFavorite() async {
    final Song? song = ref.read(playerControllerProvider).currentSong;
    if (song == null) {
      return;
    }
    try {
      await ref.read(libraryProvider.notifier).toggleFavorite(song);
    } on KugouApiException catch (error) {
      debugPrint('[collect] 收藏失败：${error.message}');
    } on Object catch (error) {
      debugPrint('[collect] 收藏失败：$error');
    }
    await _syncPanelState(ref.read(playerControllerProvider));
  }

  /// 把当前播放 / 收藏状态压成快照推给面板，并同步任务栏中间按钮图标。
  Future<void> _syncPanelState(PlaybackSnapshot snapshot) async {
    if (!DesktopHost.isSupported) {
      return;
    }
    final Song? song = snapshot.currentSong;
    final bool liked =
        song != null && ref.read(isFavoriteProvider)(song.hash);

    await TrayPanelHost.instance.pushState(
      TrayPanelState(
        hasSong: song != null,
        title: song?.title ?? '',
        artist: song?.artist ?? '',
        album: song?.album ?? '',
        coverUrl: song?.coverUrl ?? '',
        isPlaying: snapshot.isPlaying,
        isLoading: snapshot.isLoading,
        positionMs: snapshot.position.inMilliseconds,
        durationMs: snapshot.duration.inMilliseconds,
        liked: liked,
        repeatLabel: snapshot.repeatMode.label,
        repeatActive: snapshot.repeatMode != RepeatMode.none,
        favoriteCount: ref.read(libraryProvider).favorites.length,
        volume: snapshot.volume,
        muted: snapshot.muted,
        errorMessage: snapshot.errorMessage,
      ),
    );
    await TaskbarThumbnailToolbar.syncPlaybackState(snapshot.isPlaying);
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
    showAppSnackBarWith(messenger, '已最小化到托盘，仍在后台播放');
  }

  @override
  Widget build(BuildContext context) {
    // 播放状态 / 收藏变化都推给托盘面板与任务栏按钮，面板不在前台时只更新缓存。
    ref.listen<PlaybackSnapshot>(playerControllerProvider, (
      PlaybackSnapshot? previous,
      PlaybackSnapshot next,
    ) {
      unawaited(_syncPanelState(next));
    });
    ref.listen<LibraryState>(libraryProvider, (
      LibraryState? previous,
      LibraryState next,
    ) {
      unawaited(_syncPanelState(ref.read(playerControllerProvider)));
    });

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
