import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主框架 UI 状态（侧边导航折叠等）。仅 shell 内部使用，不跨 feature 共享。
class ShellState {
  const ShellState({this.navCollapsed = false});

  final bool navCollapsed;

  ShellState copyWith({bool? navCollapsed}) =>
      ShellState(navCollapsed: navCollapsed ?? this.navCollapsed);
}

class ShellController extends Notifier<ShellState> {
  @override
  ShellState build() => const ShellState();

  void toggleNav() => state = state.copyWith(navCollapsed: !state.navCollapsed);

  void setNavCollapsed(bool collapsed) =>
      state = state.copyWith(navCollapsed: collapsed);
}

final shellControllerProvider = NotifierProvider<ShellController, ShellState>(
  ShellController.new,
);
