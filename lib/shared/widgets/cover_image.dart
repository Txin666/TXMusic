import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'cover_placeholder.dart';

/// 网络封面：加载失败或无地址时自动退回 [CoverPlaceholder] 渐变占位。
///
/// 真实接口的封面多为 `imge.kugou.com` 模板串，偶发 403/超时属于常态，
/// 这里统一兜底，避免列表里出现破图方块。
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
  });

  final String seed;
  final String? url;
  final double size;
  final double radius;
  final IconData icon;
  final String? label;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final String? src = url;
    final Widget fallback = CoverPlaceholder(
      seed: seed,
      size: size,
      radius: radius,
      icon: icon,
      label: label,
    );
    if (src == null || src.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? size / 2 : radius),
      child: Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            fallback,
        loadingBuilder: (
          BuildContext context,
          Widget child,
          ImageChunkEvent? progress,
        ) {
          if (progress == null) {
            return child;
          }
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(circle ? size / 2 : radius),
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }
}
