import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/i_audio_engine.dart';
import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
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
    return const PlaybackSnapshot();
  }

  /// 播放单曲，可传入所在队列（列表/歌单/专辑/榜单）。
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    final List<Song> list = (queue == null || queue.isEmpty)
        ? <Song>[song]
        : queue;
    int index = list.indexWhere((Song item) => item.id == song.id);
    if (index < 0) {
      index = 0;
    }

    final int request = ++_requestId;
    state = state.copyWith(
      currentSong: song,
      status: PlaybackStatus.loadingUrl,
      position: Duration.zero,
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
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        status: PlaybackStatus.playing,
        duration: resolved.duration,
      );
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
  }

  Future<void> resume() async {
    if (!state.hasSong) {
      return;
    }
    if (state.status == PlaybackStatus.error) {
      // 失败后重试同曲：重新走一遍解析链路。
      final Song? song = state.currentSong;
      if (song != null) {
        await playSong(song, queue: state.queue);
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
    state = state.copyWith(
      position: Duration.zero,
      status: PlaybackStatus.playing,
    );
    unawaited(_engine.seek(Duration.zero));
    unawaited(_engine.play());
  }

  void seek(Duration position) {
    if (!state.hasSong) {
      return;
    }
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : (position > state.duration ? state.duration : position);
    state = state.copyWith(position: clamped);
    unawaited(_engine.seek(clamped));
  }

  void setVolume(double volume) {
    final double next = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: next, muted: next <= 0);
    unawaited(_engine.setVolume(next));
  }

  void nudgeVolume(double delta) => setVolume(state.volume + delta);

  void toggleMute() {
    final bool muted = !state.muted;
    state = state.copyWith(muted: muted);
    unawaited(_engine.setVolume(muted ? 0 : state.volume));
  }

  void cycleRepeatMode() =>
      state = state.copyWith(repeatMode: state.repeatMode.nextMode);

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
