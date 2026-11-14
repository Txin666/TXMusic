import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../song/domain/song.dart';
import '../domain/playback_state.dart';

/// 播放进度存档：用户退出前的「当前听歌信息」。
///
/// 落盘位置 `.local/playback_state.json`（与酷狗登录态同目录，已被
/// `.gitignore` 忽略），只存本地，不上云、不涉及任何账号信息。
///
/// 记录内容：
/// - 当前曲目 [song] 与所在队列 [queue]（含 [queueIndex]，恢复后可继续
///   上一首/下一首）；
/// - 进度 [position] 与总时长 [duration]；
/// - 音量 / 静音 / 循环模式等播放偏好。
@immutable
class PlaybackArchive {
  const PlaybackArchive({
    required this.song,
    this.queue = const <Song>[],
    this.queueIndex = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 0.7,
    this.muted = false,
    this.repeatMode = RepeatMode.all,
    this.savedAt,
  });

  /// 队列最多存 200 首：够还原上下文，又不让 JSON 无限膨胀。
  static const int queueLimit = 200;

  /// 进度距离结尾不足该时长时视为「已听完」，下次从头播放。
  static const Duration endTolerance = Duration(seconds: 5);

  final Song song;
  final List<Song> queue;
  final int queueIndex;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool muted;
  final RepeatMode repeatMode;
  final DateTime? savedAt;

  /// 真正用于续播的进度：非法值与「已听完」的尾巴统一归零。
  Duration get resumePosition {
    if (position <= Duration.zero) {
      return Duration.zero;
    }
    final Duration total = duration > Duration.zero ? duration : song.duration;
    if (total > Duration.zero && total - position <= endTolerance) {
      return Duration.zero;
    }
    return position;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'song': song.toJson(),
    'queue': queue.take(queueLimit).map((Song item) => item.toJson()).toList(),
    'queueIndex': queueIndex,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'volume': volume,
    'muted': muted,
    'repeatMode': repeatMode.name,
    'savedAt': DateTime.now().toIso8601String(),
  };

  /// 解析存档；结构不合法（无歌曲 / 无 hash）时返回 null，调用方按空态处理。
  static PlaybackArchive? fromJson(Map<String, dynamic> json) {
    final Song? song = Song.fromJson(json['song']);
    if (song == null) {
      return null;
    }

    final List<Song> queue = <Song>[];
    final Object? rawQueue = json['queue'];
    if (rawQueue is List) {
      for (final Object? item in rawQueue) {
        final Song? parsed = Song.fromJson(item);
        if (parsed != null) {
          queue.add(parsed);
        }
      }
    }
    if (queue.isEmpty) {
      queue.add(song);
    }

    int queueIndex = _toInt(json['queueIndex']);
    if (queueIndex < 0 || queueIndex >= queue.length) {
      final int found = queue.indexWhere((Song item) => item.hash == song.hash);
      queueIndex = found < 0 ? 0 : found;
    }

    return PlaybackArchive(
      song: song,
      queue: List<Song>.unmodifiable(queue),
      queueIndex: queueIndex,
      position: Duration(milliseconds: _toInt(json['positionMs'])),
      duration: Duration(milliseconds: _toInt(json['durationMs'])),
      volume: _toDouble(json['volume'], 0.7),
      muted: json['muted'] == true,
      repeatMode: _parseRepeatMode(json['repeatMode']),
      savedAt: DateTime.tryParse('${json['savedAt'] ?? ''}'),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? 0}') ?? 0;
  }

  static double _toDouble(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble().clamp(0.0, 1.0);
    }
    final double? parsed = double.tryParse('${value ?? ''}');
    if (parsed == null) {
      return fallback;
    }
    return parsed.clamp(0.0, 1.0);
  }

  static RepeatMode _parseRepeatMode(Object? value) {
    final String name = '${value ?? ''}';
    for (final RepeatMode mode in RepeatMode.values) {
      if (mode.name == name) {
        return mode;
      }
    }
    return RepeatMode.all;
  }
}

/// 播放进度存档读写接口。
///
/// 抽成接口是为了让测试注入内存实现，避免测试读写用户真实的
/// `.local/playback_state.json`。
abstract class PlaybackArchiveStorage {
  const PlaybackArchiveStorage();

  static const String fileName = 'playback_state.json';

  Future<PlaybackArchive?> load();

  Future<void> save(PlaybackArchive archive);

  Future<void> clear();
}

/// 默认实现：单文件落盘到 `.local/playback_state.json`，读写失败一律静默
/// 降级（不阻塞启动与播放）。
class LocalPlaybackArchiveStorage extends PlaybackArchiveStorage {
  const LocalPlaybackArchiveStorage();

  @override
  Future<PlaybackArchive?> load() async {
    final Map<String, dynamic> json = await LocalStore.readJson(
      PlaybackArchiveStorage.fileName,
    );
    if (json.isEmpty) {
      return null;
    }
    try {
      return PlaybackArchive.fromJson(json);
    } on Object catch (error) {
      debugPrint('解析播放进度存档失败: $error');
      return null;
    }
  }

  @override
  Future<void> save(PlaybackArchive archive) =>
      LocalStore.writeJson(PlaybackArchiveStorage.fileName, archive.toJson());

  @override
  Future<void> clear() => LocalStore.delete(PlaybackArchiveStorage.fileName);
}

/// 存档读写入口：默认落本地文件，测试可通过 override 换成内存实现。
final Provider<PlaybackArchiveStorage> playbackArchiveStorageProvider =
    Provider<PlaybackArchiveStorage>(
      (Ref ref) => const LocalPlaybackArchiveStorage(),
    );

