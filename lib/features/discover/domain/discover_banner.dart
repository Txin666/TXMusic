/// 发现页横幅（骨架期用本地渐变替代真实运营图）。
class DiscoverBanner {
  const DiscoverBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    this.tag = '推荐',
    this.targetRoute,
  });

  final String id;
  final String title;
  final String subtitle;
  final String tag;

  /// 点击后跳转的路由；为空时仅提示占位。
  final String? targetRoute;
}
