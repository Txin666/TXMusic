import 'package:flutter/foundation.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'desktop_host.dart';

/// 任务栏缩略图工具栏（Win7+ 的 THUMBNAIL_TOOLBAR）封装。
///
/// 三个按钮一次性注册：上一曲 / 播放暂停 / 下一曲。中间按钮的图标与
/// tooltip 随播放状态切换，只重设图标会触发 native 侧整组重建，
/// 因此这里把「是否播放」做去重，状态没变就不重复走通道。
class TaskbarThumbnailToolbar {
  TaskbarThumbnailToolbar._();

  static const String _prevIcon = 'assets/icons/taskbar_prev.ico';
  static const String _playIcon = 'assets/icons/taskbar_play.ico';
  static const String _pauseIcon = 'assets/icons/taskbar_pause.ico';
  static const String _nextIcon = 'assets/icons/taskbar_next.ico';

  static bool _registered = false;
  static bool _appliedPlaying = true;
  static VoidCallback? _onPrevious;
  static VoidCallback? _onTogglePlayPause;
  static VoidCallback? _onNext;

  /// 是否已注册过（供 UI 层判断是否需要初始化）。
  static bool get isRegistered => _registered;

  /// 窗口初始化时调用一次，注册全部三个按钮。
  ///
  /// [isPlaying] 决定中间按钮初始图标（播放中显示「暂停」）。
  static Future<void> register({
    required VoidCallback onPrevious,
    required VoidCallback onTogglePlayPause,
    required VoidCallback onNext,
    required bool isPlaying,
  }) async {
    if (!DesktopHost.isSupported) {
      return;
    }
    _onPrevious = onPrevious;
    _onTogglePlayPause = onTogglePlayPause;
    _onNext = onNext;

    if (_registered && _appliedPlaying == isPlaying) {
      return;
    }
    _registered = true;
    _appliedPlaying = isPlaying;
    await _apply(isPlaying);
  }

  /// 播放状态变化时同步中间按钮的图标与 tooltip。
  static Future<void> syncPlaybackState(bool isPlaying) async {
    if (!_registered || _appliedPlaying == isPlaying) {
      return;
    }
    _appliedPlaying = isPlaying;
    await _apply(isPlaying);
  }

  /// 重新绑定点击回调（例如播放器控制器实例被替换），不重建按钮。
  static void updateCallbacks({
    VoidCallback? onPrevious,
    VoidCallback? onTogglePlayPause,
    VoidCallback? onNext,
  }) {
    _onPrevious = onPrevious ?? _onPrevious;
    _onTogglePlayPause = onTogglePlayPause ?? _onTogglePlayPause;
    _onNext = onNext ?? _onNext;
  }

  static Future<void> _apply(bool isPlaying) async {
    try {
      await WindowsTaskbar.setThumbnailToolbar(<ThumbnailToolbarButton>[
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(_prevIcon),
          '上一曲',
          () => _onPrevious?.call(),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(isPlaying ? _pauseIcon : _playIcon),
          isPlaying ? '暂停' : '播放',
          () => _onTogglePlayPause?.call(),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(_nextIcon),
          '下一曲',
          () => _onNext?.call(),
        ),
      ]);
    } on Object catch (error, stack) {
      debugPrint('任务栏缩略图工具栏设置失败：$error\n$stack');
    }
  }

  /// 移除缩略图工具栏（退出前调用，避免任务栏图标残留按钮）。
  static Future<void> reset() async {
    if (!DesktopHost.isSupported) {
      return;
    }
    _registered = false;
    try {
      await WindowsTaskbar.resetThumbnailToolbar();
    } on Object catch (error) {
      debugPrint('任务栏缩略图工具栏移除失败：$error');
    }
  }
}
