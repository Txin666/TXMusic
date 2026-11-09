import '../../song/domain/song.dart';

/// 播放状态枚举（对应文档 §3.2 player/domain/playback_state.dart）。
enum PlaybackStatus { idle, loadingUrl, buffering, playing, paused, completed, error }

/// 循环模式。
enum RepeatMode { none, all, one }

extension RepeatModeX on RepeatMode {
  String get label {
    switch (this) {
      case RepeatMode.none:
        return '顺序播放';
      case RepeatMode.all:
        return '列表循环';
      case RepeatMode.one:
        return '单曲循环';
    }
  }

  RepeatMode get nextMode {
    switch (this) {
      case RepeatMode.none:
        return RepeatMode.all;
      case RepeatMode.all:
        return RepeatMode.one;
      case RepeatMode.one:
        return RepeatMode.none;
    }
  }
}

/// 播放快照：不可变状态 + copyWith（文档 §9.2 NotifierProvider 约束）。
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.currentSong,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 0.7,
    this.muted = false,
    this.repeatMode = RepeatMode.all,
    this.queue = const <Song>[],
    this.queueIndex = -1,
    this.errorMessage,
  });

  final Song? currentSong;
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool muted;
  final RepeatMode repeatMode;
  final List<Song> queue;
  final int queueIndex;

  /// 音源解析/播放失败原因（[PlaybackStatus.error] 时展示给用户）。
  final String? errorMessage;

  bool get hasSong => currentSong != null;

  bool get isPlaying => status == PlaybackStatus.playing;

  bool get isLoading =>
      status == PlaybackStatus.loadingUrl || status == PlaybackStatus.buffering;

  double get progress {
    if (duration.inMilliseconds <= 0) {
      return 0;
    }
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  PlaybackSnapshot copyWith({
    Song? currentSong,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? volume,
    bool? muted,
    RepeatMode? repeatMode,
    List<Song>? queue,
    int? queueIndex,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlaybackSnapshot(
      currentSong: currentSong ?? this.currentSong,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      repeatMode: repeatMode ?? this.repeatMode,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
