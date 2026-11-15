import 'package:flutter/foundation.dart';

/// 酷狗账号个人信息快照。
///
/// 数据聚合自本地 KuGouMusicApi 的四个真实接口（均已实测）：
/// - `GET /user/detail`    昵称、头像、性别、粉丝 / 关注 / 好友 / 访客
/// - `GET /user/info`      注册时间（乐龄依据）、账号名、签名、绑定信息
/// - `GET /user/grade/info` 累计听歌时长 `duration`（**分钟**，与官方客户端口径一致）、
///   听歌等级成长值
/// - `GET /user/vip/detail` 概念版 VIP 权益
/// - `GET /user/listen`    本周 / 累计听歌统计
///
/// 所有字段都按「能拿到就展示、拿不到就显示占位」处理，不写死任何演示数据。
@immutable
class UserProfile {
  const UserProfile({
    this.userid = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.signature = '',
    this.gender = 0,
    this.region = '',
    this.registeredAt,
    this.listenMinutes = 0,
    this.grade = 0,
    this.gradePoint = 0,
    this.nextGradePoint = 0,
    this.finishPercent = 0,
    this.fans = 0,
    this.follows = 0,
    this.friends = 0,
    this.visitors = 0,
    this.weekListenCount = 0,
    this.totalListenCount = 0,
    this.isVip = false,
    this.vipExpireAt,
    this.username = '',
    this.loginMobile = '',
    this.bindings = const <String>[],
  });

  final String userid;
  final String nickname;
  final String avatarUrl;
  final String signature;

  /// 1 = 男，2 = 女，其它视为未知。
  final int gender;

  /// `省 市` 拼接结果，未设置时为空串。
  final String region;

  /// 注册时间：乐龄（注册天数）的唯一依据。
  final DateTime? registeredAt;

  /// 累计听歌时长（**分钟**），来自 `/user/grade/info` 的 `duration`。
  ///
  /// 注意单位：酷狗官方客户端展示的「听歌 xxxx 分钟」与接口 `duration` 数值完全一致，
  /// 说明该字段口径就是分钟（早期按秒解读会导致时长被缩小 60 倍）。
  final int listenMinutes;

  /// 听歌等级（`p_grade`）及当前成长值 / 下一级所需成长值。
  final int grade;
  final int gradePoint;
  final int nextGradePoint;

  /// 资料完整度（`finish_percent`）。
  final int finishPercent;

  final int fans;
  final int follows;
  final int friends;
  final int visitors;

  /// 本周 / 累计听歌次数（`/user/listen` 的 `total_week` / `total_history`）。
  final int weekListenCount;
  final int totalListenCount;

  final bool isVip;
  final DateTime? vipExpireAt;

  /// 酷狗账号名（`username`，形如 `kgopen2615679232`）。
  final String username;

  /// 绑定的手机号（部分账号为空，接口不回传时保持空串）。
  final String loginMobile;

  /// 已绑定的第三方渠道名（微信 / QQ 等），来自 `third_info`。
  final List<String> bindings;

  static const UserProfile empty = UserProfile();

  /// 是否拿到了可展示的资料。
  bool get hasData => userid.isNotEmpty || nickname.isNotEmpty;

  /// 乐龄：注册至今的整天数（注册时间为空时为 0）。
  int get listenAgeDays {
    final DateTime? reg = registeredAt;
    if (reg == null) {
      return 0;
    }
    final int days = DateTime.now().difference(reg).inDays;
    return days < 0 ? 0 : days;
  }

  /// 累计听歌时长（按接口口径，单位分钟）。
  Duration get listenDuration =>
      Duration(minutes: listenMinutes < 0 ? 0 : listenMinutes);

  bool get hasListenDuration => listenMinutes > 0;

  /// 升级到下一级还差多少成长值。
  int get gradeGap {
    final int gap = nextGradePoint - gradePoint;
    return gap < 0 ? 0 : gap;
  }

  /// 等级进度（0~1）：成长值 / 下一级所需。
  double get gradeProgress {
    if (nextGradePoint <= 0) {
      return 0;
    }
    final double ratio = gradePoint / nextGradePoint;
    return ratio.clamp(0, 1).toDouble();
  }

  String get genderLabel {
    switch (gender) {
      case 1:
        return '男';
      case 2:
        return '女';
      default:
        return '未设置';
    }
  }

  /// VIP 到期文案（未开通或到期时间未知时为空）。
  String get vipSummary {
    final DateTime? end = vipExpireAt;
    if (!isVip || end == null) {
      return isVip ? 'VIP 生效中' : '';
    }
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${end.year}-${two(end.month)}-${two(end.day)} 到期';
  }

  UserProfile copyWith({
    String? userid,
    String? nickname,
    String? avatarUrl,
    String? signature,
    int? gender,
    String? region,
    DateTime? registeredAt,
    int? listenMinutes,
    int? grade,
    int? gradePoint,
    int? nextGradePoint,
    int? finishPercent,
    int? fans,
    int? follows,
    int? friends,
    int? visitors,
    int? weekListenCount,
    int? totalListenCount,
    bool? isVip,
    DateTime? vipExpireAt,
    String? username,
    String? loginMobile,
    List<String>? bindings,
  }) {
    return UserProfile(
      userid: userid ?? this.userid,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      signature: signature ?? this.signature,
      gender: gender ?? this.gender,
      region: region ?? this.region,
      registeredAt: registeredAt ?? this.registeredAt,
      listenMinutes: listenMinutes ?? this.listenMinutes,
      grade: grade ?? this.grade,
      gradePoint: gradePoint ?? this.gradePoint,
      nextGradePoint: nextGradePoint ?? this.nextGradePoint,
      finishPercent: finishPercent ?? this.finishPercent,
      fans: fans ?? this.fans,
      follows: follows ?? this.follows,
      friends: friends ?? this.friends,
      visitors: visitors ?? this.visitors,
      weekListenCount: weekListenCount ?? this.weekListenCount,
      totalListenCount: totalListenCount ?? this.totalListenCount,
      isVip: isVip ?? this.isVip,
      vipExpireAt: vipExpireAt ?? this.vipExpireAt,
      username: username ?? this.username,
      loginMobile: loginMobile ?? this.loginMobile,
      bindings: bindings ?? this.bindings,
    );
  }
}
