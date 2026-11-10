import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

/// 桌面壳层原生能力宿主：无边框窗口控制、关闭进托盘、系统托盘菜单。
///
/// 设计约束：
/// - 所有原生调用都包在 try/catch 里：`flutter test` 环境没有 window_manager /
///   tray_manager 的原生实现，异常不能影响 UI 与既有测试；
/// - 托盘菜单的播放控制通过回调注入，宿主本身不依赖 Riverpod，
///   避免 core 层反向依赖 features 层；
/// - 只有「退出 TX Music」会真正结束进程，关闭按钮一律收进托盘。
class DesktopHost with WindowListener {
  DesktopHost._();

  /// 全局单例：窗口与托盘在进程内只应存在一份。
  static final DesktopHost instance = DesktopHost._();

  /// 托盘图标资源（与 windows/runner/resources/app_icon.ico 同源）。
  static const String trayIconAsset = 'assets/icons/tray.ico';

  /// SnackBar 入口，挂到 MaterialApp.scaffoldMessengerKey 上。
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// 是否运行在桌面平台（Windows / macOS / Linux）。
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// 是否运行在 `flutter test` 环境（没有原生插件实现）。
  static bool get isUnderTest =>
      !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

  /// 原生窗口 / 托盘能力是否可用。
  static bool get isSupported => isDesktopPlatform && !isUnderTest;

  /// 主窗口是否已最大化（供自绘标题栏切换按钮图标）。
  final ValueNotifier<bool> isMaximized = ValueNotifier<bool>(false);

  bool _windowAttached = false;
  bool _trayReady = false;
  bool _quitting = false;

  tray.TrayIcon? _trayIcon;
  tray.Menu? _trayMenu;
  final List<tray.MenuItem> _trayMenuItems = <tray.MenuItem>[];

  /// 窗口收进托盘后的提示回调（由 UI 层注入，用于弹 SnackBar）。
  VoidCallback? onMinimizedToTray;

  // ---------------------------------------------------------------- 窗口

  /// 注册窗口监听，并把系统关闭按钮改成「收进托盘」。
  Future<void> attachWindow() async {
    if (!isSupported || _windowAttached) {
      return;
    }
    _windowAttached = true;
    try {
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
    } on Object catch (error) {
      _windowAttached = false;
      debugPrint('窗口监听注册失败: $error');
    }
  }

  /// 开始拖动窗口（无边框窗口的标题栏拖拽）。
  Future<void> startDragging() async {
    if (!isSupported) {
      return;
    }
    try {
      await windowManager.startDragging();
    } on Object catch (error) {
      debugPrint('窗口拖拽失败: $error');
    }
  }

  /// 最近一次同步过的窗口底色（避免主题重建时重复调用原生接口）。
  Color? _windowBackgroundColor;

  /// 让窗口原生底色跟随当前主题（浅色主题下窗口缩放/重绘不再露出深色底）。
  ///
  /// 非桌面平台、测试环境或原生调用异常时静默忽略；
  /// 调用方以 `unawaited` 方式触发，不阻塞 UI。
  Future<void> setWindowBackgroundColor(Color color) async {
    if (!isSupported || _windowBackgroundColor == color) {
      return;
    }
    _windowBackgroundColor = color;
    try {
      await windowManager.setBackgroundColor(color);
    } on Object catch (error) {
      // 失败时清空缓存，下次主题变化可重试。
      _windowBackgroundColor = null;
      debugPrint('窗口底色设置失败: $error');
    }
  }

  /// 最小化到任务栏。
  Future<void> minimize() async {
    if (!isSupported) {
      return;
    }
    try {
      await windowManager.minimize();
    } on Object catch (error) {
      debugPrint('窗口最小化失败: $error');
    }
  }

  /// 最大化 / 还原切换。
  Future<void> toggleMaximize() async {
    if (!isSupported) {
      return;
    }
    try {
      final bool maximized = await windowManager.isMaximized();
      if (maximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      isMaximized.value = await windowManager.isMaximized();
    } on Object catch (error) {
      debugPrint('窗口最大化切换失败: $error');
    }
  }

  /// 显示并聚焦主窗口（托盘左键 / 菜单「显示主窗口」）。
  Future<void> showWindow() async {
    if (!isSupported) {
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } on Object catch (error) {
      debugPrint('窗口显示失败: $error');
    }
  }

  /// 关闭按钮：隐藏到托盘，进程与播放继续。
  Future<void> hideToTray() async {
    if (!isSupported) {
      return;
    }
    try {
      await windowManager.hide();
    } on Object catch (error) {
      debugPrint('窗口隐藏失败: $error');
      return;
    }
    onMinimizedToTray?.call();
  }

  /// 退出程序：先回收托盘，再销毁窗口，进程随之结束。
  Future<void> quitApp() async {
    if (_quitting) {
      return;
    }
    _quitting = true;

    _disposeTray();

    if (isSupported) {
      try {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      } on Object catch (error) {
        debugPrint('窗口销毁失败: $error');
      }
    }
    _quitting = false;
    // window_manager.destroy 在部分 Windows 环境下只销毁窗口、不结束消息循环，
    // 进程会带着托盘残影留在后台，这里兜底真正退出。
    exit(0);
  }

  // ---------------------------------------------------------------- 托盘

  /// 创建系统托盘：图标 + 中文菜单 + 左键唤回窗口。
  ///
  /// [onTogglePlayPause] / [onSkipPrevious] / [onSkipNext] 由 UI 层接到
  /// `playerController`，这里只负责菜单项与点击派发。
  Future<void> initTray({
    required VoidCallback onTogglePlayPause,
    required VoidCallback onSkipPrevious,
    required VoidCallback onSkipNext,
  }) async {
    if (!isSupported || _trayReady) {
      return;
    }
    _trayReady = true;

    try {
      final tray.TrayIcon? icon = tray.TrayIcon.create();
      if (icon == null) {
        _trayReady = false;
        return;
      }
      _trayIcon = icon;

      final tray.Image? image = tray.ImageAsset.fromAsset(trayIconAsset);
      if (image == null) {
        debugPrint('托盘图标加载失败: $trayIconAsset');
      } else {
        icon.icon = image;
      }
      icon.setTooltip('TX Music');
      // Windows 原生实现默认不自动弹菜单，这里显式绑定右键。
      icon.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);

      final tray.Menu? menu = tray.Menu.create();
      if (menu != null) {
        _trayMenu = menu;
        _addMenuItem(menu, '显示主窗口', () => unawaited(showWindow()));
        menu.addSeparator();
        _addMenuItem(menu, '播放/暂停', onTogglePlayPause);
        _addMenuItem(menu, '上一首', onSkipPrevious);
        _addMenuItem(menu, '下一首', onSkipNext);
        menu.addSeparator();
        _addMenuItem(menu, '退出 TX Music', () => unawaited(quitApp()));
        icon.setContextMenu(menu);
      }

      icon.addListener((tray.TrayIconEvent event) {
        if (event is tray.TrayIconClickedEvent) {
          unawaited(showWindow());
        }
      });

      icon.setVisible(true);
      debugPrint('系统托盘已创建：$trayIconAsset');
    } on Object catch (error) {
      _trayReady = false;
      debugPrint('系统托盘初始化失败: $error');
    }
  }

  void _addMenuItem(tray.Menu menu, String label, VoidCallback onSelected) {
    final tray.MenuItem? item = tray.MenuItem.createWithLabelAndType(
      label,
      tray.MenuItemType.normal,
    );
    if (item == null) {
      return;
    }
    item.addListener((tray.MenuEvent event) {
      if (event is tray.MenuItemClickedEvent) {
        onSelected();
      }
    });
    _trayMenuItems.add(item);
    menu.addItem(item);
  }

  void _disposeTray() {
    _trayReady = false;

    final tray.TrayIcon? icon = _trayIcon;
    _trayIcon = null;
    try {
      icon?.dispose();
    } on Object catch (error) {
      debugPrint('托盘图标释放失败: $error');
    }

    for (final tray.MenuItem item in _trayMenuItems) {
      try {
        item.dispose();
      } on Object catch (error) {
        debugPrint('托盘菜单项释放失败: $error');
      }
    }
    _trayMenuItems.clear();

    try {
      _trayMenu?.dispose();
    } on Object catch (error) {
      debugPrint('托盘菜单释放失败: $error');
    }
    _trayMenu = null;
  }

  // ------------------------------------------------------ WindowListener

  @override
  void onWindowClose() {
    if (_quitting) {
      return;
    }
    // 关闭 = 收进托盘，播放不中断。
    unawaited(hideToTray());
  }

  @override
  void onWindowMaximize() => isMaximized.value = true;

  @override
  void onWindowUnmaximize() => isMaximized.value = false;
}
