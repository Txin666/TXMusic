import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/app_spacing.dart';
import '../../domain/discover_banner.dart';
import '../../../../theme/app_palette.dart';

/// 发现页顶部横幅：PageView + 指示点（骨架期不自动轮播，避免测试时干扰）。
class DiscoverBannerCarousel extends StatefulWidget {
  const DiscoverBannerCarousel({
    super.key,
    required this.banners,
    required this.onTapBanner,
  });

  final List<DiscoverBanner> banners;
  final ValueChanged<DiscoverBanner> onTapBanner;

  @override
  State<DiscoverBannerCarousel> createState() => _DiscoverBannerCarouselState();
}

class _DiscoverBannerCarouselState extends State<DiscoverBannerCarousel> {
  late final PageController _controller = PageController(
    viewportFraction: 0.86,
  );
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 触控板横向滑动 / Shift+滚轮切页。
  ///
  /// 鼠标拖拽由 [DesktopScrollBehavior] 放开；这里只消费横向指针信号，纵向滚轮
  /// 原样留给外层页面滚动，避免在横幅上滚动时整页被卡住。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final double dx = event.scrollDelta.dx;
    final double dy = event.scrollDelta.dy;
    if (dx.abs() < 8 || dx.abs() <= dy.abs()) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (PointerSignalEvent resolved) => _stepBy(dx),
    );
  }

  /// 按方向翻一页；已经在首/末页时不动，避免出现橡皮筋回弹。
  void _stepBy(double dx) {
    if (widget.banners.length < 2) {
      return;
    }
    final int target = (_index + (dx > 0 ? 1 : -1)).clamp(
      0,
      widget.banners.length - 1,
    );
    if (target == _index) {
      return;
    }
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: <Widget>[
        SizedBox(
          height: 188,
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.banners.length,
              onPageChanged: (int index) => setState(() => _index = index),
              itemBuilder: (BuildContext context, int index) {
                final DiscoverBanner banner = widget.banners[index];
                // 封面渐变里有偏亮的色（绿/橙/青），白字直接压上去对比不足，
                // 统一压暗 30% 再叠白字，保证深浅两套主题下标题都可读。
                final List<Color> colors = AppColors.coverGradient(banner.id)
                    .map((Color c) => Color.lerp(c, Colors.black, 0.3)!)
                    .toList(growable: false);
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: _buildCard(context, banner, colors),
                );
              },
            ),
            ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(widget.banners.length, (int i) {
            final bool active = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : context.palette.surfaceHigh,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context,
    DiscoverBanner banner,
    List<Color> colors,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onTapBanner(banner),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(color: context.palette.divider),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  banner.tag,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                banner.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                banner.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 16,
                          color: Color(0xFF04120C),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '立即播放',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF04120C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}