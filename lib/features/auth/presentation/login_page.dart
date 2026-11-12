import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_providers.dart';
import '../../../core/network/kugou_session.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_spacing.dart';
import '../application/auth_controller.dart';
import '../data/kugou_login_api.dart';

/// 登录方式在 UI 上的展示顺序：手机优先，酷狗扫码垫底（原有方式）。
const List<LoginMethod> _methodOrder = <LoginMethod>[
  LoginMethod.sms,
  LoginMethod.wechat,
  LoginMethod.qq,
  LoginMethod.kugouQr,
];

extension _LoginMethodUi on LoginMethod {
  String get label => switch (this) {
        LoginMethod.sms => '手机登录',
        LoginMethod.wechat => '微信扫码',
        LoginMethod.qq => 'QQ 扫码',
        LoginMethod.kugouQr => '酷狗扫码',
      };

  IconData get icon => switch (this) {
        LoginMethod.sms => Icons.smartphone_rounded,
        LoginMethod.wechat => Icons.chat_bubble_rounded,
        LoginMethod.qq => Icons.forum_rounded,
        LoginMethod.kugouQr => Icons.qr_code_2_rounded,
      };

  String get scanHint => switch (this) {
        LoginMethod.sms => '',
        LoginMethod.wechat => '打开微信 → 扫一扫，确认授权后自动登录',
        LoginMethod.qq => '打开手机 QQ → 扫一扫，确认后自动登录',
        LoginMethod.kugouQr => '打开手机酷狗 App → 扫一扫，确认后自动登录',
      };
}

/// 账号登录页（路由 `/login`）：手机验证码 / 微信扫码 / QQ 扫码 / 酷狗扫码。
///
/// 四种方式全部由用户本人在软件内操作完成 —— 助手不代收验证码、
/// 不代扫二维码、不接触账号密码。登录成功后由 [AuthController] 把
/// token / userid 写入本机 `.local/kugou_cookie.json`。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _mobile = TextEditingController();
  final TextEditingController _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 首帧后再触发，避免在 build 期间修改 Provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!ref.read(kugouSessionProvider).isLoggedIn) {
        ref.read(authControllerProvider.notifier).ensureStarted();
      }
    });
  }

  @override
  void dispose() {
    _mobile.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final KugouSession session = ref.watch(kugouSessionProvider);

    // 登录成功：提示后退回设置页（登录态已由 AuthController 落盘）。
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
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (!context.mounted) {
            return;
          }
          _leave(context, reset: false);
        });
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
                        : _buildLoginEntry(context, theme, auth),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 已登录

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

  // ------------------------------------------------------------ 未登录

  Widget _buildLoginEntry(
    BuildContext context,
    ThemeData theme,
    AuthState auth,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.md),
        Text(
          '登录',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '选择一种登录方式，全程在本机完成，账号密码不经过本软件',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final LoginMethod method in _methodOrder)
              ChoiceChip(
                selected: auth.method == method,
                onSelected: (bool selected) {
                  if (!selected) {
                    return;
                  }
                  ref.read(authControllerProvider.notifier).selectMethod(method);
                },
                avatar: Icon(
                  method.icon,
                  size: 16,
                  color: auth.method == method
                      ? AppColors.primary
                      : context.palette.textSecondary,
                ),
                label: Text(method.label),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (auth.method == LoginMethod.sms)
          _buildSmsForm(context, theme, auth)
        else
          _buildQrPane(context, theme, auth),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '未登录仍可浏览与 60 秒试听；登录态只保存在本地，可随时退出。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textDisabled),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: () => _leave(context),
            child: const Text('稍后再说'),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 扫码面板

  Widget _buildQrPane(
    BuildContext context,
    ThemeData theme,
    AuthState auth,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          auth.method.scanHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Container(
            width: 264,
            height: 264,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.palette.divider),
            ),
            alignment: Alignment.center,
            child: _buildQrBody(context, auth),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _statusLabel(auth),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: _statusColor(context, auth)),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: FilledButton.icon(
            onPressed: auth.isBusy
                ? null
                : () => ref.read(authControllerProvider.notifier).refreshQr(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(auth.hasQr ? '刷新二维码' : '生成二维码'),
          ),
        ),
      ],
    );
  }

  Widget _buildQrBody(BuildContext context, AuthState auth) {
    if (!auth.hasQr) {
      if (auth.isBusy) {
        return const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      }
      return Icon(
        Icons.qr_code_2_rounded,
        size: 72,
        color: context.palette.textDisabled,
      );
    }

    final Uint8List? bytes = _decode(auth.qrImage);
    if (bytes == null) {
      return Icon(
        Icons.broken_image_rounded,
        size: 64,
        color: context.palette.textDisabled,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.memory(
        bytes,
        width: 232,
        height: 232,
        gaplessPlayback: true,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
          return Icon(
            Icons.qr_code_2_rounded,
            size: 72,
            color: context.palette.textDisabled,
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ 手机登录

  Widget _buildSmsForm(
    BuildContext context,
    ThemeData theme,
    AuthState auth,
  ) {
    final bool canSend = !auth.isBusy && auth.countdown == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: const InputDecoration(
            labelText: '手机号',
            hintText: '请输入 11 位手机号',
            prefixIcon: Icon(Icons.smartphone_rounded),
            counterText: '',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onSubmitted: (String _) => _submitSms(auth),
                decoration: const InputDecoration(
                  labelText: '短信验证码',
                  hintText: '手机收到的验证码',
                  prefixIcon: Icon(Icons.password_rounded),
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: canSend
                    ? () => ref
                        .read(authControllerProvider.notifier)
                        .sendSmsCode(_mobile.text)
                    : null,
                child: Text(
                  auth.countdown > 0 ? '${auth.countdown}s 后重发' : '发送验证码',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: auth.isBusy ? null : () => _submitSms(auth),
          child: auth.isBusy && auth.method == LoginMethod.sms
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _statusLabel(auth),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: _statusColor(context, auth)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '验证码由酷狗官方短信下发，本软件不做任何代收或转发。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.textDisabled),
        ),
      ],
    );
  }

  void _submitSms(AuthState auth) {
    ref.read(authControllerProvider.notifier).loginWithSms(
          mobile: _mobile.text,
          code: _code.text,
        );
  }

  // ------------------------------------------------------------ 公共

  Uint8List? _decode(String base64Text) {
    if (base64Text.isEmpty) {
      return null;
    }
    final int index = base64Text.indexOf('base64,');
    final String raw =
        index >= 0 ? base64Text.substring(index + 7) : base64Text;
    try {
      return base64Decode(raw);
    } on FormatException {
      return null;
    }
  }

  Color _statusColor(BuildContext context, AuthState auth) {
    switch (auth.phase) {
      case AuthPhase.error:
        return AppColors.danger;
      case AuthPhase.expired:
        return AppColors.vip;
      case AuthPhase.scanned:
      case AuthPhase.loading:
        return AppColors.primary;
      case AuthPhase.idle:
      case AuthPhase.waiting:
      case AuthPhase.success:
        return context.palette.textSecondary;
    }
  }

  String _statusLabel(AuthState auth) {
    if (auth.message.isNotEmpty) {
      return auth.message;
    }
    switch (auth.phase) {
      case AuthPhase.idle:
        return auth.method == LoginMethod.sms ? '输入手机号后获取验证码' : '点击下方按钮生成二维码';
      case AuthPhase.loading:
        return '处理中…';
      case AuthPhase.waiting:
        return '等待扫码…';
      case AuthPhase.scanned:
        return '已扫码，请在手机上确认登录';
      case AuthPhase.success:
        return '登录成功';
      case AuthPhase.expired:
        return '二维码已过期，请点击刷新';
      case AuthPhase.error:
        return '登录失败，请重试';
    }
  }

  /// 离开页面：停掉轮询与倒计时，回到设置页。
  ///
  /// [reset] 为 false 用于登录成功后返回，此时保留成功状态避免重复出码。
  void _leave(BuildContext context, {bool reset = true}) {
    if (reset) {
      ref.read(authControllerProvider.notifier).cancel();
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.settings);
    }
  }
}
