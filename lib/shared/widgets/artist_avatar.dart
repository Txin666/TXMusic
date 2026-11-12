import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/asset_url.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_palette.dart';

/// 圆形歌手头像：有真实头像就加载网络图（磁盘缓存），否则用首字 + 渐变占位。
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 84,
    this.subtitle,
    this.onTap,
  });

  final String name;

  /// 歌手头像地址；为空或加载失败时回落首字占位。
  final String? avatarUrl;
  final double size;
  final String? subtitle;
  final VoidCallback? onTap;

  Widget _buildFallback() {
    return Text(
      name.isEmpty ? '?' : name.substring(0, 1),
      style: TextStyle(
        fontSize: size * 0.34,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.92),
      ),
    );
  }

  Widget _buildContent() {
    final String? src = AssetUrl.normalize(avatarUrl, size: AssetUrl.sizeFor(size));
    if (src == null) {
      return _buildFallback();
    }
    return CachedNetworkImage(
      imageUrl: src,
      width: size,
      height: size,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: Duration.zero,
      placeholder: (BuildContext context, String _) => _buildFallback(),
      errorWidget: (BuildContext context, String _, Object error) =>
          _buildFallback(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = AppColors.coverGradient(name);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size,
          child: Column(
            children: <Widget>[
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: context.palette.divider),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: _buildContent(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: context.palette.textDisabled),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
