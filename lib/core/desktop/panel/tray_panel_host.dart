import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../desktop_host.dart';
import 'tray_panel_models.dart';

/// 托盘悬浮面板的「主窗口侧」控制器。
///
/// 面板本身是 desktop_multi_window 拉起的独立引擎窗口，[ensureCreated] 只在
/// 首次点击托盘时创建（惰性），之后复用同一个小窗，避免反复重建引擎带来的
/// 内存与首帧开销。
///
/// 通信走两条单向通道：
/// * [uiChannel]：主 → 面板（推状态、令其显示/隐藏），由面板注册 handler；
/// * [hostChannel]：面板 → 主（上报动作、失焦关闭），由主窗口注册 handler。
class TrayPanelHost {
  TrayPanelHost._();

  static final TrayPanelHost instance = TrayPanelHost._();

  /// 写在子窗口 arguments 里的标识，子引擎据此走面板入口。
  static const String windowArgument = 'txmusic-tray-panel';

  /// 面板尺寸：宽度固定，高度按「播放器区 + 6 个功能项」实测收敛。
  static const Size panelSize = Size(336, 520);

  static const WindowMethodChannel uiChannel = WindowMethodChannel(
    'txmusic/tray_panel_ui',
    mode: ChannelMode.unidirectional,
  );

  static const WindowMethodChannel hostChannel = WindowMethodChannel(
    'txmusic/tray_panel_host',
    mode: ChannelMode.unidirectional,
  );

  WindowController? _controller;
  Future<void>? _creating;
  Completer<void>? _readyCompleter;
  bool _ready = false;
  bool _visible = false;
  DateTime? _lastHiddenAt;
  DateTime? _lastToggleAt;
  TrayPanelState? _latestState;
  void Function(TrayPanelAction action, num? value)? _onAction;

  bool get isVisible => _visible;

  /// 当前引擎是否是面板窗口；主窗口调用时会返回 null（原生查不到窗口定义，
  /// 主引擎抛 PlatformException 属于预期行为）。
  static Future<WindowController?> currentPanelController() async {
    if (!DesktopHost.isDesktopPlatform) {
      return null;
    }
    try {
      final WindowController controller =
          await WindowController.fromCurrentEngine();
      return controller.arguments == windowArgument ? controller : null;
    } on Object catch (error) {
      debugPrint('当前引擎不是多窗口实例：$error');
      return null;
    }
  }

  /// 主窗口初始化时绑定一次：面板上报的动作在这里统一转交给播放器。
  Future<void> bind({
    required void Function(TrayPanelAction action, num? value) onAction,
  }) async {
    _onAction = onAction;
    if (!DesktopHost.isDesktopPlatform) {
      return;
    }
    try {
      await hostChannel.setMethodCallHandler(_handleHostCall);
    } on Object catch (error, stack) {
      debugPrint('托盘面板通道注册失败：$error\n$stack');
    }
  }

  Future<dynamic> _handleHostCall(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        _ready = true;
        final Completer<void>? completer = _readyCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        final TrayPanelState? latest = _latestState;
        if (latest != null) {
          await _push(latest);
        }
        break;
      case 'dismissed':
        // 面板自己判定失焦并隐藏，主窗口只需同步可见标志。
        debugPrint('[panel] dismissed visible=$_visible');
        _visible = false;
        _lastHiddenAt = DateTime.now();
        break;
      case 'action':
        final Object? raw = call.arguments;
        if (raw is Map) {
          final TrayPanelAction? action =
              trayPanelActionFromName('${raw['action']}');
          final Object? value = raw['value'];
          if (action != null) {
            _onAction?.call(action, value is num ? value : null);
          }
        }
        break;
    }
    return null;
  }

  /// 托盘图标点击：面板已显示则收起，否则定位到托盘上方弹出。
  ///
  /// 面板失焦与托盘点击是两条独立路径，用户点托盘想让面板收起时，面板可能
  /// 已经先一步因失焦自行隐藏，此时再 show 会出现「点了关不掉 / 一闪再开」，
  /// 所以刚隐藏的 250ms 内点击一律视为收起动作，不再重新弹出。
  Future<void> toggle({Rect? trayBounds}) async {
    // 同一次物理点击在部分托盘实现里会连发 down/up 两次回调，
    // 不去抖会变成「刚弹出又被自己收起」。
    final DateTime now = DateTime.now();
    final DateTime? lastToggle = _lastToggleAt;
    _lastToggleAt = now;
    if (lastToggle != null &&
        now.difference(lastToggle) < const Duration(milliseconds: 250)) {
      return;
    }
    final DateTime? hiddenAt = _lastHiddenAt;
    if (hiddenAt != null &&
        DateTime.now().difference(hiddenAt) <
            const Duration(milliseconds: 250)) {
      await hide();
      return;
    }
    if (_visible) {
      await hide();
      return;
    }
    await show(trayBounds: trayBounds);
  }

  Future<void> show({Rect? trayBounds}) async {
    if (!DesktopHost.isDesktopPlatform) {
      return;
    }
    try {
      await ensureCreated();
      await _waitUntilReady();
      // 先把最新状态压过去，减少面板亮起瞬间的空态闪烁。
      final TrayPanelState? latest = _latestState;
      if (latest != null) {
        await _push(latest);
      }
      _visible = true;
      final Rect bounds = await _computeBounds(trayBounds);
      debugPrint('[panel] show rect=$bounds');
      await uiChannel.invokeMethod<void>('show', <String, dynamic>{
        'rect': <double>[
          bounds.left,
          bounds.top,
          bounds.width,
          bounds.height,
        ],
      });
    } on Object catch (error) {
      _visible = false;
      debugPrint('托盘面板显示失败：$error');
    }
  }

  /// 定位在托盘图标正上方，并按所在显示器工作区做四边收敛：
  /// 托盘贴底任务栏时向上展开，托盘在屏幕顶部时翻到下方。
  ///
  /// 显示器信息只能在这里取：面板是独立引擎，screen_retriever 没有注册到
  /// 子引擎，面板侧拿不到真实的缩放与工作区。
  Future<Rect> _computeBounds(Rect? trayIn) async {
    const Size size = TrayPanelHost.panelSize;
    const double gap = 8;

    Rect? tray = trayIn;
    Rect workArea = const Rect.fromLTWH(0, 0, 1920, 1040);
    try {
      final List<Display> displays = await screenRetriever.getAllDisplays();
      if (displays.isNotEmpty) {
        // 托盘图标落在任务栏里，任务栏不算工作区，所以「是否越界」只能用整块
        // 屏幕（display.size）判断；用工作区判断会把正常的托盘坐标误判成物理
        // 像素，再折算一次面板就跑到屏幕左边去了。
        if (tray != null) {
          final Rect trayRect = tray;
          final bool inside = displays.any(
            (Display display) =>
                _displayFullRect(display).contains(trayRect.center),
          );
          if (!inside) {
            final double scale = _trayScaleFactor(displays);
            if (scale > 1) {
              tray = Rect.fromLTWH(
                trayRect.left / scale,
                trayRect.top / scale,
                trayRect.width / scale,
                trayRect.height / scale,
              );
            }
          }
        }

        Display target = displays.first;
        final Rect? probe = tray;
        if (probe != null) {
          for (final Display display in displays) {
            if (_displayFullRect(display).contains(probe.center)) {
              target = display;
              break;
            }
          }
        } else {
          target = await screenRetriever.getPrimaryDisplay();
        }
        workArea = _displayRect(target);
      }
    } on Object catch (error) {
      debugPrint('读取显示器信息失败，退回默认工作区：$error');
    }

    final Rect? anchor = tray;
    double x;
    double y;
    if (anchor == null) {
      x = workArea.right - size.width - 12;
      y = workArea.bottom - size.height - 12;
    } else {
      x = anchor.center.dx - size.width / 2;
      y = anchor.top - size.height - gap;
      if (y < workArea.top + gap) {
        y = anchor.bottom + gap;
      }
    }

    final double maxX =
        math.max(workArea.left + gap, workArea.right - size.width - gap);
    final double maxY =
        math.max(workArea.top + gap, workArea.bottom - size.height - gap);
    x = x.clamp(workArea.left + gap, maxX);
    y = y.clamp(workArea.top + gap, maxY);

    return Rect.fromLTWH(x, y, size.width, size.height);
  }

  Rect _displayRect(Display display) {
    final Offset origin = display.visiblePosition ?? Offset.zero;
    final Size size = display.visibleSize ?? display.size;
    if (size.width <= 0 || size.height <= 0) {
      return Rect.fromLTWH(
        origin.dx,
        origin.dy,
        display.size.width,
        display.size.height,
      );
    }
    return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
  }

  /// 显示器整块屏幕的逻辑矩形（含任务栏区域），用于判断托盘坐标归属。
  Rect _displayFullRect(Display display) {
    final Offset origin = display.visiblePosition ?? Offset.zero;
    final Size size = display.size;
    if (size.width <= 0 || size.height <= 0) {
      return _displayRect(display);
    }
    return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
  }

  /// 原生托盘坐标的单位折算系数。
  ///
  /// 优先用主窗口 Flutter 视图的 devicePixelRatio：它和真实系统缩放严格一致。
  /// screen_retriever 报出的 scaleFactor 在高缩放下会偏大（实测 125% 报成
  /// 1.5625），拿它折算会把面板推到托盘左侧一大截，只作兜底。
  double _trayScaleFactor(List<Display> displays) {
    final Iterable<ui.FlutterView> views = ui.PlatformDispatcher.instance.views;
    for (final ui.FlutterView view in views) {
      final double ratio = view.devicePixelRatio;
      if (ratio > 1) {
        return ratio;
      }
    }
    return _maxScaleFactor(displays);
  }

  double _maxScaleFactor(List<Display> displays) {
    double scale = 1;
    for (final Display display in displays) {
      final num? factor = display.scaleFactor;
      if (factor != null && factor.toDouble() > scale) {
        scale = factor.toDouble();
      }
    }
    return scale;
  }

  Future<void> hide() async {
    if (!_visible || !DesktopHost.isDesktopPlatform) {
      _visible = false;
      return;
    }
    _visible = false;
    _lastHiddenAt = DateTime.now();
    try {
      await uiChannel.invokeMethod<void>('hide');
    } on Object catch (error) {
      debugPrint('托盘面板隐藏通道不可用，退回窗口控制器：$error');
      await _controller?.hide();
    }
  }

  /// 播放状态变化时调用；面板不可见时只更新缓存，不产生 IPC。
  Future<void> pushState(TrayPanelState state) async {
    _latestState = state;
    if (!_visible || !_ready) {
      return;
    }
    await _push(state);
  }

  Future<void> _push(TrayPanelState state) async {
    try {
      await uiChannel.invokeMethod<void>('state', state.toJson());
    } on Object catch (error) {
      debugPrint('托盘面板状态推送失败：$error');
    }
  }

  Future<void> ensureCreated() {
    if (_controller != null) {
      return Future<void>.value();
    }
    return _creating ??= _create();
  }

  Future<void> _create() async {
    try {
      _readyCompleter = Completer<void>();
      _controller = await WindowController.create(
        const WindowConfiguration(
          arguments: windowArgument,
          hiddenAtLaunch: true,
        ),
      );
    } on Object {
      _creating = null;
      _readyCompleter = null;
      rethrow;
    }
  }

  Future<void> _waitUntilReady() async {
    if (_ready) {
      return;
    }
    final Completer<void>? completer = _readyCompleter;
    if (completer == null) {
      return;
    }
    // 新引擎冷启动需要一点时间，超时后仍然照常显示（面板自带空态兜底）。
    await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => debugPrint('等待托盘面板就绪超时，继续显示'),
    );
  }
}
