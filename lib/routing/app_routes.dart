/// 路由路径常量：全应用唯一来源，避免硬编码字符串（文档 §9.4）。
class AppRoutes {
  const AppRoutes._();

  // 主框架内（ShellRoute，带侧边导航 + 播放条）
  static const String discover = '/discover';
  static const String rank = '/rank';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String search = '/search';

  // 主框架内的详情页（带参数）
  static const String rankDetailPattern = '/rank/:id';
  static const String playlistDetailPattern = '/playlist/:id';
  static const String albumDetailPattern = '/album/:id';
  static const String artistDetailPattern = '/artist/:id';

  static String rankDetail(String id) => '/rank/$id';
  static String playlistDetail(String id) => '/playlist/$id';
  static String albumDetail(String id) => '/album/$id';
  static String artistDetail(String id) => '/artist/$id';

  // 独立窗口 / 全屏页（脱离 Shell，避免播放详情页重复渲染播放条）
  static const String player = '/player';

  /// 应用内自助扫码登录页（脱离 Shell，独立全屏页）。
  static const String login = '/login';

  /// 侧边导航可选项（顺序即展示顺序）。
  static const List<String> navDestinations = <String>[
    discover,
    rank,
    library,
    settings,
  ];
}
