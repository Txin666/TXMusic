import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../../core/storage/local_store.dart';
import '../data/kugou_vip_api.dart';

/// 每日 VIP 状态（UI 只读；写入走 [DailyVipController]）。
@immutable
class DailyVipState {
  const DailyVipState({
    this.autoClaim = true,
    this.busy = false,
    this.lastClaimDate = '',
    this.lastAttemptAt = '',
    this.lastMessage = '',
    this.lastSuccess = false,
    this.lastSteps = const <String>[],
    this.snapshot = VipSnapshot.empty,
  });

  /// 是否开启「登录即自动领取」。
  final bool autoClaim;

  /// 正在领取中（防重入）。
  final bool busy;

  /// 最近一次成功领取的日期（`yyyy-MM-dd`），用于跨天判断。
  final String lastClaimDate;

  /// 最近一次发起领取的时间（ISO8601），失败后用于退避，避免高频重试触发风控。
  final String lastAttemptAt;

  final String lastMessage;
  final bool lastSuccess;
  final List<String> lastSteps;
  final VipSnapshot snapshot;

  bool get claimedToday => lastClaimDate == DailyVipController.today();

  DailyVipState copyWith({
    bool? autoClaim,
    bool? busy,
    String? lastClaimDate,
    String? lastAttemptAt,
    String? lastMessage,
    bool? lastSuccess,
    List<String>? lastSteps,
    VipSnapshot? snapshot,
  }) {
    return DailyVipState(
      autoClaim: autoClaim ?? this.autoClaim,
      busy: busy ?? this.busy,
      lastClaimDate: lastClaimDate ?? this.lastClaimDate,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSuccess: lastSuccess ?? this.lastSuccess,
      lastSteps: lastSteps ?? this.lastSteps,
      snapshot: snapshot ?? this.snapshot,
    );
  }
}

/// 每日自动领 VIP 编排（参考 MoeKoeMusic「登录即 VIP」思路）。
///
/// 触发时机（三处，全部幂等）：
/// 1. 应用启动  —— [bootstrap]
/// 2. 登录成功  —— 登录流程末尾调用 [claimIfNeeded]
/// 3. 常驻定时器 —— 每小时检查一次，跨天自动补领（软件挂机过夜也能领到）
///
/// 领取记录落 `.local/daily_vip.json`，同一天不会重复请求接口，
/// 避免触发酷狗风控。
class DailyVipController extends Notifier<DailyVipState> {
  static const String _fileName = 'daily_vip.json';

  Timer? _watchTimer;
  bool _booted = false;

  static String today() {
    final DateTime now = DateTime.now();
    final String month = now.month < 10 ? '0${now.month}' : '${now.month}';
    final String day = now.day < 10 ? '0${now.day}' : '${now.day}';
    return '${now.year}-$month-$day';
  }

  @override
  DailyVipState build() {
    ref.onDispose(() {
      _watchTimer?.cancel();
      _watchTimer = null;
    });
    return const DailyVipState();
  }

  /// 应用启动时调用一次：读本地记录 → 起定时器 → 若今天还没领就领。
  Future<void> bootstrap() async {
    if (_booted) {
      return;
    }
    _booted = true;

    final Map<String, dynamic> json =
        await LocalStore.readJson(_fileName);
    if (json.isNotEmpty) {
      state = state.copyWith(
        autoClaim: json['auto_claim'] != false,
        lastClaimDate: '${json['last_claim_date'] ?? ''}',
        lastAttemptAt: '${json['last_attempt_at'] ?? ''}',
        lastMessage: '${json['last_message'] ?? ''}',
        lastSuccess: json['last_success'] == true,
        lastSteps: (json['last_steps'] is List)
            ? (json['last_steps'] as List<Object?>)
                .map<String>((Object? item) => '$item')
                .toList(growable: false)
            : const <String>[],
      );
    }

    _watchTimer ??= Timer.periodic(
      const Duration(hours: 1),
      (Timer timer) => unawaited(claimIfNeeded()),
    );

    await claimIfNeeded();
  }

  /// 开关：关闭后不再自动请求接口（手动按钮仍可用）。
  Future<void> setAutoClaim(bool enabled) async {
    state = state.copyWith(autoClaim: enabled);
    await _persist();
    if (enabled) {
      await claimIfNeeded();
    }
  }

  /// 今天还没领、且已登录、且开关打开时执行领取。
  Future<void> claimIfNeeded() async {
    if (!state.autoClaim || state.busy) {
      return;
    }
    if (!ref.read(kugouSessionProvider).isLoggedIn) {
      return;
    }
    if (state.claimedToday) {
      return;
    }
    // 失败退避：上一次尝试不到 60 分钟就跳过，当天最多试 24 次以内的量级，
    // 避免 token 失效时每小时硬撞接口。
    if (_inCooldown()) {
      return;
    }
    await claimNow();
  }

  /// 是否处于失败退避窗口内。
  bool _inCooldown() {
    final String raw = state.lastAttemptAt;
    if (raw.isEmpty) {
      return false;
    }
    final DateTime? last = DateTime.tryParse(raw);
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) < const Duration(minutes: 60);
  }

  /// 立即领取（设置页手动按钮 / 定时任务共用）。
  Future<void> claimNow() async {
    if (state.busy) {
      return;
    }
    if (!ref.read(kugouSessionProvider).isLoggedIn) {
      state = state.copyWith(
        lastMessage: '未登录酷狗账号，无法领取 VIP',
        lastSuccess: false,
      );
      return;
    }

    state = state.copyWith(
      busy: true,
      lastAttemptAt: DateTime.now().toIso8601String(),
      lastMessage: '正在领取今日 VIP…',
    );
    final KugouVipApi api = ref.read(kugouVipApiProvider);

    try {
      final DailyVipClaimResult result = await api.claimDailyVip();
      // 领完再拉一次权益，界面能直接看到到期时间。
      final VipSnapshot snapshot = await api.detail();
      state = state.copyWith(
        busy: false,
        lastClaimDate: result.isOk ? today() : state.lastClaimDate,
        lastMessage: result.message,
        lastSuccess: result.isOk,
        lastSteps: result.steps,
        snapshot: snapshot,
      );
    } on Object catch (error) {
      state = state.copyWith(
        busy: false,
        lastMessage: '领取失败：$error',
        lastSuccess: false,
      );
    }
    await _persist();
  }

  /// 刷新权益展示（不触发领取）。
  Future<void> refreshSnapshot() async {
    if (!ref.read(kugouSessionProvider).isLoggedIn) {
      return;
    }
    final VipSnapshot snapshot = await ref.read(kugouVipApiProvider).detail();
    state = state.copyWith(snapshot: snapshot);
  }

  Future<void> _persist() async {
    await LocalStore.writeJson(_fileName, <String, dynamic>{
      'auto_claim': state.autoClaim,
      'last_claim_date': state.lastClaimDate,
      'last_attempt_at': state.lastAttemptAt,
      'last_message': state.lastMessage,
      'last_success': state.lastSuccess,
      'last_steps': state.lastSteps,
      'vip': state.snapshot.summary,
    });
  }
}

final NotifierProvider<DailyVipController, DailyVipState>
    dailyVipControllerProvider =
    NotifierProvider<DailyVipController, DailyVipState>(
  DailyVipController.new,
);
