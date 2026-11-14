import 'package:flutter/material.dart';

/// 应用内品牌标识：统一使用 `assets/icons/TX MUSIC.png`。
///
/// 说明：
/// - 侧边导航、标题栏等需要显示 logo 的位置都走本组件，避免各处硬编码路径；
/// - 资源缺失（例如未在 pubspec 声明）时退回渐变图标，不能出现整块空白；
/// - 图标本身已带圆角与底色，这里只做裁剪与等比缩放。
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.radius = 9});

  /// 边长（宽高一致，正方形）。
  final double size;

  /// 圆角半径；传 0 表示不裁剪。
  final double radius;

  /// logo 资源路径（与 `windows/runner/resources/app_icon.ico` 同源）。
  static const String assetPath = 'assets/icons/TX MUSIC.png';

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        debugPrint('品牌图标加载失败($assetPath): $error');
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.primary,
          child: Icon(
            Icons.graphic_eq_rounded,
            size: size * 0.55,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        );
      },
    );

    if (radius <= 0) {
      return image;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
  }
}
