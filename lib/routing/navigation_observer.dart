import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 历史里的一条记录。
@immutable
class NavigationEntry {
  const NavigationEntry({required this.location, this.isPush = false});

  /// 该步的目标位置，例如 `/rank`、`/search?q=周杰伦`、`/rank/8888`。
  final String location;

  /// 该步是否是 `context.push` 入栈（详情页 / 播放页）：
  /// 后退用 `go` 把它弹掉，前进用 `push` 才能还原成同样的层级关系。
  final bool isPush;

  @override
  String toString() => '$location${isPush ? ' (push)' : ''}';

  @override
  bool operator ==(Object other) =>
      other is NavigationEntry &&
      other.location == location &&
      other.isPush == isPush;

  @override
  int get hashCode => Object.hash(location, isPush);
}

/// 监听 Navigator 的入栈事件。
///
/// 为什么需要它：go_router 的 `go` 会替换当前配置并触发 delegate 回调，
/// 但 `context.push`（详情页、播放页都用它）只往 Navigator 压一层，
/// delegate 的 `currentConfiguration` 与位置回调都不会变。只靠 delegate
/// 记录历史的话，「点开歌单详情 → 后退」就永远弹不掉详情页，这里补上
/// push 这一路来源。
class NavigationLocationObserver extends NavigatorObserver {
  final List<void Function(NavigationEntry entry)> _listeners =
      <void Function(NavigationEntry entry)>[];

  void addListener(void Function(NavigationEntry entry) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(NavigationEntry entry) listener) {
    _listeners.remove(listener);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final String? name = route.settings.name;
    // 只认形如 `/xxx` 的路由名；首屏 push 与弹窗等匿名路由不入历史。
    if (previousRoute == null || name == null || !name.startsWith('/')) {
      return;
    }
    final NavigationEntry entry = NavigationEntry(location: name, isPush: true);
    for (final void Function(NavigationEntry entry) listener
        in List<void Function(NavigationEntry entry)>.of(_listeners)) {
      listener(entry);
    }
  }
}

/// 全局单例观察者：路由构建时注入，历史控制器订阅它。
final Provider<NavigationLocationObserver> navigationLocationObserverProvider =
    Provider<NavigationLocationObserver>(
      (Ref ref) => NavigationLocationObserver(),
    );
