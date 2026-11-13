import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/kugou_providers.dart';
import '../../../../core/network/kugou_session.dart';
import '../../../../routing/app_routes.dart';
import '../../../../routing/navigation_history.dart';
import '../../../../shared/widgets/cover_image.dart';
import '../../../../theme/app_spacing.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../search/application/search_controller.dart';
import '../../../../theme/app_palette.dart';

/// 顶部栏：返回 + 全局搜索框 + 右侧快捷操作。
/// 搜索框回车即跳转搜索页并触发检索（真实接口接入点见 search_controller 的 TODO）。
class TopSearchBar extends ConsumerStatefulWidget {
  const TopSearchBar({super.key});

  @override
  ConsumerState<TopSearchBar> createState() => _TopSearchBarState();
}

class _TopSearchBarState extends ConsumerState<TopSearchBar> {
  late final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final String keyword = value.trim();
    if (keyword.isEmpty) {
      return;
    }
    ref.read(searchPageControllerProvider.notifier).search(keyword);
    _focusNode.unfocus();
    context.go('${AppRoutes.search}?q=${Uri.encodeQueryComponent(keyword)}');
  }

  @override
  Widget build(BuildContext context) {
    // 前进 / 后退改走自建历史栈：go_router 的 go 不入栈，canPop 在 Shell 内基本恒为 false。
    final NavigationHistoryState history = ref.watch(navigationHistoryProvider);
    final bool canGoBack = history.canGoBack;
    final bool canGoForward = history.canGoForward;
    final NavigationHistoryController historyController = ref.read(
      navigationHistoryProvider.notifier,
    );

    return Container(
      height: AppSpacing.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.background,
        border: Border(bottom: BorderSide(color: context.palette.divider)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: canGoBack ? '后退（Alt+←）' : '没有可后退的页面',
            onPressed: canGoBack ? historyController.goBack : null,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            color: canGoBack
                ? context.palette.textSecondary
                : context.palette.textDisabled,
          ),
          IconButton(
            tooltip: canGoForward ? '前进（Alt+→）' : '没有可前进的页面',
            onPressed: canGoForward ? historyController.goForward : null,
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            color: canGoForward
                ? context.palette.textSecondary
                : context.palette.textDisabled,
          ),
          const SizedBox(width: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                onTap: () {
                  if (_controller.text.isEmpty) {
                    context.go(AppRoutes.search);
                  }
                },
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索歌曲、歌手、歌单',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  prefixIconColor: context.palette.textSecondary,
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () => setState(_controller.clear),
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          _ActionIcon(
            tooltip: '设置',
            icon: Icons.tune_rounded,
            onPressed: () => context.go(AppRoutes.settings),
          ),
          const SizedBox(width: AppSpacing.sm),
          const _AccountAvatar(),
        ],
      ),
    );
  }
}

/// 右上角账号头像：登录后显示酷狗真实头像，未登录退化为占位人像。
///
/// 点击统一 `go(AppRoutes.profile)`：已登录进个人信息页，未登录该页会给出登录入口，
/// 因此不需要在这里再分流一次登录页。
class _AccountAvatar extends ConsumerWidget {
  const _AccountAvatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KugouSession session = ref.watch(kugouSessionProvider);
    final UserProfile? profile = ref.watch(userProfileProvider).value;

    final bool loggedIn = session.isLoggedIn;
    final String nickname = profile?.nickname.isNotEmpty == true
        ? profile!.nickname
        : session.nickname;
    final String avatarUrl = profile?.avatarUrl ?? '';

    return Tooltip(
      message: loggedIn
          ? (nickname.isEmpty ? '个人信息' : '$nickname · 个人信息')
          : '未登录 · 前往个人信息页登录',
      child: InkWell(
        onTap: () => context.go(AppRoutes.profile),
        customBorder: const CircleBorder(),
        child: avatarUrl.isNotEmpty
            ? CoverImage(
                seed: nickname.isEmpty
                    ? (session.userid.isEmpty ? 'TX' : session.userid)
                    : nickname,
                url: avatarUrl,
                size: 30,
                circle: true,
                icon: Icons.person_rounded,
              )
            : Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: context.palette.surfaceHigh,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  loggedIn
                      ? Icons.person_rounded
                      : Icons.person_outline_rounded,
                  size: 18,
                  color: context.palette.textSecondary,
                ),
              ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      color: context.palette.textSecondary,
    );
  }
}
