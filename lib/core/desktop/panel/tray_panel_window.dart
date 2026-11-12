import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tray_panel_host.dart';
import 'tray_panel_models.dart';

/// 面板配色：深色磨砂黑 + 青蓝渐变强调色，不跟随主窗口主题（面板始终浮在
/// 其他应用之上，深浅主题切换反而会让它和背景撞色）。
const Color _accent = Color(0xFF3DDC97);
const Color _accentAlt = Color(0xFF22D3EE);
const Color _danger = Color(0xFFFF5F63);
const Color _textPrimary = Color(0xFFF1F4F5);
const Color _textSecondary = Color(0xFF9AA4A8);

/// 面板窗口的原生通道：无边框样式、置顶、圆角与显隐都在 runner 侧实现。
///
/// 这里不能用 window_manager：它的窗口句柄是进程级单值，注册到子引擎会把
/// 主窗口的窗口操作劫持到面板上。
const MethodChannel _windowChannel = MethodChannel('txmusic/tray_panel_native');

/// 面板窗口入口：由 main.dart 判定当前引擎是多窗口实例后调用。
Future<void> runTrayPanelWindow() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _TrayPanelApp());
}

class _TrayPanelApp extends StatelessWidget {
  const _TrayPanelApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Microsoft YaHei UI',
        splashFactory: NoSplash.splashFactory,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accentAlt,
          surface: Color(0xFF14181A),
          error: _danger,
        ),
      ),
      home: const TrayPanelView(),
    );
  }
}

/// 面板视图：纯被动渲染 + 动作回传，不持有播放状态。
class TrayPanelView extends StatefulWidget {
  const TrayPanelView({super.key});

  @override
  State<TrayPanelView> createState() => _TrayPanelViewState();
}

class _TrayPanelViewState extends State<TrayPanelView> {
  TrayPanelState _state = const TrayPanelState();
  int? _dragPositionMs;

  @override
  void initState() {
    super.initState();
    // 原生侧在面板失去激活时先隐藏再发 blurred，Dart 只负责同步状态。
    _windowChannel.setMethodCallHandler(_handleWindowCall);
    TrayPanelHost.uiChannel
        .setMethodCallHandler(_handleUiCall)
        .then((_) => _notifyReady())
        .catchError((Object error) {
      debugPrint('托盘面板 UI 通道注册失败：$error');
      _notifyReady();
    });
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleWindowCall(MethodCall call) async {
    if (call.method == 'blurred') {
      await _hideSelf();
    }
    return null;
  }

  Future<void> _notifyReady() async {
    try {
      await TrayPanelHost.hostChannel.invokeMethod<void>('ready');
    } on Object catch (error) {
      debugPrint('托盘面板上报就绪失败：$error');
    }
  }

  Future<dynamic> _handleUiCall(MethodCall call) async {
    switch (call.method) {
      case 'state':
        final Object? raw = call.arguments;
        if (raw is Map && mounted) {
          setState(() => _state = TrayPanelState.fromJson(raw));
        }
        break;
      case 'show':
        final Object? raw = call.arguments;
        await _present(raw is Map ? raw : const <String, dynamic>{});
        break;
      case 'hide':
        await _hideSelf();
        break;
    }
    return null;
  }

  /// 显示面板。窗口位置由主窗口算好（子引擎没有 screen_retriever），这里只把
  /// 矩形交给原生 SetWindowPos。
  Future<void> _present(Map<dynamic, dynamic> arguments) async {
    final List<double> rect = _parseRect(arguments['rect']) ??
        <double>[
          0,
          0,
          TrayPanelHost.panelSize.width,
          TrayPanelHost.panelSize.height,
        ];
    try {
      await _windowChannel.invokeMethod<void>('show', <String, dynamic>{
        'x': rect[0].round(),
        'y': rect[1].round(),
        'width': rect[2].round(),
        'height': rect[3].round(),
      });
    } on Object catch (error) {
      debugPrint('托盘面板显示失败：$error');
    }
  }

  List<double>? _parseRect(Object? raw) {
    if (raw is! List || raw.length != 4) {
      return null;
    }
    return raw
        .map<double>((Object? value) => value is num ? value.toDouble() : 0)
        .toList(growable: false);
  }

  Future<void> _hideSelf() async {
    try {
      await _windowChannel.invokeMethod<void>('hide');
    } on Object catch (error) {
      debugPrint('托盘面板隐藏失败：$error');
    }
    try {
      await TrayPanelHost.hostChannel.invokeMethod<void>('dismissed');
    } on Object catch (error) {
      debugPrint('托盘面板上报关闭失败：$error');
    }
  }

  Future<void> _dispatch(TrayPanelAction action, [num? value]) async {
    try {
      await TrayPanelHost.hostChannel.invokeMethod<void>('action', <String, dynamic>{
        'action': action.name,
        'value': value,
      });
    } on Object catch (error) {
      debugPrint('托盘面板动作发送失败：$error');
    }
    switch (action) {
      case TrayPanelAction.showMainWindow:
      case TrayPanelAction.openPlayer:
      case TrayPanelAction.openLibrary:
      case TrayPanelAction.openSettings:
      case TrayPanelAction.quit:
        await _hideSelf();
      case TrayPanelAction.togglePlayPause:
      case TrayPanelAction.skipPrevious:
      case TrayPanelAction.skipNext:
      case TrayPanelAction.seek:
      case TrayPanelAction.toggleFavorite:
      case TrayPanelAction.cycleRepeatMode:
      case TrayPanelAction.toggleMute:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _dispatch(TrayPanelAction.togglePlayPause),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            () => _dispatch(TrayPanelAction.skipPrevious),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            () => _dispatch(TrayPanelAction.skipNext),
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () =>
            _dispatch(TrayPanelAction.showMainWindow),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _dispatch(TrayPanelAction.toggleFavorite),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            _dispatch(TrayPanelAction.cycleRepeatMode),
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () =>
            _dispatch(TrayPanelAction.quit),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(_hideSelf()),
      },
      child: Focus(autofocus: true, child: _buildPanel(context)),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return Scaffold(
      // 窗口本身由 DWM 裁成圆角，底色给深色，兜住自绘圆角与系统圆角之间的
      // 那几像素差值，避免角落闪白。
      backgroundColor: const Color(0xFF121618),
      body: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF1E2326), Color(0xFF0E1113)],
            ),
            border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
          ),
          child: Stack(
            children: <Widget>[
              // 左上角一抹青蓝柔光，模拟磨砂玻璃的边缘高光。
              Positioned(
                left: -60,
                top: -70,
                child: IgnorePointer(
                  child: Container(
                    width: 200,
                    height: 160,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: <Color>[Color(0x333DDC97), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                children: <Widget>[
                  _buildPlayerSection(),
                  const Divider(height: 1, thickness: 1, color: Color(0x14FFFFFF)),
                  Expanded(child: _buildActionList()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSection() {
    final int durationMs = math.max(_state.durationMs, 0);
    final double maxValue = durationMs <= 0 ? 1 : durationMs.toDouble();
    final double sliderValue =
        (_dragPositionMs ?? _state.positionMs).toDouble().clamp(0, maxValue);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _PanelCover(
                seed: _state.album.isEmpty ? _state.title : _state.album,
                url: _state.coverUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      _state.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _state.errorMessage ?? _state.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _state.errorMessage != null
                            ? _danger
                            : _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _accent,
              inactiveTrackColor: const Color(0x33FFFFFF),
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: SizedBox(
              height: 18,
              child: Slider(
                value: sliderValue,
                max: maxValue,
                onChanged: _state.hasSong
                    ? (double value) => setState(
                        () => _dragPositionMs = value.round())
                    : null,
                onChangeEnd: _state.hasSong
                    ? (double value) {
                        setState(() => _dragPositionMs = null);
                        _dispatch(TrayPanelAction.seek, value.round());
                      }
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _formatMs((_dragPositionMs ?? _state.positionMs)),
                  style: const TextStyle(fontSize: 10.5, color: _textSecondary),
                ),
                Text(
                  _formatMs(durationMs),
                  style: const TextStyle(fontSize: 10.5, color: _textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _CircleIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一曲',
                size: 36,
                onTap: () => _dispatch(TrayPanelAction.skipPrevious),
              ),
              const SizedBox(width: 14),
              _PlayButton(
                isPlaying: _state.isPlaying,
                isLoading: _state.isLoading,
                onTap: () => _dispatch(TrayPanelAction.togglePlayPause),
              ),
              const SizedBox(width: 14),
              _CircleIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一曲',
                size: 36,
                onTap: () => _dispatch(TrayPanelAction.skipNext),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionList() {
    final bool hasSong = _state.hasSong;
    // 内容固定为 6 项，用 Column 而不是 ListView：面板高度就是内容高度，
    // 列表一旦可滚动，末两项（含红色「退出」）会被挤到视口外出不来。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
        _PanelActionTile(
          icon: Icons.open_in_new_rounded,
          label: '显示主窗口',
          shortcut: 'Ctrl+M',
          onTap: () => _dispatch(TrayPanelAction.showMainWindow),
        ),
        _PanelActionTile(
          icon: _state.liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconColor: _state.liked ? _accent : null,
          label: _state.liked ? '取消收藏' : '收藏当前歌曲',
          shortcut: 'Ctrl+L',
          enabled: hasSong,
          onTap: () => _dispatch(TrayPanelAction.toggleFavorite),
        ),
        _PanelActionTile(
          icon: Icons.repeat_rounded,
          iconColor: _state.repeatActive ? _accent : null,
          label: '播放模式 · ${_state.repeatLabel}',
          shortcut: 'Ctrl+R',
          onTap: () => _dispatch(TrayPanelAction.cycleRepeatMode),
        ),
        _PanelActionTile(
          icon: Icons.queue_music_rounded,
          label: _state.favoriteCount > 0 ? '我喜欢（${_state.favoriteCount}）' : '我喜欢',
          shortcut: 'Ctrl+F',
          onTap: () => _dispatch(TrayPanelAction.openLibrary),
        ),
        _PanelActionTile(
          icon: Icons.tune_rounded,
          label: '设置',
          onTap: () => _dispatch(TrayPanelAction.openSettings),
        ),
        _PanelActionTile(
          icon: Icons.power_settings_new_rounded,
          label: '退出 TX Music',
          shortcut: 'Ctrl+Q',
          danger: true,
          onTap: () => _dispatch(TrayPanelAction.quit),
        ),
        ],
      ),
    );
  }

  String _formatMs(int milliseconds) {
    final int totalSeconds = math.max(milliseconds, 0) ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 方形封面：面板是独立引擎，拿不到主窗口的主题扩展，网络图自己加载自己缓存；
/// 地址为空或加载失败时退回「文字指纹 → 渐变」占位，保证观感不塌。
class _PanelCover extends StatelessWidget {
  const _PanelCover({required this.seed, this.url});

  final String seed;

  /// 主引擎推来的封面地址（已补 `{size}` 与 https）。
  final String? url;

  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF1DB954), Color(0xFF0B3D2C)],
    <Color>[Color(0xFF6C5CE7), Color(0xFF1B1663)],
    <Color>[Color(0xFFE17055), Color(0xFF4A1E17)],
    <Color>[Color(0xFF00B8D9), Color(0xFF073B4C)],
    <Color>[Color(0xFF22D3EE), Color(0xFF0B2E3A)],
    <Color>[Color(0xFF3DDC97), Color(0xFF0C332A)],
  ];

  List<Color> get _colors {
    if (seed.isEmpty) {
      return _palettes.first;
    }
    final int hash =
        seed.codeUnits.fold<int>(0, (int sum, int unit) => sum + unit);
    return _palettes[hash % _palettes.length];
  }

  Widget get _fallback => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: _colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          size: 22,
          color: Colors.white.withValues(alpha: 0.92),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final String src = (url ?? '').trim();
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: src.isEmpty
          ? _fallback
          : CachedNetworkImage(
              imageUrl: src,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 120),
              fadeOutDuration: Duration.zero,
              placeholder: (BuildContext context, String _) => _fallback,
              errorWidget: (BuildContext context, String _, Object error) =>
                  _fallback,
            ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
  });

  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isPlaying ? '暂停' : '播放',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[_accentAlt, _accent],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _accent.withValues(alpha: 0.32),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF04120C),
                  ),
                )
              : Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 26,
                  color: const Color(0xFF04120C),
                ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatefulWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback onTap;

  @override
  State<_CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<_CircleIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered ? const Color(0x1FFFFFFF) : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 22,
              color: _hovered ? _textPrimary : const Color(0xFFD6DEE0),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelActionTile extends StatefulWidget {
  const _PanelActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.danger = false,
    this.enabled = true,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? shortcut;
  final bool danger;
  final bool enabled;
  final Color? iconColor;

  @override
  State<_PanelActionTile> createState() => _PanelActionTileState();
}

class _PanelActionTileState extends State<_PanelActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = widget.danger
        ? _danger
        : widget.enabled
            ? _textPrimary
            : const Color(0x66F1F4F5);
    final Color icColor = widget.iconColor ??
        (widget.danger
            ? _danger
            : widget.enabled
                ? const Color(0xFFC9D3D6)
                : const Color(0x66F1F4F5));

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: _hovered && widget.enabled
                ? const Color(0x14FFFFFF)
                : Colors.transparent,
          ),
          child: Row(
            children: <Widget>[
              Icon(widget.icon, size: 17, color: icColor),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.8,
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.shortcut != null)
                Text(
                  widget.shortcut!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0x8A9AA4A8),
                    letterSpacing: 0.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
