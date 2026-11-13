/// 音频引擎抽象：UI / 状态层只依赖本接口，便于替换实现（media_kit / 其它）
/// 或在单元测试中注入假引擎（开发文档 §3.2 services 层）。
library;

/// 引擎事件类型。
enum AudioEngineEventType { position, duration, playing, completed, error }

/// 引擎事件：位置推进、总时长、播放/暂停、播放完成、错误。
class AudioEngineEvent {
  const AudioEngineEvent({
    required this.type,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.message,
  });

  const AudioEngineEvent.position(Duration value)
    : type = AudioEngineEventType.position,
      position = value,
      duration = Duration.zero,
      playing = false,
      message = null;

  const AudioEngineEvent.duration(Duration value)
    : type = AudioEngineEventType.duration,
      position = Duration.zero,
      duration = value,
      playing = false,
      message = null;

  const AudioEngineEvent.playing(bool value)
    : type = AudioEngineEventType.playing,
      position = Duration.zero,
      duration = Duration.zero,
      playing = value,
      message = null;

  const AudioEngineEvent.completed()
    : type = AudioEngineEventType.completed,
      position = Duration.zero,
      duration = Duration.zero,
      playing = false,
      message = null;

  const AudioEngineEvent.error(String value)
    : type = AudioEngineEventType.error,
      position = Duration.zero,
      duration = Duration.zero,
      playing = false,
      message = value;

  final AudioEngineEventType type;
  final Duration position;
  final Duration duration;
  final bool playing;
  final String? message;
}

/// 播放器引擎能力集合。
abstract class AudioEngine {
  /// 引擎事件流（广播）。
  Stream<AudioEngineEvent> get events;

  /// 打开音源（网络 URL 直连播放）。
  Future<void> open(Uri url, {bool autoPlay = true});

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  /// 音量 0.0 ~ 1.0。
  Future<void> setVolume(double volume);

  Future<void> dispose();
}
