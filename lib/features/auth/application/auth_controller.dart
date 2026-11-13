import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../../core/network/kugou_session.dart';
import '../../vip/application/daily_vip_controller.dart';
import '../data/kugou_login_api.dart';

/// 登录阶段：四种登录方式共用同一套状态机。
enum AuthPhase { idle, loading, waiting, scanned, success, expired, error }

/// 登录表单本地校验（不发请求，先挡住明显非法输入）。
class AuthValidators {
  const AuthValidators._();

  static final RegExp _mobile = RegExp(r'^1[3-9]\d{9}$');

  /// 返回 null 表示合法，否则返回可直接展示的错误文案。
  static String? mobileError(String mobile) {
    final String value = mobile.trim();
    if (value.isEmpty) {
      return '请输入手机号';
    }
    if (!_mobile.hasMatch(value)) {
      return '手机号格式不正确（11 位中国大陆号码）';
    }
    return null;
  }

  static String? codeError(String code) {
    final String value = code.trim();
    if (value.isEmpty) {
      return '请输入短信验证码';
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(value)) {
      return '验证码应为 4~6 位数字';
    }
    return null;
  }
}

@immutable
class AuthState {
  const AuthState({
    this.method = LoginMethod.kugouQr,
    this.phase = AuthPhase.idle,
    this.qrImage = '',
    this.message = '',
    this.nickname = '',
    this.countdown = 0,
  });

  final LoginMethod method;
  final AuthPhase phase;

  /// 二维码图片（纯 base64，不含 `data:` 前缀）；短信登录时为空。
  final String qrImage;
  final String message;
  final String nickname;

  /// 短信验证码重发倒计时（秒），0 表示可发送。
  final int countdown;

  bool get isBusy => phase == AuthPhase.loading;

  bool get isScanning =>
      phase == AuthPhase.waiting || phase == AuthPhase.scanned;

  bool get hasQr => qrImage.isNotEmpty;

  AuthState copyWith({
    LoginMethod? method,
    AuthPhase? phase,
    String? qrImage,
    String? message,
    String? nickname,
    int? countdown,
    bool clearQr = false,
  }) {
    return AuthState(
      method: method ?? this.method,
      phase: phase ?? this.phase,
      qrImage: clearQr ? '' : (qrImage ?? this.qrImage),
      message: message ?? this.message,
      nickname: nickname ?? this.nickname,
      countdown: countdown ?? this.countdown,
    );
  }
}

/// 登录编排：手机验证码 / 微信扫码 / QQ 扫码 / 酷狗 App 扫码。
///
/// 全流程由用户本人在软件界面内完成：助手不代收验证码、不代扫二维码、
/// 不接触账号密码；成功后只把 token / userid 写入本机
/// `.local/kugou_cookie.json`（通过 [KugouSessionController.signIn]）。
class AuthController extends Notifier<AuthState> {
  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _pollBusy = false;
  int _pollFailures = 0;

  String? _kugouKey;
  WechatQrSession? _wechat;
  QqQrSession? _qq;

  @override
  AuthState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
      _countdownTimer?.cancel();
      _countdownTimer = null;
    });
    return const AuthState();
  }

  // ------------------------------------------------------------ 方式切换

  /// 进入登录页时调用：扫码方式若还没出码则自动生成一张。
  Future<void> ensureStarted() async {
    if (state.method == LoginMethod.sms) {
      return;
    }
    if (state.phase == AuthPhase.idle) {
      await refreshQr();
    }
  }

  /// 切换登录方式：停掉旧轮询、重置状态，扫码方式立刻出新码。
  Future<void> selectMethod(LoginMethod method) async {
    if (state.method == method) {
      return;
    }
    _stopPolling();
    state = AuthState(method: method, countdown: state.countdown);
    if (method != LoginMethod.sms) {
      await refreshQr();
    }
  }

  /// 生成 / 刷新当前方式的二维码。
  Future<void> refreshQr() async {
    final LoginMethod method = state.method;
    if (method == LoginMethod.sms) {
      return;
    }
    _stopPolling();
    final int countdown = state.countdown;
    _kugouKey = null;
    _wechat = null;
    _qq = null;
    state = AuthState(
      method: method,
      phase: AuthPhase.loading,
      message: '正在生成二维码…',
      countdown: countdown,
    );

    final KugouLoginApi api = ref.read(kugouLoginApiProvider);
    try {
      switch (method) {
        case LoginMethod.kugouQr:
          final LoginQr qr = await api.createQr();
          if (state.method != method) {
            return;
          }
          _kugouKey = qr.key;
          state = AuthState(
            method: method,
            phase: AuthPhase.waiting,
            qrImage: qr.rawBase64,
            message: '打开手机酷狗 App → 扫一扫',
            countdown: countdown,
          );
          _startPolling();
        case LoginMethod.wechat:
          final WechatQrSession session = await api.createWechatQr();
          if (state.method != method) {
            return;
          }
          _wechat = session;
          state = AuthState(
            method: method,
            phase: AuthPhase.waiting,
            qrImage: session.rawBase64,
            message: '打开微信 → 扫一扫',
            countdown: countdown,
          );
          _startPolling();
        case LoginMethod.qq:
          final QqQrSession session = await api.createQqQr();
          if (state.method != method) {
            return;
          }
          _qq = session;
          state = AuthState(
            method: method,
            phase: AuthPhase.waiting,
            qrImage: session.rawBase64,
            message: '打开手机 QQ → 扫一扫',
            countdown: countdown,
          );
          _startPolling();
        case LoginMethod.sms:
          break;
      }
    } on KugouApiException catch (error) {
      state = AuthState(
        method: method,
        phase: AuthPhase.error,
        message: error.message,
        countdown: countdown,
      );
    } on Object catch (error) {
      state = AuthState(
        method: method,
        phase: AuthPhase.error,
        message: '二维码生成失败：$error',
        countdown: countdown,
      );
    }
  }

  // ------------------------------------------------------------ 手机登录

  /// 发送短信验证码，成功后开始 60 秒重发倒计时。
  Future<void> sendSmsCode(String mobile) async {
    final String? invalid = AuthValidators.mobileError(mobile);
    if (invalid != null) {
      state = state.copyWith(phase: AuthPhase.error, message: invalid);
      return;
    }
    state = state.copyWith(phase: AuthPhase.loading, message: '正在发送验证码…');
    try {
      await ref.read(kugouLoginApiProvider).sendSmsCode(mobile.trim());
      _startCountdown(60);
      state = state.copyWith(phase: AuthPhase.idle, message: '验证码已发送，请查收短信');
    } on KugouApiException catch (error) {
      state = state.copyWith(phase: AuthPhase.error, message: error.message);
    } on Object catch (error) {
      state = state.copyWith(phase: AuthPhase.error, message: '验证码发送失败：$error');
    }
  }

  /// 手机号 + 验证码登录。
  Future<void> loginWithSms({
    required String mobile,
    required String code,
  }) async {
    final String? invalid =
        AuthValidators.mobileError(mobile) ?? AuthValidators.codeError(code);
    if (invalid != null) {
      state = state.copyWith(phase: AuthPhase.error, message: invalid);
      return;
    }
    _stopPolling();
    state = state.copyWith(phase: AuthPhase.loading, message: '正在登录…');
    try {
      final LoginCredential credential = await ref
          .read(kugouLoginApiProvider)
          .loginBySms(mobile: mobile.trim(), code: code.trim());
      await _completeLogin(credential);
    } on KugouApiException catch (error) {
      state = state.copyWith(phase: AuthPhase.error, message: error.message);
    } on Object catch (error) {
      state = state.copyWith(phase: AuthPhase.error, message: '登录失败：$error');
    }
  }

  // ------------------------------------------------------------ 轮询

  void _startPolling() {
    _pollTimer?.cancel();
    _pollFailures = 0;
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (Timer timer) => _poll(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollBusy = false;
    _pollFailures = 0;
  }

  Future<void> _poll() async {
    if (_pollBusy || !state.isScanning) {
      return;
    }
    _pollBusy = true;
    try {
      switch (state.method) {
        case LoginMethod.kugouQr:
          await _pollKugou();
        case LoginMethod.wechat:
          await _pollWechat();
        case LoginMethod.qq:
          await _pollQq();
        case LoginMethod.sms:
          break;
      }
    } finally {
      _pollBusy = false;
    }
  }

  Future<void> _pollKugou() async {
    final String key = _kugouKey ?? '';
    if (key.isEmpty) {
      return;
    }
    QrLoginCheck check;
    try {
      check = await ref.read(kugouLoginApiProvider).check(key);
    } on Object catch (error) {
      _onPollFailure('酷狗扫码状态轮询失败', error);
      return;
    }
    if (!state.isScanning || state.method != LoginMethod.kugouQr) {
      return;
    }
    _pollFailures = 0;

    switch (check.status) {
      case QrLoginStatus.expired:
        _stopPolling();
        state = state.copyWith(
          phase: AuthPhase.expired,
          message: '二维码已过期，请点击刷新',
        );
      case QrLoginStatus.scanned:
        state = state.copyWith(
          phase: AuthPhase.scanned,
          message: '已扫码，请在手机上确认登录',
        );
      case QrLoginStatus.confirmed:
        _stopPolling();
        await _completeLogin(
          LoginCredential(
            token: check.token,
            userid: check.userid,
            nickname: check.nickname,
          ),
        );
      case QrLoginStatus.waiting:
      case QrLoginStatus.unknown:
        break;
    }
  }

  Future<void> _pollWechat() async {
    final WechatQrSession? session = _wechat;
    if (session == null) {
      return;
    }
    WechatCheckResult result;
    try {
      result = await ref.read(kugouLoginApiProvider).checkWechat(session.uuid);
    } on Object catch (error) {
      _onPollFailure('微信扫码状态轮询失败', error);
      return;
    }
    if (state.method != LoginMethod.wechat) {
      return;
    }
    _pollFailures = 0;

    switch (result.status) {
      case WechatScanStatus.waiting:
      case WechatScanStatus.unknown:
        break;
      case WechatScanStatus.scanned:
        state = state.copyWith(
          phase: AuthPhase.scanned,
          message: '已扫码，请在微信中点击确认',
        );
      case WechatScanStatus.refused:
        _stopPolling();
        state = state.copyWith(
          phase: AuthPhase.expired,
          message: '已取消授权，请刷新二维码重试',
        );
      case WechatScanStatus.expired:
        _stopPolling();
        state = state.copyWith(
          phase: AuthPhase.expired,
          message: '二维码已失效，请点击刷新',
        );
      case WechatScanStatus.confirmed:
        _stopPolling();
        if (result.code.isEmpty) {
          state = state.copyWith(
            phase: AuthPhase.error,
            message: '微信未返回授权码，请刷新二维码重试',
          );
          return;
        }
        state = state.copyWith(
          phase: AuthPhase.loading,
          message: '已确认，正在获取登录态…',
        );
        try {
          final LoginCredential credential = await ref
              .read(kugouLoginApiProvider)
              .loginByWechatCode(result.code);
          await _completeLogin(credential);
        } on KugouApiException catch (error) {
          state = state.copyWith(
            phase: AuthPhase.error,
            message: error.message,
          );
        } on Object catch (error) {
          state = state.copyWith(
            phase: AuthPhase.error,
            message: '登录失败：$error',
          );
        }
    }
  }

  Future<void> _pollQq() async {
    final QqQrSession? session = _qq;
    if (session == null) {
      return;
    }
    QqCheckResult result;
    try {
      result = await ref.read(kugouLoginApiProvider).checkQqQr(session);
    } on Object catch (error) {
      _onPollFailure('QQ 扫码状态轮询失败', error);
      return;
    }
    if (state.method != LoginMethod.qq) {
      return;
    }
    _pollFailures = 0;

    switch (result.status) {
      case QqScanStatus.waiting:
      case QqScanStatus.unknown:
        break;
      case QqScanStatus.scanned:
        state = state.copyWith(
          phase: AuthPhase.scanned,
          message: '已扫码，请在手机上确认登录',
        );
      case QqScanStatus.expired:
        _stopPolling();
        state = state.copyWith(
          phase: AuthPhase.expired,
          message: '二维码已失效，请点击刷新',
        );
      case QqScanStatus.confirmed:
        _stopPolling();
        final LoginCredential? credential = result.credential;
        if (credential == null) {
          state = state.copyWith(
            phase: AuthPhase.error,
            message: result.message.isEmpty ? 'QQ 登录失败，请重试' : result.message,
          );
          return;
        }
        await _completeLogin(credential);
    }
  }

  /// 轮询连续失败 3 次才终止：偶发网络抖动不该直接打断用户。
  void _onPollFailure(String label, Object error) {
    _pollFailures++;
    debugPrint('$label（第 $_pollFailures 次）: $error');
    if (_pollFailures < 3) {
      return;
    }
    _stopPolling();
    state = state.copyWith(
      phase: AuthPhase.error,
      message: error is KugouApiException ? error.message : '$label，请稍后重试',
    );
  }

  // ------------------------------------------------------------ 结束 / 退出

  /// 离开页面或放弃登录：清空状态并停掉所有计时器。
  void cancel() {
    _stopPolling();
    _stopCountdown();
    _kugouKey = null;
    _wechat = null;
    _qq = null;
    state = const AuthState();
  }

  /// 退出登录：清本地 cookie 并回到游客态。
  Future<void> logout() async {
    cancel();
    await ref.read(kugouSessionProvider.notifier).signOut();
    state = const AuthState();
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    state = state.copyWith(countdown: seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      final int next = state.countdown - 1;
      if (next <= 0) {
        timer.cancel();
        _countdownTimer = null;
        state = state.copyWith(countdown: 0);
        return;
      }
      state = state.copyWith(countdown: next);
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  /// 登录成功：写本地登录态并结束状态机。
  Future<void> _completeLogin(LoginCredential credential) async {
    if (!credential.isValid) {
      state = state.copyWith(
        phase: AuthPhase.error,
        message: '登录失败：服务端未返回有效凭证',
      );
      return;
    }
    final KugouSession current = ref.read(kugouSessionProvider);
    final String cookie = <String>[
      if (current.dfid.isNotEmpty) 'dfid=${current.dfid}',
      'userid=${credential.userid}',
      'token=${credential.token}',
      if (credential.vipType.isNotEmpty && credential.vipType != '0')
        'vip_type=${credential.vipType}',
      if (credential.vipToken.isNotEmpty) 'vip_token=${credential.vipToken}',
    ].join('; ');

    final KugouSession logged = current.copyWith(
      cookie: cookie,
      userid: credential.userid,
      token: credential.token,
      nickname: credential.nickname.isEmpty
          ? current.nickname
          : credential.nickname,
    );
    await ref.read(kugouSessionProvider.notifier).signIn(logged);
    _stopCountdown();
    state = AuthState(
      method: state.method,
      phase: AuthPhase.success,
      message: '登录成功',
      nickname: logged.nickname,
    );

    // 登录成功即触发一次「每日领 VIP」：概念版听歌任务一天一领，
    // 内部做了日期幂等，重复调用不会重复请求接口。
    unawaited(ref.read(dailyVipControllerProvider.notifier).claimIfNeeded());
  }
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
