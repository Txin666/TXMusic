import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/kugou_providers.dart';
import '../../../core/network/kugou_session.dart';
import '../../../core/utils/formatters.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/cover_image.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_spacing.dart';
import '../application/profile_providers.dart';
import '../domain/user_profile.dart';

/// 个人信息页（路由 `/profile`）。
///
/// 这是一个**独立页面**，而不是设置页里的一个分区：头像、昵称、乐龄、累计听歌
/// 时长、听歌等级、粉丝关注等资料都来自酷狗账号实时接口（见 [KugouUserApi]），
/// 登录 / 退出登录入口也从设置页迁移到这里，设置页只保留外观、播放等本地选项。
///
/// 未登录时页面不请求任何接口（避免 502 噪音），直接展示游客态与登录引导。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final KugouSession session = ref.watch(kugouSessionProvider);
    final AsyncValue<UserProfile?> profileState = ref.watch(
      userProfileProvider,
    );
    final UserProfile profile = profileState.value ?? UserProfile.empty;
    final bool loggedIn = session.isLoggedIn;
    final bool refreshing = profileState.isLoading;

    return PageContainer(
      maxWidth: 1080,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('个人信息', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '头像、乐龄、听歌时长与登录信息，均取自已登录的酷狗账号',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新资料',
                onPressed: loggedIn && !refreshing
                    ? () => ref.invalidate(userProfileProvider)
                    : null,
                icon: refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (profileState.hasError)
            _NoticeBar(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              text: '资料接口请求失败：${profileState.error}',
            ),
          _ProfileHeader(
            profile: profile,
            session: session,
            loading: refreshing,
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: '音乐数据',
            subtitle: profile.hasData ? '来自酷狗账号实时统计' : '登录后可查看真实数据',
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: <Widget>[
              _StatTile(
                icon: Icons.cake_outlined,
                label: '乐龄',
                value: _ageText(profile),
                hint: profile.registeredAt == null
                    ? '注册时间未知'
                    : '注册于 ${Formatters.date(profile.registeredAt!)}',
              ),
              _StatTile(
                icon: Icons.timer_outlined,
                label: '累计听歌时长',
                value: _listenText(profile),
                hint: profile.weekListenCount > 0
                    ? '本周听歌 ${profile.weekListenCount} 次'
                    : '本周暂无听歌记录',
              ),
              _StatTile(
                icon: Icons.military_tech_outlined,
                label: '听歌等级',
                value: profile.grade > 0 ? 'Lv.${profile.grade}' : '未定级',
                hint: profile.nextGradePoint > 0
                    ? '成长值 ${profile.gradePoint}/${profile.nextGradePoint}'
                    : '成长值 ${profile.gradePoint}',
              ),
              _StatTile(
                icon: Icons.repeat_rounded,
                label: '累计听歌次数',
                value: profile.totalListenCount > 0
                    ? Formatters.playCount(profile.totalListenCount)
                    : '暂无记录',
                hint: '每日推荐 / 歌单播放均计入',
              ),
              _StatTile(
                icon: Icons.favorite_border_rounded,
                label: '粉丝',
                value: Formatters.playCount(profile.fans),
                hint: '关注 ${Formatters.playCount(profile.follows)} 人',
              ),
              _StatTile(
                icon: Icons.group_outlined,
                label: '好友',
                value: Formatters.playCount(profile.friends),
                hint: '主页访客 ${Formatters.playCount(profile.visitors)}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _Panel(
            title: '听歌等级成长',
            children: <Widget>[
              if (profile.nextGradePoint > 0) ...<Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'Lv.${profile.grade}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: context.palette.emphasized,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: profile.gradeProgress,
                          minHeight: 6,
                          backgroundColor: context.palette.surfaceHigh,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Lv.${profile.grade + 1}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '还差 ${profile.gradeGap} 成长值升到 Lv.${profile.grade + 1}'
                  '（资料完整度 ${profile.finishPercent}%）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ] else
                Text(
                  '暂无等级数据：登录后听歌一段时间即可累计成长值',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _Panel(
            title: '账号与登录',
            action: loggedIn
                ? OutlinedButton(
                    onPressed: () => _signOut(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: const Text('退出登录'),
                  )
                : FilledButton(
                    onPressed: () => context.go(AppRoutes.login),
                    child: const Text('去登录'),
                  ),
            children: <Widget>[
              _InfoRow(
                label: '登录状态',
                value: loggedIn ? '已登录（全曲 / 高音质可用）' : '游客模式（60 秒试听）',
                highlight: loggedIn,
              ),
              _InfoRow(label: '昵称', value: profile.nickname),
              _InfoRow(label: '酷狗 ID', value: profile.userid),
              _InfoRow(label: '账号名', value: profile.username),
              _InfoRow(
                label: '注册时间',
                value: profile.registeredAt == null
                    ? ''
                    : '${Formatters.date(profile.registeredAt!)}'
                          '（乐龄 ${profile.listenAgeDays} 天）',
              ),
              _InfoRow(label: '绑定手机', value: _maskMobile(profile.loginMobile)),
              _InfoRow(
                label: '第三方账号',
                value: profile.bindings.isEmpty
                    ? ''
                    : profile.bindings.join('、'),
              ),
              _InfoRow(
                label: '会员状态',
                value: profile.isVip
                    ? (profile.vipSummary.isEmpty
                          ? 'VIP 生效中'
                          : 'VIP · ${profile.vipSummary}')
                    : '未开通 VIP',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
 
        ],
      ),
    );
  }

  /// 退出登录：先弹二次确认，避免误触直接把本地登录凭证清掉。
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
        title: const Text('确定要退出登录吗？'),
        content: const Text(
          '退出后会清除本地登录凭证，'
          '重新登录需要再次扫码或账号验证。',
        ),
        actions: <Widget>[
          OverflowBar(
            alignment: MainAxisAlignment.center,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                child: const Text('退出登录'),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await ref.read(kugouSessionProvider.notifier).signOut();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已退出登录，当前为游客模式')));
  }

  /// 乐龄文案：注册天数为 0（今天注册）时也给明确反馈。
  static String _ageText(UserProfile profile) {
    if (profile.registeredAt == null) {
      return '未知';
    }
    final int days = profile.listenAgeDays;
    if (days <= 0) {
      return '今天注册';
    }
    if (days >= 365) {
      final int years = days ~/ 365;
      final int rest = days % 365;
      return rest == 0 ? '$years 年' : '$years 年 $rest 天';
    }
    return '$days 天';
  }

  /// 累计听歌时长文案（接口给的是秒）。
  static String _listenText(UserProfile profile) {
    if (!profile.hasListenDuration) {
      return '暂无记录';
    }
    final Duration d = profile.listenDuration;
    final int hours = d.inHours;
    final int minutes = d.inMinutes % 60;
    if (hours >= 100) {
      return '$hours 小时';
    }
    if (hours > 0) {
      return minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
    }
    if (minutes > 0) {
      return '$minutes 分钟';
    }
    return '${d.inSeconds} 秒';
  }

  /// 手机号脱敏：保留前 3 后 4。
  static String _maskMobile(String raw) {
    final String digits = raw.replaceAll(RegExp('[^0-9]'), '');
    if (digits.length < 7) {
      return raw;
    }
    return '${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
  }
}

/// 页面头部：头像 + 昵称 + 等级 / VIP 徽章 + 地区、性别、乐龄等元信息。
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.session,
    required this.loading,
  });

  final UserProfile profile;
  final KugouSession session;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool loggedIn = session.isLoggedIn;
    final String nickname = profile.nickname.isNotEmpty
        ? profile.nickname
        : (loggedIn ? '酷狗用户' : '未登录');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CoverImage(
            seed: nickname,
            url: profile.avatarUrl.isEmpty ? null : profile.avatarUrl,
            size: 96,
            circle: true,
            icon: Icons.person_rounded,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(nickname, style: theme.textTheme.headlineSmall),
                    if (profile.grade > 0)
                      _Badge(
                        text: 'Lv.${profile.grade}',
                        color: AppColors.primary,
                      ),
                    if (profile.isVip)
                      _Badge(text: 'VIP', color: AppColors.accent),
                    if (!loggedIn)
                      _Badge(text: '游客', color: context.palette.textSecondary),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  profile.signature.isNotEmpty
                      ? profile.signature
                      : (loggedIn ? '还没有设置个性签名' : '登录后可查看头像、乐龄与听歌数据'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    if (profile.region.isNotEmpty)
                      _MetaItem(
                        icon: Icons.location_on_outlined,
                        text: profile.region,
                      ),
                    if (loggedIn)
                      _MetaItem(
                        icon: Icons.wc_rounded,
                        text: profile.genderLabel,
                      ),
                    if (profile.registeredAt != null)
                      _MetaItem(
                        icon: Icons.event_outlined,
                        text: '加入于 ${Formatters.date(profile.registeredAt!)}',
                      ),
                    if (profile.userid.isNotEmpty)
                      _MetaItem(
                        icon: Icons.badge_outlined,
                        text: 'ID ${profile.userid}',
                      ),
                    if (loading)
                      _MetaItem(
                        icon: Icons.hourglass_bottom_rounded,
                        text: '资料加载中…',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: context.palette.textDisabled),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.palette.textSecondary),
        ),
      ],
    );
  }
}

/// 统计小卡：一个指标 + 一句上下文提示。
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? normalized = value.trim().isEmpty ? null : value;

    return Container(
      width: 196,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: context.palette.emphasized),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            normalized ?? '—',
            style: theme.textTheme.titleMedium?.copyWith(
              color: normalized == null
                  ? context.palette.textDisabled
                  : context.palette.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hint != null && hint!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.palette.textDisabled,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// 通用面板容器：标题 + 内容，右侧可挂一个操作按钮。
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children, this.action});

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: context.palette.emphasized,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

/// 一行「标签 — 值」信息；值为空时显示 `未设置 / 未回传`，不臆造数据。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool empty = value.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SelectableText(
              empty ? '未设置 / 未回传' : value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: empty
                    ? context.palette.textDisabled
                    : (highlight
                          ? context.palette.emphasized
                          : context.palette.textPrimary),
                fontWeight: highlight ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
