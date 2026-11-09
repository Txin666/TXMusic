import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'i_audio_engine.dart';

/// 基于 media_kit（libmpv）的音频引擎实现。
///
/// 说明：
/// - 网络 mp3 直连播放（实测 206 Partial Content / audio/mpeg 可正常播放）；
/// - media_kit 的 `setVolume` 取值 0~100，本类对外保持 0.0~1.0 语义；
/// - 使用 audio 版 windows 依赖（media_kit_libs_windows_audio），不额外拉视频库。
class MediaKitAudioEngine implements AudioEngine {
  MediaKitAudioEngine() {
    _bind();
  }

  final Player _player = Player();
  final StreamController<AudioEngineEvent> _events =
      StreamController<AudioEngineEvent>.broadcast();
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  bool _disposed = false;

  @override
  Stream<AudioEngineEvent> get events => _events.stream;

  void _bind() {
    _subs.add(_player.stream.position.listen((Duration value) {
      _emit(AudioEngineEvent.position(value));
    }));
    _subs.add(_player.stream.duration.listen((Duration value) {
      if (value > Duration.zero) {
        _emit(AudioEngineEvent.duration(value));
      }
    }));
    _subs.add(_player.stream.playing.listen((bool value) {
      _emit(AudioEngineEvent.playing(value));
    }));
    _subs.add(_player.stream.completed.listen((bool value) {
      if (value) {
        _emit(const AudioEngineEvent.completed());
      }
    }));
    _subs.add(_player.stream.error.listen((String value) {
      if (value.isNotEmpty) {
        _emit(AudioEngineEvent.error(value));
      }
    }));
  }

  void _emit(AudioEngineEvent event) {
    if (_disposed || _events.isClosed) {
      return;
    }
    _events.add(event);
  }

  @override
  Future<void> open(Uri url, {bool autoPlay = true}) async {
    await _player.open(Media(url.toString()), play: autoPlay);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) {
    final double clamped = volume.clamp(0.0, 1.0);
    return _player.setVolume(clamped * 100);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final StreamSubscription<Object?> sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _events.close();
    try {
      await _player.dispose();
    } on Object catch (error) {
      debugPrint('释放 media_kit 失败: $error');
    }
  }
}
