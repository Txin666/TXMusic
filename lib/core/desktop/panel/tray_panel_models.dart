/// 托盘悬浮面板的跨窗口数据契约。
///
/// 面板运行在 desktop_multi_window 创建的第二引擎里，无法直接访问主引擎的
/// Riverpod 容器，所以主窗口把播放状态压成纯 JSON 推给面板，面板把用户操作
/// 以[托盘面板动作]回传主窗口执行。此文件只依赖 Dart 基础类型，core 层不反向
/// 依赖 features。
library;

/// 面板可触发的动作，全部由主窗口（唯一播放状态持有者）执行。
enum TrayPanelAction {
  togglePlayPause,
  skipPrevious,
  skipNext,
  seek,
  toggleFavorite,
  cycleRepeatMode,
  toggleMute,
  showMainWindow,
  openPlayer,
  openLibrary,
  openSettings,
  quit,
}

/// 动作序列化名 → 枚举，未知名字返回 null（版本不一致时不炸掉面板）。
TrayPanelAction? trayPanelActionFromName(String name) {
  for (final TrayPanelAction action in TrayPanelAction.values) {
    if (action.name == name) {
      return action;
    }
  }
  return null;
}

/// 主窗口推给面板的展示快照。
class TrayPanelState {
  const TrayPanelState({
    this.hasSong = false,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.coverUrl = '',
    this.isPlaying = false,
    this.isLoading = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.liked = false,
    this.repeatLabel = '列表循环',
    this.repeatActive = false,
    this.favoriteCount = 0,
    this.volume = 0.8,
    this.muted = false,
    this.errorMessage,
  });

  final bool hasSong;
  final String title;
  final String artist;
  final String album;

  /// 封面网络地址（主引擎已规范化），面板侧独立引擎自行加载。
  final String coverUrl;
  final bool isPlaying;
  final bool isLoading;
  final int positionMs;
  final int durationMs;
  final bool liked;
  final String repeatLabel;
  final bool repeatActive;
  final int favoriteCount;
  final double volume;
  final bool muted;
  final String? errorMessage;

  /// 本地演示 / 未起播时也展示占位信息，避免面板一片空白。
  String get displayTitle => hasSong ? title : '暂无播放';
  String get displayArtist => hasSong ? artist : '从主窗口挑一首歌开始';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'hasSong': hasSong,
    'title': title,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'isPlaying': isPlaying,
    'isLoading': isLoading,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'liked': liked,
    'repeatLabel': repeatLabel,
    'repeatActive': repeatActive,
    'favoriteCount': favoriteCount,
    'volume': volume,
    'muted': muted,
    'errorMessage': errorMessage,
  };

  factory TrayPanelState.fromJson(Map<dynamic, dynamic> json) {
    int asInt(Object? value) => value is num ? value.toInt() : 0;
    double asDouble(Object? value) => value is num ? value.toDouble() : 0;
    bool asBool(Object? value) => value is bool ? value : false;
    String asString(Object? value) => value is String ? value : '';

    return TrayPanelState(
      hasSong: asBool(json['hasSong']),
      title: asString(json['title']),
      artist: asString(json['artist']),
      album: asString(json['album']),
      coverUrl: asString(json['coverUrl']),
      isPlaying: asBool(json['isPlaying']),
      isLoading: asBool(json['isLoading']),
      positionMs: asInt(json['positionMs']),
      durationMs: asInt(json['durationMs']),
      liked: asBool(json['liked']),
      repeatLabel: asString(json['repeatLabel']).isEmpty
          ? '列表循环'
          : asString(json['repeatLabel']),
      repeatActive: asBool(json['repeatActive']),
      favoriteCount: asInt(json['favoriteCount']),
      volume: asDouble(json['volume']),
      muted: asBool(json['muted']),
      errorMessage: json['errorMessage'] is String
          ? json['errorMessage'] as String
          : null,
    );
  }
}
