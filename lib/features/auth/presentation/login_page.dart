import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_providers.dart';
import '../../../core/network/kugou_session.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../application/auth_controller.dart';
import '../data/kugou_login_api.dart';
import '../../../theme/app_palette.dart';

/// 应用内自助扫码登录页（路由 `/login`）。
///
/// 全流程在软件内完成：进入页面自动调 `/login/qr/key` + `/login/qr/create`
/// 生成二维码 → 每 2 秒轮询 `/login/qr/check` → 用户在手机酷狗 App 上
/// 扫码并确认 → 成功后写入本地登录态（`.local/kugou_cookie.json`）。
/// 助手不代替用户扫码，也不接触任何账号密码。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  @override
  void initState() {
    super.initState();
    // 首帧后再触发，避免在 build 期间修改 Provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final bool loggedIn = ref.read(kugouSessionProvider).isLoggedIn;
      final AuthState auth = ref.read(authControllerProvider);
      if (!loggedIn && auth.qr == null && !auth.isWaiting && !auth.isBusy) {
        ref.read(authControllerProvider.notifier).startQrLogin();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final KugouSession session = ref.watch(kugouSessionProvider);

    // 登录成功：提示并退回设置页（登录态已由 AuthController 落盘）。
    ref.listen<AuthState>(authControllerProvider,
        (AuthState? previous, AuthState next) {
      if (next.phase == AuthPhase.success &&
          previous?.phase != AuthPhase.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next.nickname.isEmpty ? '登录成功' : '登录成功：${next.nickname}',
            ),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => _leave(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('酷狗账号', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.page,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: session.isLoggedIn
                        ? _buildLoggedIn(context, theme, session)
                        : _buildQrLogin(context, theme, auth),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 已登录：展示昵称与退出登录。
  Widget _buildLoggedIn(
    BuildContext context,
    ThemeData theme,
    KugouSession session,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xl),
        const Icon(Icons.check_circle_rounded,
            size: 56, color: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        Text(
          session.nickname.isEmpty ? '已登录' : session.nickname,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          session.userid.isEmpty ? 'userid 未知' : 'userid ${session.userid}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '登录态仅保存在本机 .local/kugou_cookie.json，可解锁全曲与高音质。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textDisabled),
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(authControllerProvider.notifier).logout();
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已退出登录，当前为游客模式')),
            );
          },
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('退出登录'),
        ),
      ],
    );
  }

  /// 未登录：二维码 + 扫码状态。
  Widget _buildQrLogin(
    BuildContext context,
    ThemeData theme,
    AuthState auth,
  ) {
    final LoginQr? qr = auth.qr;
    final bool expired = auth.phase == AuthPhase.expired;
    final bool failed = auth.phase == AuthPhase.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const SizedBox(height: AppSpacing.md),
        Text('扫码登录', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '打开手机酷狗 App → 扫一扫，确认后自动登录',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          width: 264,
          height: 264,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.palette.divider),
          ),
          alignment: Alignment.center,
          child: _buildQrBody(theme, auth, qr),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _statusLabel(auth),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: failed
                ? AppColors.danger
                : expired
                    ? AppColors.vip
                    : context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            FilledButton.icon(
              onPressed: auth.isBusy
                  ? null
                  : () => ref.read(authControllerProvider.notifier).startQrLogin(),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: Text(qr == null ? '生成二维码' : '刷新二维码'),
            ),
            const SizedBox(width: AppSpacing.md),
            OutlinedButton(
              onPressed: () => _leave(context),
              child: const Text('稍后再说'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '二维码仅用于本机登录，登录态保存在本地；未登录时仍可浏览与 60 秒试听。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textDisabled),
        ),
      ],
    );
  }

  Widget _buildQrBody(ThemeData theme, AuthState auth, LoginQr? qr) {
    if (auth.isBusy) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (qr != null) {
      Uint8List? bytes;
      try {
        bytes = base64Decode(qr.rawBase64);
      } on FormatException {
        bytes = null;
      }
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.memory(
            bytes,
            width: 232,
            height: 232,
            gaplessPlayback: true,
            errorBuilder: (BuildContext context, Object error,
                StackTrace? stack) {
              return Icon(Icons.qr_code_2_rounded,
                  size: 72, color: context.palette.textDisabled);
            },
          ),
        );
      }
    }
    return Icon(
      Icons.qr_code_2_rounded,
      size: 72,
      color: context.palette.textDisabled,
    );
  }

  String _statusLabel(AuthState auth) {
    switch (auth.phase) {
      case AuthPhase.idle:
        return '点击下方按钮生成二维码';
      case AuthPhase.loading:
        return '正在生成二维码…';
      case AuthPhase.waiting:
        return '请用手机酷狗 App 扫码';
      case AuthPhase.scanned:
        return '已扫码，请在手机上确认登录';
      case AuthPhase.success:
        return auth.message.isEmpty ? '登录成功' : auth.message;
      case AuthPhase.expired:
        return '二维码已过期，请点击刷新';
      case AuthPhase.error:
        return auth.message.isEmpty ? '登录失败，请重试' : auth.message;
    }
  }

  /// 离开页面：停掉轮询，回到设置页。
  void _leave(BuildContext context) {
    ref.read(authControllerProvider.notifier).cancel();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.settings);
    }
  }
}
