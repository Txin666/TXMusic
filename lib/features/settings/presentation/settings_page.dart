import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/page_container.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../application/settings_controller.dart';

/// 设置页（路由 `/settings`）：外观 / 播放 / 桌面歌词 / 关于。
///
/// 骨架期所有开关仅作用于内存态；TODO(storage): 接入 Hive settings box（文档 §8）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsState settings = ref.watch(settingsControllerProvider);
    final SettingsController controller =
        ref.read(settingsControllerProvider.notifier);
    final ThemeData theme = Theme.of(context);

    return PageContainer(
      maxWidth: 880,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('设置', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '骨架期设置仅内存生效，持久化在文档 §8 接入',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
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
            title: '桌面歌词',
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用桌面歌词'),
                subtitle: const Text('独立置顶悬浮窗，需 window_manager 多窗口支持'),
                value: settings.desktopLyricEnabled,
                onChanged: controller.setDesktopLyricEnabled,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('打开桌面歌词窗口'),
                subtitle: const Text('骨架期以全屏占位页演示布局'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => context.go(AppRoutes.desktopLyric),
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
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
                    ?.copyWith(color: AppColors.primary),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
