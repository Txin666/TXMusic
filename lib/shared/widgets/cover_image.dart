import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/asset_url.dart';
import '../../theme/app_palette.dart';
import 'cover_placeholder.dart';

/// 网络封面：磁盘缓存 + 加载态 + 失败自动退回 [CoverPlaceholder] 渐变占位。
///
/// 开发文档 §5 图片加载策略：封面统一走 `CachedNetworkImage`，避免列表滚动反复请求；
/// 地址先经 [AssetUrl.normalize] 补 `{size}` 与 https，偶发 403/超时直接兜底，
/// 列表里不出现破图红块。
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.seed,
    this.url,
    this.size = 160,
    this.radius = 12,
    this.icon = Icons.music_note_rounded,
    this.label,
    this.circle = false,
    this.fit = BoxFit.cover,
  });

  final String seed;
  final String? url;
  final double size;
  final double radius;
  final IconData icon;
  final String? label;
  final bool circle;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(
      circle ? size / 2 : radius,
    );
    final Widget fallback = CoverPlaceholder(
      seed: seed,
      size: size,
      radius: radius,
      icon: icon,
      label: label,
    );

    final String? src = AssetUrl.normalize(url, size: AssetUrl.sizeFor(size));
    if (src == null) {
      return fallback;
    }

    final int cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: src,
        width: size,
        height: size,
        fit: fit,
        memCacheWidth: cachePx > 0 ? cachePx : null,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (BuildContext context, String _) => Container(
          width: size,
          height: size,
          color: context.palette.surfaceHigh,
          alignment: Alignment.center,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.palette.textDisabled,
            ),
          ),
        ),
        errorWidget: (BuildContext context, String _, Object error) => fallback,
      ),
    );
  }
}
