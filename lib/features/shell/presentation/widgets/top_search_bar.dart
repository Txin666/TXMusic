import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/app_routes.dart';
import '../../../../theme/app_spacing.dart';
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
    context.go(AppRoutes.search);
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = context.canPop();

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
            tooltip: canPop ? '返回' : '已在首页',
            onPressed: canPop ? () => context.pop() : null,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            color: context.palette.textSecondary,
          ),
          IconButton(
            tooltip: '前进（骨架期未实现）',
            onPressed: null,
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            color: context.palette.textDisabled,
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
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: context.palette.surfaceHigh,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              'TX',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.palette.textSecondary,
              ),
            ),
          ),
        ],
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
