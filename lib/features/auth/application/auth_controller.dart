import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../../core/network/kugou_session.dart';
import '../data/kugou_login_api.dart';

/// 扫码登录阶段。
enum AuthPhase { idle, loading, waiting, scanned, success, expired, error }

@immutable
class AuthState {
  const AuthState({
    this.phase = AuthPhase.idle,
    this.qr,
    this.message = '',
    this.nickname = '',
  });

  final AuthPhase phase;
  final LoginQr? qr;
  final String message;
  final String nickname;

  bool get isBusy => phase == AuthPhase.loading;

  bool get isWaiting => phase == AuthPhase.waiting || phase == AuthPhase.scanned;

  AuthState copyWith({
    AuthPhase? phase,
    LoginQr? qr,
    String? message,
    String? nickname,
    bool clearQr = false,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      qr: clearQr ? null : (qr ?? this.qr),
      message: message ?? this.message,
      nickname: nickname ?? this.nickname,
    );
  }
}

/// 扫码登录编排：生成二维码 → 轮询状态 → 成功后写入本地登录态。
///
/// 全程由用户自己在界面上扫码、在手机上确认，助手不介入。
class AuthController extends Notifier<AuthState> {
  Timer? _timer;

  @override
  AuthState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return const AuthState();
  }

  /// 生成 / 刷新二维码并开始轮询。
  Future<void> startQrLogin() async {
    _cancelTimer();
    state = const AuthState(phase: AuthPhase.loading, message: '正在生成二维码…');
    try {
      final LoginQr qr = await ref.read(kugouLoginApiProvider).createQr();
      state = AuthState(
        phase: AuthPhase.waiting,
        qr: qr,
        message: '请用酷狗 App 扫码登录',
      );
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (Timer timer) => _poll(qr.key),
      );
    } on KugouApiException catch (error) {
      state = AuthState(phase: AuthPhase.error, message: error.message);
    } on Object catch (error) {
      state = AuthState(phase: AuthPhase.error, message: '二维码生成失败：$error');
    }
  }

  void cancel() {
    _cancelTimer();
    state = const AuthState();
  }

  /// 退出登录：清本地 cookie 并回到游客态。
  Future<void> logout() async {
    _cancelTimer();
    await ref.read(kugouSessionProvider.notifier).signOut();
    state = const AuthState();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll(String key) async {
    if (!state.isWaiting) {
      return;
    }
    QrLoginCheck check;
    try {
      check = await ref.read(kugouLoginApiProvider).check(key);
    } on Object catch (error) {
      debugPrint('扫码状态轮询失败: $error');
      return;
    }

    if (!state.isWaiting) {
      return;
    }

    switch (check.status) {
      case QrLoginStatus.expired:
        _cancelTimer();
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
        _cancelTimer();
        await _completeLogin(check);
      case QrLoginStatus.waiting:
      case QrLoginStatus.unknown:
        break;
    }
  }

  Future<void> _completeLogin(QrLoginCheck check) async {
    if (check.token.isEmpty || check.userid.isEmpty) {
      state = state.copyWith(
        phase: AuthPhase.error,
        message: '登录失败：服务端未返回 token',
      );
      return;
    }
    final KugouSession current = ref.read(kugouSessionProvider);
    final KugouSession logged = current.copyWith(
      cookie: <String>[
        if (current.dfid.isNotEmpty) 'dfid=${current.dfid}',
        'userid=${check.userid}',
        'token=${check.token}',
      ].join('; '),
      userid: check.userid,
      token: check.token,
      nickname: check.nickname.isEmpty ? current.nickname : check.nickname,
    );
    await ref.read(kugouSessionProvider.notifier).signIn(logged);
    state = AuthState(
      phase: AuthPhase.success,
      message: '登录成功',
      nickname: logged.nickname,
    );
  }
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
