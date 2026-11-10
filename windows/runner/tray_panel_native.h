#ifndef RUNNER_TRAY_PANEL_NATIVE_H_
#define RUNNER_TRAY_PANEL_NATIVE_H_

// 托盘悬浮面板窗口的原生支持。
//
// 面板是 desktop_multi_window 拉起的独立 Flutter 引擎窗口，而 window_manager
// 的 native_window 是进程级单值（指向主窗口），把插件注册到子引擎会把主窗口的
// 窗口操作劫持到面板上，所以面板的窗口能力在这里单独实现：
//   * 创建时改成无边框弹出窗口 + 置顶 + 不占任务栏 + DWM 圆角；
//   * 提供一个精简 MethodChannel（show/hide）用于定位与显隐；
//   * 失去焦点时自动隐藏，并通过 blurred 事件通知 Dart 侧同步状态。
void TrayPanelNativeInstall();

#endif  // RUNNER_TRAY_PANEL_NATIVE_H_
