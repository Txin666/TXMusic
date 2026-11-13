import 'package:flutter/foundation.dart';

import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../vip/data/kugou_vip_api.dart';
import '../domain/user_profile.dart';

/// 个人信息接口聚合层。
///
/// 五个接口彼此独立，**任何一个失败都不能影响其它字段展示**，因此每个请求单独
/// try/catch，失败只记日志并留空，最终合并成一份 [UserProfile]。
///
/// 实测要点：
/// - 未登录（无 userid / token）时这些接口统一回 502，所以调用前必须先判断登录态；
/// - `/user/info` 的 `reg_time` 是 `yyyy-MM-dd HH:mm:ss`（本地时区，无时区后缀）；
/// - `/user/grade/info` 的 `duration` 单位是**秒**，新账号为 0；
/// - `/user/vip/detail` 复用 [VipSnapshot] 的宽松解析，避免结构变化把整页拖崩。
class KugouUserApi {
  KugouUserApi(this._client);

  final KugouClient _client;

  /// 并行拉取并合并个人资料。
  Future<UserProfile> load() async {
    final List<Map<String, dynamic>> payloads = await Future.wait(
      <Future<Map<String, dynamic>>>[
        _get('/user/detail'),
        _get('/user/info'),
        _get('/user/grade/info'),
        _get(
          '/user/vip/detail',
          query: <String, dynamic>{'busi_type': 'concept'},
        ),
        _get('/user/listen'),
      ],
    );

    final Map<String, dynamic> detail = payloads[0];
    final Map<String, dynamic> info = payloads[1];
    final Map<String, dynamic> grade = payloads[2];
    final Map<String, dynamic> listen = payloads[4];

    final VipSnapshot vip = VipSnapshot.fromDetailJson(payloads[3]);

    return UserProfile(
      userid: _str(info, <String>['userid'], detail).isEmpty
          ? _client.session.userid
          : _str(info, <String>['userid'], detail),
      nickname: _str(detail, <String>[
        'nickname',
        'k_nickname',
        'username',
      ], info),
      avatarUrl: _str(detail, <String>['pic', 'k_pic'], info),
      signature: _str(info, <String>['signature']),
      // 性别：`/user/detail` 的 gender 优先，缺失（0）时回落到 `/user/info` 的 sex。
      gender: _firstPositive(<int>[
        _int(detail, <String>['gender'], info),
        _int(info, <String>['sex']),
      ]),
      region: _region(info, detail),
      registeredAt: _dateTime(_str(info, <String>['reg_time'])),
      listenSeconds: _int(grade, <String>['duration']),
      grade: _int(grade, <String>['p_grade']),
      gradePoint: _int(grade, <String>['p_current_point', 'p_grade_point']),
      nextGradePoint: _int(grade, <String>['p_next_grade_point']),
      finishPercent: _int(grade, <String>['finish_percent'], info),
      fans: _int(detail, <String>['fans']),
      follows: _int(detail, <String>['follows']),
      friends: _int(detail, <String>['friend_total', 'friends_count']),
      visitors: _int(detail, <String>['visitors', 'visitor_count']),
      weekListenCount: _int(listen, <String>['total_week']),
      totalListenCount: _int(listen, <String>['total_history']),
      isVip: vip.isVip,
      vipExpireAt: vip.expireAt,
      username: _str(info, <String>['username']),
      loginMobile: _str(info, <String>['login_mobile', 'mobile']),
      bindings: _bindings(info),
    );
  }

  /// 单个接口请求：失败返回空 Map，不向上抛异常。
  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      return await _client.getJson(path, query: query, lenient: true);
    } on Object catch (error) {
      debugPrint('个人信息接口失败 $path: $error');
      return const <String, dynamic>{};
    }
  }

  // ---- 解析工具：接口数据可能挂在 `data` 层，也可能直接平铺 ----

  static Map<String, dynamic> _data(Map<String, dynamic> json) {
    return JsonUtils.asMap(json['data']) ?? json;
  }

  /// 先主来源、后兜底来源，两处都先看 `data` 层再看顶层。
  static Object? _pick(
    Map<String, dynamic> json,
    List<String> keys, [
    Map<String, dynamic>? fallback,
  ]) {
    Object? value =
        JsonUtils.pick(_data(json), keys) ?? JsonUtils.pick(json, keys);
    if ((value == null || '$value'.trim().isEmpty) && fallback != null) {
      value =
          JsonUtils.pick(_data(fallback), keys) ??
          JsonUtils.pick(fallback, keys);
    }
    return value;
  }

  static String _str(
    Map<String, dynamic> json,
    List<String> keys, [
    Map<String, dynamic>? fallback,
  ]) {
    return JsonUtils.str(_pick(json, keys, fallback));
  }

  /// 取第一个 > 0 的候选值，全为 0 时返回 0。
  static int _firstPositive(List<int> values) {
    for (final int value in values) {
      if (value > 0) {
        return value;
      }
    }
    return 0;
  }

  static int _int(
    Map<String, dynamic> json,
    List<String> keys, [
    Map<String, dynamic>? fallback,
  ]) {
    return JsonUtils.integer(_pick(json, keys, fallback));
  }

  /// `province` + `city`：两者都为空时返回空串。
  static String _region(
    Map<String, dynamic> info,
    Map<String, dynamic> detail,
  ) {
    final String province = _str(info, <String>['province'], detail);
    final String city = _str(info, <String>['city'], detail);
    if (province.isEmpty && city.isEmpty) {
      return '';
    }
    if (province.isEmpty || province == city) {
      return city.isEmpty ? province : city;
    }
    if (city.isEmpty) {
      return province;
    }
    return '$province $city';
  }

  /// 解析 `yyyy-MM-dd HH:mm:ss`（也兼容 `yyyy-MM-dd`）。
  static DateTime? _dateTime(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }

  /// 第三方绑定渠道：`third_info` 的 key 形如 `pid_36`，按渠道码翻成人话。
  static List<String> _bindings(Map<String, dynamic> info) {
    final Map<String, dynamic> data = _data(info);
    final Map<String, dynamic>? third =
        JsonUtils.asMap(data['third_info']) ??
        JsonUtils.asMap(info['third_info']);
    if (third == null || third.isEmpty) {
      return const <String>[];
    }
    const Map<String, String> names = <String, String>{
      'pid_36': '微信',
      'pid_2': 'QQ',
      'pid_5': '微博',
      'pid_39': 'Apple',
      'pid_33': '抖音',
    };
    final List<String> result = <String>[];
    for (final String key in third.keys) {
      if (JsonUtils.asMap(third[key]) == null) {
        continue;
      }
      final String code = key.replaceFirst('pid_', '');
      result.add(names[key] ?? '渠道 $code');
    }
    return result;
  }
}
