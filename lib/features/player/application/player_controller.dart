import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/i_audio_engine.dart';
import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
import '../data/playback_archive.dart';
import '../data/song_url_resolver.dart';
import '../domain/playback_state.dart';

/// 播放编排：队列推进 + 真实音源解析 + 引擎控制。
///
/// 真实链路（已打通）：
/// `playSong` → `/song/url`（hash + album_id + free_part=1）→ media_kit 直连播放；
/// 播放进度、总时长、播放完成、错误全部来自引擎事件流，不再用计时器模拟。
///
/// 设计约束：
/// - 状态挂在根 ProviderScope 上，路由切换不影响播放（文档 §9.6.3）；
/// - `playSong` 用请求序号 [_requestId] 做竞态保护，快速连点不会出现
///   "后一首被前一首的解析结果覆盖"；
/// - 解析失败不抛异常给 UI，统一落到 [PlaybackStatus.error] + `errorMessage`。
class PlayerController extends Notifier<PlaybackSnapshot> {
  int _requestId = 0;
  StreamSubscription<AudioEngineEvent>? _engineSub;

  /// 引擎里是否真的加载了音源。
  ///
  /// 从本地存档恢复出来的状态只是「待续播」：此时点播放必须重新解析音源
  /// 并 seek 到 [Duration]，不能直接对空引擎 `play()`。
  bool _engineHasMedia = false;

  /// 待续播位置（恢复存档、或在未加载音源时拖动进度条）。
  Duration? _pendingStart;

  /// 上次落盘时刻：position 事件很密集，用它做节流（不挂定时器，
  /// 避免测试/退出时残留 pending timer）。
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 本地存档是否已尝试恢复（只做一次，避免覆盖用户新播的歌）。
  bool _restored = false;

  /// 进度落盘间隔：2 秒足够精确，又不会造成频繁磁盘写入。
  static const Duration _saveInterval = Duration(seconds: 2);

  AudioEngine get _engine => ref.read(audioEngineProvider);

  SongUrlResolver get _resolver => ref.read(songUrlResolverProvider);

  @override
  PlaybackSnapshot build() {
    final AudioEngine engine = ref.read(audioEngineProvider);
    _engineSub = engine.events.listen(_onEngineEvent);
    ref.onDispose(() {
      _engineSub?.cancel();
      _engineSub = null;
    });
    // 启动即恢复上次的听歌信息（曲目 + 进度），异步进行不阻塞首帧。
    unawaited(_restoreFromArchive());
    return const PlaybackSnapshot();
  }

  /// 从 `.local/playback_state.json` 恢复当前曲目与进度。
  ///
  /// 恢复后状态为 [PlaybackStatus.paused] 且引擎未加载音源：界面照常显示
  /// 上次那首歌与进度条，用户点播放时再解析音源并从原位置继续。
  Future<void> _restoreFromArchive() async {
    if (_restored) {
      return;
    }
    _restored = true;

    final PlaybackArchiveStorage storage = ref.read(
      playbackArchiveStorageProvider,
    );
    final PlaybackArchive? archive = await storage.load();
    if (archive == null || state.hasSong) {
      return;
    }

    final Duration position = archive.resumePosition;
    _engineHasMedia = false;
    _pendingStart = position;

    state = state.copyWith(
      currentSong: archive.song,
      status: PlaybackStatus.paused,
      position: position,
      duration: archive.duration > Duration.zero
          ? archive.duration
          : archive.song.duration,
      volume: archive.volume,
      muted: archive.muted,
      repeatMode: archive.repeatMode,
      queue: archive.queue,
      queueIndex: archive.queueIndex,
      clearError: true,
    );
    debugPrint(
      '已恢复上次播放：${archive.song.title} - ${archive.song.artist}'
      '（${position.inSeconds}s）',
    );
  }

  /// 立即把当前听歌信息写入本地（退出前由 [DesktopHost.onBeforeQuit] 调用）。
  Future<void> flushProgress() async {
    final Song? song = state.currentSong;
    if (song == null) {
      return;
    }
    _lastSavedAt = DateTime.now();
    final PlaybackArchive archive = PlaybackArchive(
      song: song,
      queue: state.queue,
      queueIndex: state.queueIndex,
      position: state.position,
      duration: state.duration,
      volume: state.volume,
      muted: state.muted,
      repeatMode: state.repeatMode,
    );
    await ref.read(playbackArchiveStorageProvider).save(archive);
  }

  /// 节流写盘：间隔 [_saveInterval] 内只落一次，避免 position 事件刷盘。
  void _scheduleProgressSave() {
    if (!state.hasSong) {
      return;
    }
    if (DateTime.now().difference(_lastSavedAt) < _saveInterval) {
      return;
    }
    unawaited(flushProgress());
  }

  /// 播放单曲，可传入所在队列（列表/歌单/专辑/榜单）。
  ///
  /// [startAt] 用于「接着上次进度继续听」：音源解析完成后 seek 到该位置。
  Future<void> playSong(
    Song song, {
    List<Song>? queue,
    Duration? startAt,
  }) async {
    final List<Song> list = (queue == null || queue.isEmpty)
        ? <Song>[song]
        : queue;
    int index = list.indexWhere((Song item) => item.id == song.id);
    if (index < 0) {
      index = 0;
    }

    final int request = ++_requestId;
    _engineHasMedia = false;
    state = state.copyWith(
      currentSong: song,
      status: PlaybackStatus.loadingUrl,
      position: startAt ?? Duration.zero,
      duration: song.duration,
      queue: list,
      queueIndex: index,
      clearError: true,
    );

    ResolvedAudio resolved;
    try {
      resolved = await _resolver.resolve(song);
    } on KugouApiException catch (error) {
      _failIfCurrent(request, error.message);
      return;
    } on Object catch (error) {
      _failIfCurrent(request, '音源解析失败：$error');
      return;
    }

    if (request != _requestId) {
      return;
    }

    try {
      state = state.copyWith(
        status: PlaybackStatus.buffering,
        duration: resolved.duration,
      );
      await _engine.open(resolved.url);
      await _engine.setVolume(_effectiveVolume);
      _engineHasMedia = true;
      // 续播：音源解析完成后跳到存档位置，避免「从头再来」。
      final Duration? seekTo = startAt;
      if (seekTo != null && seekTo > Duration.zero) {
        await _engine.seek(seekTo);
      }
      _pendingStart = null;
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        status: PlaybackStatus.playing,
        duration: resolved.duration,
        position: (seekTo != null && seekTo > Duration.zero)
            ? seekTo
            : Duration.zero,
      );
      // 切歌即落盘，保证异常退出后也能接着上一首。
      unawaited(flushProgress());
    } on Object catch (error) {
      _failIfCurrent(request, '播放失败：$error');
    }
  }

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      return;
    }
    final int safeIndex = startIndex.clamp(0, songs.length - 1);
    await playSong(songs[safeIndex], queue: songs);
  }

  void togglePlayPause() {
    if (!state.hasSong) {
      return;
    }
    if (state.isPlaying) {
      pause();
    } else {
      resume();
    }
  }

  void pause() {
    if (!state.hasSong) {
      return;
    }
    state = state.copyWith(status: PlaybackStatus.paused);
    unawaited(_engine.pause());
    unawaited(flushProgress());
  }

  Future<void> resume() async {
    if (!state.hasSong) {
      return;
    }
    // 引擎里没有音源（刚恢复存档 / 上次解析失败）：重新走解析链路并从原进度续播。
    if (state.status == PlaybackStatus.error || !_engineHasMedia) {
      final Song? song = state.currentSong;
      if (song != null) {
        await playSong(
          song,
          queue: state.queue,
          startAt: _pendingStart ?? state.position,
        );
        return;
      }
    }
    state = state.copyWith(status: PlaybackStatus.playing);
    await _engine.play();
  }

  void skipNext() {
    final List<Song> queue = state.queue;
    if (queue.isEmpty) {
      return;
    }
    if (state.repeatMode == RepeatMode.one) {
      restartCurrent();
      return;
    }
    final int nextIndex = state.queueIndex + 1;
    if (nextIndex >= queue.length) {
      if (state.repeatMode == RepeatMode.none) {
        state = state.copyWith(
          status: PlaybackStatus.completed,
          position: Duration.zero,
        );
        unawaited(_engine.pause());
        return;
      }
      unawaited(playSong(queue.first, queue: queue));
      return;
    }
    unawaited(playSong(queue[nextIndex], queue: queue));
  }

  void skipPrevious() {
    final List<Song> queue = state.queue;
    if (queue.isEmpty) {
      return;
    }
    if (state.position.inSeconds > 3) {
      restartCurrent();
      return;
    }
    final int prevIndex = state.queueIndex - 1;
    if (prevIndex < 0) {
      unawaited(playSong(queue.last, queue: queue));
      return;
    }
    unawaited(playSong(queue[prevIndex], queue: queue));
  }

  void restartCurrent() {
    final Song? song = state.currentSong;
    if (song != null && !_engineHasMedia) {
      // 引擎里还没加载音源：重新解析旋律并从头播放。
      unawaited(playSong(song, queue: state.queue, startAt: Duration.zero));
      return;
    }
    state = state.copyWith(
      position: Duration.zero,
      status: PlaybackStatus.playing,
    );
    unawaited(_engine.seek(Duration.zero));
    unawaited(_engine.play());
    unawaited(flushProgress());
  }

  void seek(Duration position) {
    if (!state.hasSong) {
      return;
    }
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : (position > state.duration ? state.duration : position);
    state = state.copyWith(position: clamped);
    if (!_engineHasMedia) {
      // 未加载音源：只记住目标位置，等用户点播放时一起提交。
      _pendingStart = clamped;
      unawaited(flushProgress());
      return;
    }
    unawaited(_engine.seek(clamped));
    unawaited(flushProgress());
  }

  void setVolume(double volume) {
    final double next = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: next, muted: next <= 0);
    unawaited(_engine.setVolume(next));
    // 音量滑杆拖动很频繁，走节流写盘。
    _scheduleProgressSave();
  }

  void nudgeVolume(double delta) => setVolume(state.volume + delta);

  void toggleMute() {
    final bool muted = !state.muted;
    state = state.copyWith(muted: muted);
    unawaited(_engine.setVolume(muted ? 0 : state.volume));
  }

  void cycleRepeatMode() {
    state = state.copyWith(repeatMode: state.repeatMode.nextMode);
    unawaited(flushProgress());
  }

  double get _effectiveVolume => state.muted ? 0 : state.volume;

  void _failIfCurrent(int request, String message) {
    if (request != _requestId) {
      return;
    }
    state = state.copyWith(
      status: PlaybackStatus.error,
      position: Duration.zero,
      errorMessage: message,
    );
  }

  void _onEngineEvent(AudioEngineEvent event) {
    switch (event.type) {
      case AudioEngineEventType.position:
        if (state.status == PlaybackStatus.playing ||
            state.status == PlaybackStatus.buffering) {
          state = state.copyWith(position: event.position);
          // 边听边存：退出/断电后最多丢 2 秒进度。
          _scheduleProgressSave();
        }
      case AudioEngineEventType.duration:
        state = state.copyWith(duration: event.duration);
      case AudioEngineEventType.playing:
        if (!event.playing &&
            state.status == PlaybackStatus.playing &&
            !state.isPlaying) {
          return;
        }
        if (event.playing && state.status == PlaybackStatus.buffering) {
          state = state.copyWith(status: PlaybackStatus.playing);
        }
      case AudioEngineEventType.completed:
        skipNext();
      case AudioEngineEventType.error:
        debugPrint('音频引擎错误: ${event.message}');
        state = state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: event.message ?? '音频引擎异常',
        );
    }
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlaybackSnapshot>(PlayerController.new);
