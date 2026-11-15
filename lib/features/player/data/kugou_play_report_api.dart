import 'package:flutter/foundation.dart';

import '../../../core/network/kugou_client.dart';

/// 酷狗播放行为上报（`module/user_listen_report.js` → `POST /user/listen/report`）。
///
/// 为什么需要它：`/user/grade/info` 的累计听歌时长（分钟）只由服务端根据
/// CSCC 播放上报累加，本地播放器不调这个接口，听歌时长就永远不会增长。
///
/// 上报是 **start / end 一对**：
/// - `event=start`：开始播放某首（`mixsongid` = 歌曲 mixsongid）；
/// - `event=end`：本次播放结束（暂停 / 切歌 / 播放完成），带 `duration`（毫秒）、
///   `d_sec` / `diff_sec`（秒）。
///
/// 该接口对体验不关键，任何失败都只打日志（[_post] 不抛异常），
/// 避免上报问题影响播放链路。
class KugouPlayReportApi {
  KugouPlayReportApi(this._client);

  final KugouClient _client;

  static const String _path = '/user/listen/report';

  /// 服务端会校验 `mixsongid` 是正整数，传歌曲 hash 必被 400 拒掉。
  static final RegExp _numericId = RegExp(r'^\d+$');

  static bool _canReport(String mixSongId) => _numericId.hasMatch(mixSongId);

  /// 播放开始上报。
  ///
  /// 注意：这里**不能**带 `d_sec` / `diff_sec`。服务端把这两个字段当作
  /// 「要同步账号等级时长」，而等级同步只允许出现在 `event=end` 上，
  /// 一旦 start 也带上就会直接 400，整条上报链路断在第一步。
  Future<void> reportStart({required String mixSongId}) {
    if (!_canReport(mixSongId)) {
      return Future<void>.value();
    }
    return _post(<String, dynamic>{
      'event': 'start',
      'mixsongid': mixSongId,
      'duration': 0,
    });
  }

  /// 播放结束上报：`played` 为这一段连续播放的时长。
  ///
  /// `d_sec` / `diff_sec`（秒）是官方累计听歌时长的增量，缺了服务端只记账
  /// 不同步等级时长，听歌时长依旧不涨，所以 end 必须带。
  Future<void> reportEnd({
    required String mixSongId,
    required Duration played,
  }) {
    if (!_canReport(mixSongId)) {
      return Future<void>.value();
    }
    final int millis = played.inMilliseconds.clamp(0, 1 << 31);
    final int seconds = played.inSeconds.clamp(0, 1 << 20);
    return _post(<String, dynamic>{
      'event': 'end',
      'mixsongid': mixSongId,
      'duration': millis,
      'd_sec': seconds,
      'diff_sec': seconds,
    });
  }

  /// 一次性上报「某首歌听了多久」（按 start + end 顺序发）。
  Future<void> report({
    required String mixSongId,
    required Duration played,
  }) async {
    await reportStart(mixSongId: mixSongId);
    await reportEnd(mixSongId: mixSongId, played: played);
  }

  Future<void> _post(Map<String, dynamic> body) async {
    try {
      await _client.postJson(_path, body: body, lenient: true);
    } on Object catch (error) {
      // 未启动本地服务 / 未登录概念版账号都会失败，静默即可。
      if (kDebugMode) {
        debugPrint('播放上报失败(${body['event']}): $error');
      }
    }
  }
}

/// 播放上报计时器：按曲目累计「真正在播」的时长。
///
/// 与 `PlayerController` 解耦，纯 Dart 逻辑便于单测：
/// - [begin]：开始（或续播）计时，同一首重复调用不会重置累计值；
/// - [pause]：暂停时结清本次连续播放时长；
/// - [finish]：取走累计时长并清空，返回需要上报的曲目与时长。
class PlayReportClock {
  String? _songId;
  DateTime? _runningSince;
  Duration _accumulated = Duration.zero;

  String? get songId => _songId;
  bool get isRunning => _runningSince != null;

  /// 开始为 [songId] 计时；换歌时丢弃上一首的累计值。
  void begin(String songId, {DateTime? now}) {
    if (_songId != songId) {
      _songId = songId;
      _accumulated = Duration.zero;
    }
    _runningSince ??= now ?? DateTime.now();
  }

  /// 暂停计时（把本次连续播放时长计入累计）。
  void pause({DateTime? now}) {
    final DateTime? startedAt = _runningSince;
    if (startedAt == null) {
      return;
    }
    final DateTime endAt = now ?? DateTime.now();
    final Duration delta = endAt.difference(startedAt);
    if (delta > Duration.zero) {
      _accumulated += delta;
    }
    _runningSince = null;
  }

  /// 结清并返回 `(mixsongid, 累计播放时长)`；无内容时返回 null。
  ({String songId, Duration played})? finish({DateTime? now}) {
    pause(now: now);
    final String? id = _songId;
    final Duration played = _accumulated;
    _songId = null;
    _accumulated = Duration.zero;
    if (id == null || id.isEmpty || played <= Duration.zero) {
      return null;
    }
    return (songId: id, played: played);
  }

  /// 仅重置（不入账），用于解析失败等场景。
  void reset() {
    _songId = null;
    _runningSince = null;
    _accumulated = Duration.zero;
  }
}
