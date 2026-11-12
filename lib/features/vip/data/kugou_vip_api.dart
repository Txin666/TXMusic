import 'package:flutter/foundation.dart';

import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';

/// 概念版 VIP 快照（`/user/vip/detail` → `kugouvip/v1/get_union_vip`）。
///
/// 该接口返回结构随账号权益变化（有时是 `data.vip_list[]`，有时直接平铺），
/// 因此统一用「深度找键」的方式宽松解析，解析不到就退回空快照，绝不抛异常
/// 影响主流程。
@immutable
class VipSnapshot {
  const VipSnapshot({
    this.isVip = false,
    this.vipLabel = '',
    this.expireAt,
  });

  final bool isVip;

  /// 原始权益标识（`vip_type` / `is_vip` 等），仅用于展示与排查。
  final String vipLabel;

  final DateTime? expireAt;

  static const VipSnapshot empty = VipSnapshot();

  String get summary {
    if (!isVip) {
      return '当前非 VIP';
    }
    if (expireAt == null) {
      return 'VIP 生效中';
    }
    final DateTime end = expireAt!;
    final String text = '${end.year}-${_two(end.month)}-${_two(end.day)} '
        '${_two(end.hour)}:${_two(end.minute)}';
    return 'VIP 到期 $text';
  }

  static String _two(int value) => value < 10 ? '0$value' : '$value';

  /// 从 `/user/vip/detail` 的完整 JSON 解析快照。
  static VipSnapshot fromDetailJson(Map<String, dynamic> json) {
    final Object? data = json['data'] ?? json;
    final Object? rawExpire = _deepFind(data, const <String>{
      'end_time',
      'expire_time',
      'vip_end_time',
      'endTime',
      'expireTime',
    });
    final Object? rawType = _deepFind(data, const <String>{
      'vip_type',
      'vipType',
      'is_vip',
      'isVip',
      'business_type',
    });

    DateTime? expireAt;
    final int ts = JsonUtils.integer(rawExpire);
    if (ts > 0) {
      // 秒 / 毫秒两套时间戳都出现过。
      expireAt = DateTime.fromMillisecondsSinceEpoch(ts > 100000000000 ? ts : ts * 1000);
    }

    final String label = JsonUtils.str(rawType);
    final bool flagByType = label.isNotEmpty && label != '0' && label != 'false';
    final bool flagByTime = expireAt != null && expireAt.isAfter(DateTime.now());

    return VipSnapshot(
      isVip: flagByTime || (flagByType && expireAt == null),
      vipLabel: label,
      expireAt: expireAt,
    );
  }

  /// 递归找键（最多 4 层），命中第一个非空值即返回。
  static Object? _deepFind(Object? node, Set<String> keys, [int depth = 0]) {
    if (node == null || depth > 4) {
      return null;
    }
    final Map<String, dynamic>? map = JsonUtils.asMap(node);
    if (map != null) {
      for (final String key in keys) {
        final Object? value = map[key];
        if (value != null && '$value'.trim().isNotEmpty) {
          return value;
        }
      }
      for (final Object? child in map.values) {
        final Object? hit = _deepFind(child, keys, depth + 1);
        if (hit != null) {
          return hit;
        }
      }
      return null;
    }
    if (node is List) {
      for (final Object? child in node) {
        final Object? hit = _deepFind(child, keys, depth + 1);
        if (hit != null) {
          return hit;
        }
      }
    }
    return null;
  }
}

/// 每日领取结果状态。
enum DailyVipStatus { success, alreadyClaimed, needLogin, failed }

@immutable
class DailyVipClaimResult {
  const DailyVipClaimResult({
    required this.status,
    required this.message,
    required this.at,
    this.steps = const <String>[],
  });

  final DailyVipStatus status;
  final String message;
  final DateTime at;

  /// 分步执行轨迹（听歌上报 → 领取 → 升级奖励），便于出问题时定位。
  final List<String> steps;

  bool get isOk =>
      status == DailyVipStatus.success ||
      status == DailyVipStatus.alreadyClaimed;
}

/// 概念版「听歌领 VIP」任务接口。
///
/// 全部对应本地 KuGouMusicApi 的 `module/youth_*.js`，仅在服务端
/// `platform=lite`（概念版）且已登录时有效：
/// - `POST /youth/listen/song`        听歌上报（领 VIP 的前置条件）
/// - `POST /youth/day/vip`            领取 1 天 VIP（`receive_day`）
/// - `POST /youth/day/vip/upgrade`    听歌时长升级奖励
/// - `GET  /user/vip/detail`          查联合 VIP 权益
class KugouVipApi {
  KugouVipApi(this._client);

  final KugouClient _client;

  String get _userid => _client.session.userid;

  /// 查询当前 VIP 权益；失败返回 [VipSnapshot.empty]，不抛异常。
  Future<VipSnapshot> detail() async {
    try {
      final Map<String, dynamic> json = await _client.getJson(
        '/user/vip/detail',
        query: <String, dynamic>{'busi_type': 'concept'},
        lenient: true,
      );
      return VipSnapshot.fromDetailJson(json);
    } on Object catch (error) {
      debugPrint('查询 VIP 权益失败: $error');
      return VipSnapshot.empty;
    }
  }

  /// 听歌上报（`/youth/v2/report/listen_song`）。
  ///
  /// `mixsongid` 服务端有默认值（666075191），这里不传即可完成一次上报。
  Future<void> reportListenSong() async {
    await _client.postJson(
      '/youth/listen/song',
      body: <String, dynamic>{'mixsongid': 666075191},
      lenient: true,
    );
  }

  /// 领取每日 VIP。
  ///
  /// `receive_day` 是**日期字符串**（次日 `yyyy-MM-dd`），不是天数：
  /// - 传今天或数字天数 → 上游报 `304003`（日期不能小于今天）/ `20002`
  /// - 传次日           → 成功，天卡次日生效
  /// - 重复领取         → `131001`（今日已领）
  Future<void> receiveDailyVip() async {
    await _client.postJson(
      '/youth/day/vip',
      query: <String, dynamic>{'source_id': 90139, 'receive_day': tomorrow()},
      lenient: true,
    );
  }

  /// 领取用的目标日期：本地时区的次日（`yyyy-MM-dd`）。
  ///
  /// 必须用本地时区计算，不能走 UTC —— 凌晨 0~8 点时 UTC 还停在昨天，
  /// 上游会直接判「日期不能小于今天」。
  static String tomorrow([DateTime? from]) {
    final DateTime base = (from ?? DateTime.now()).add(const Duration(days: 1));
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${base.year}-${two(base.month)}-${two(base.day)}';
  }

  /// 听歌时长升级奖励（把体验权益升成正式 VIP）。
  ///
  /// 服务端 `module/youth_day_vip_upgrade.js` 从 `params.userid` 或 cookie 里取
  /// kugouid 并固定 `ad_type=1`，因此本地传 userid 即可满足参数校验。
  Future<void> upgradeReward() async {
    await _client.postJson(
      '/youth/day/vip/upgrade',
      query: <String, dynamic>{'userid': JsonUtils.integer(_userid)},
      lenient: true,
    );
  }

  /// 完整领取编排：听歌上报 → 领取一天 → 升级奖励。
  ///
  /// 设计原则：**上报与升级都失败也不阻断领取**，任一步出问题只记进 [steps]，
  /// 最终状态以「领取」这一步的结果为准。
  Future<DailyVipClaimResult> claimDailyVip() async {
    final DateTime at = DateTime.now();
    final List<String> steps = <String>[];
    final String receiveDay = tomorrow();

    if (_userid.isEmpty) {
      return DailyVipClaimResult(
        status: DailyVipStatus.needLogin,
        message: '未登录酷狗账号，无法领取 VIP',
        at: at,
        steps: steps,
      );
    }

    // 1) 听歌上报：概念版任务的前置动作，失败先记下继续。
    try {
      await reportListenSong();
      steps.add('听歌上报：成功');
    } on Object catch (error) {
      steps.add('听歌上报：失败（$error）');
    }

    // 2) 正式领取（`receive_day` 必须是次日日期字符串）。
    Map<String, dynamic> json;
    try {
      json = await _client.postJson(
        '/youth/day/vip',
        query: <String, dynamic>{'source_id': 90139, 'receive_day': receiveDay},
        lenient: true,
      );
    } on Object catch (error) {
      return DailyVipClaimResult(
        status: DailyVipStatus.failed,
        message: '领取请求失败：$error',
        at: at,
        steps: steps,
      );
    }

    final Object? rawError = json['error_code'] ?? json['errcode'];
    final bool hasErrorCode =
        rawError != null && '$rawError'.trim().isNotEmpty;
    final int? errorCode = hasErrorCode ? JsonUtils.integer(rawError) : null;
    final int statusFlag = JsonUtils.integer(json['status']);
    final String rawMessage =
        JsonUtils.str(json['error_msg'] ?? json['errmsg'] ?? json['msg']);
    steps.add(
      '领取接口：error_code=${errorCode ?? '-'} status=$statusFlag'
      '${rawMessage.isEmpty ? '' : ' · $rawMessage'}',
    );

    final DailyVipStatus status = _judge(errorCode, statusFlag, rawMessage);

    // 3) 升级奖励：只在领取成功/已领过时尝试，失败不影响结论。
    if (status == DailyVipStatus.success ||
        status == DailyVipStatus.alreadyClaimed) {
      try {
        await upgradeReward();
        steps.add('升级奖励：成功');
      } on Object catch (error) {
        steps.add('升级奖励：跳过（$error）');
      }
    }

    return DailyVipClaimResult(
      status: status,
      message: _friendly(status, errorCode, rawMessage),
      at: at,
      steps: steps,
    );
  }

  /// 结果判定。
  ///
  /// 优先级：文案命中（已领取 / 未登录）→ `error_code` → `status` 标志位。
  /// `status` 在酷狗接口里 1 表示成功、0 表示失败，缺 `error_code` 时以它为准。
  static DailyVipStatus _judge(
    int? errorCode,
    int statusFlag,
    String message,
  ) {
    final String text = message.toLowerCase();
    if (text.contains('已领取') ||
        text.contains('已经领取') ||
        text.contains('重复领取') ||
        text.contains('already')) {
      return DailyVipStatus.alreadyClaimed;
    }
    if (text.contains('登录') ||
        text.contains('token') ||
        errorCode == 31001) {
      return DailyVipStatus.needLogin;
    }
    // 131001：该日期的天卡已领过，等价于「今天已经领完了」。
    if (errorCode == 131001) {
      return DailyVipStatus.alreadyClaimed;
    }
    if (errorCode != null) {
      return errorCode == 0 ? DailyVipStatus.success : DailyVipStatus.failed;
    }
    if (statusFlag == 1) {
      return DailyVipStatus.success;
    }
    return DailyVipStatus.failed;
  }

  static String _friendly(DailyVipStatus status, int? errorCode, String raw) {
    switch (status) {
      case DailyVipStatus.success:
        return '已领取 1 天 VIP（次日生效）';
      case DailyVipStatus.alreadyClaimed:
        return '今天已经领过了';
      case DailyVipStatus.needLogin:
        return '登录态失效，请重新登录酷狗账号';
      case DailyVipStatus.failed:
        if (errorCode == 304003) {
          return '领取日期不合法（上游要求次日日期）';
        }
        if (raw.isNotEmpty) {
          return raw;
        }
        return errorCode == null ? '领取失败，接口未返回原因' : '领取失败（错误码 $errorCode）';
    }
  }
}
