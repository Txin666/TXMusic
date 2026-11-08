import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../song/domain/song.dart';
import '../domain/playback_state.dart';

/// 播放编排：队列推进 + 播放控制。
///
/// 骨架期说明（重要）：
/// - 真实音频链路（`/song/url` 解析 → media_kit 引擎）尚未接入，
///   这里仅用 1 秒定时器模拟播放进度，保证进度条、切歌、暂停等交互真实可感知；
/// - 播放状态挂在根 ProviderScope 上，路由切换不影响播放（文档 §9.6.3）；
/// - TODO(audio): 接入 `services/audio/i_audio_engine.dart` 与 `url_resolver.dart` 后，
///   把 `_startTicker` 替换为引擎事件流订阅。
class PlayerController extends Notifier<PlaybackSnapshot> {
  Timer? _ticker;

  @override
  PlaybackSnapshot build() {
    ref.onDispose(() => _ticker?.cancel());
    return const PlaybackSnapshot();
  }

  /// 播放单曲，可传入所在队列（列表/歌单/专辑/榜单）。
  void playSong(Song song, {List<Song>? queue}) {
    final List<Song> list = (queue == null || queue.isEmpty) ? <Song>[song] : queue;
    int index = list.indexWhere((Song item) => item.id == song.id);
    if (index < 0) {
      index = 0;
    }
    state = state.copyWith(
      currentSong: song,
      status: PlaybackStatus.loadingUrl,
      position: Duration.zero,
      duration: song.duration,
      queue: list,
      queueIndex: index,
    );

    // TODO(audio): 此处应等待 URL 解析完成后再进入 playing。
    state = state.copyWith(status: PlaybackStatus.playing);
    _startTicker();
  }

  void playQueue(List<Song> songs, {int startIndex = 0}) {
    if (songs.isEmpty) {
      return;
    }
    final int safeIndex = startIndex.clamp(0, songs.length - 1);
    playSong(songs[safeIndex], queue: songs);
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
    _stopTicker();
  }

  void resume() {
    if (!state.hasSong) {
      return;
    }
    state = state.copyWith(status: PlaybackStatus.playing);
    _startTicker();
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
        _stopTicker();
        return;
      }
      playSong(queue.first, queue: queue);
      return;
    }
    playSong(queue[nextIndex], queue: queue);
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
      playSong(queue.last, queue: queue);
      return;
    }
    playSong(queue[prevIndex], queue: queue);
  }

  void restartCurrent() {
    state = state.copyWith(
      position: Duration.zero,
      status: PlaybackStatus.playing,
    );
    _startTicker();
  }

  void seek(Duration position) {
    if (!state.hasSong) {
      return;
    }
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : (position > state.duration ? state.duration : position);
    state = state.copyWith(position: clamped);
  }

  void setVolume(double volume) {
    state = state.copyWith(volume: volume.clamp(0.0, 1.0), muted: volume <= 0);
  }

  void nudgeVolume(double delta) => setVolume(state.volume + delta);

  void toggleMute() => state = state.copyWith(muted: !state.muted);

  void cycleRepeatMode() =>
      state = state.copyWith(repeatMode: state.repeatMode.nextMode);

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!state.isPlaying) {
        return;
      }
      final Duration next = state.position + const Duration(seconds: 1);
      if (next >= state.duration) {
        skipNext();
        return;
      }
      state = state.copyWith(position: next);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlaybackSnapshot>(PlayerController.new);
