import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/kugou_providers.dart';
import '../../../core/network/kugou_session.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../theme/app_spacing.dart';
import '../../vip/application/daily_vip_controller.dart';
import '../application/settings_controller.dart';
import '../../../theme/app_palette.dart';

/// 设置页（路由 `/settings`）：外观 / 播放 / 关于。
///
/// 账号、登录 / 退出登录等个人信息已迁出，统一放 `/profile`（见 ProfilePage）。
///
/// 骨架期所有开关仅作用于内存态；TODO(storage): 接入 Hive settings box（文档 §8）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsState settings = ref.watch(settingsControllerProvider);
    final SettingsController controller =
        ref.read(settingsControllerProvider.notifier);
    final KugouSession session = ref.watch(kugouSessionProvider);
    final DailyVipState vipState = ref.watch(dailyVipControllerProvider);
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      maxWidth: 880,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('设置', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '外观、播放等本地设置；账号与登录信息已迁至「个人信息」页',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          _SettingSection(
            title: '每日 VIP',
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('登录后自动领取'),
                subtitle: const Text(
                  '概念版听歌任务：每天首次启动或登录成功时自动领取 1 天 VIP',
                ),
                value: vipState.autoClaim,
                onChanged: (bool value) => ref
                    .read(dailyVipControllerProvider.notifier)
                    .setAutoClaim(value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  vipState.busy
                      ? '正在领取…'
                      : (vipState.lastMessage.isEmpty
                          ? '尚未领取'
                          : vipState.lastMessage),
                ),
                subtitle: Text(
                  <String>[
                    if (vipState.lastClaimDate.isNotEmpty)
                      '上次领取：${vipState.lastClaimDate}',
                    if (vipState.snapshot.isVip) vipState.snapshot.summary,
                  ].join(' · '),
                ),
                trailing: TextButton(
                  onPressed: (!session.isLoggedIn || vipState.busy)
                      ? null
                      : () async {
                          await ref
                              .read(dailyVipControllerProvider.notifier)
                              .claimNow();
                          if (!context.mounted) {
                            return;
                          }
                          final DailyVipState latest =
                              ref.read(dailyVipControllerProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(latest.lastMessage)),
                          );
                        },
                  child: const Text('立即领取'),
                ),
              ),
            ],
          ),
          _SettingSection(
            title: '外观',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('主题模式'),
                subtitle: const Text('深色为默认音乐播放器风格'),
                trailing: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                    ),
                  ],
                  selected: <ThemeMode>{settings.themeMode},
                  onSelectionChanged: (Set<ThemeMode> value) =>
                      controller.setThemeMode(value.first),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('播放条显示歌词'),
                subtitle: const Text('底部播放条右侧滚动当前歌词'),
                value: settings.showLyricOnBar,
                onChanged: controller.setShowLyricOnBar,
              ),
            ],
          ),
          _SettingSection(
            title: '播放',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('音质'),
                subtitle: Text(settings.audioQuality.label),
                trailing: DropdownButton<AudioQuality>(
                  value: settings.audioQuality,
                  underline: const SizedBox.shrink(),
                  items: AudioQuality.values
                      .map(
                        (AudioQuality quality) => DropdownMenuItem<AudioQuality>(
                          value: quality,
                          child: Text(quality.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (AudioQuality? quality) {
                    if (quality != null) {
                      controller.setAudioQuality(quality);
                    }
                  },
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动播放下一首'),
                subtitle: const Text('当前歌曲结束后按队列继续'),
                value: settings.autoPlayNext,
                onChanged: controller.setAutoPlayNext,
              ),
            ],
          ),
          _SettingSection(
            title: '关于',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppConstants.appName),
                subtitle: Text(
                  '版本 ${AppConstants.appVersion} · ${AppConstants.appSlogan}',
                ),
                trailing: TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('骨架期暂未接入检查更新')),
                  ),
                  child: const Text('检查更新'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingSection extends StatelessWidget {
  const _SettingSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.palette.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: context.palette.emphasized),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
