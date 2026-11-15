#include "tray_panel_native.h"

#include <windows.h>

#include <commctrl.h>
#include <dwmapi.h>
#include <shellscalingapi.h>

#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <desktop_multi_window/desktop_multi_window_plugin.h>

#include <cmath>
#include <memory>
#include <string>

namespace {

constexpr char kChannelName[] = "txmusic/tray_panel_native";
constexpr UINT_PTR kSubclassId = 0x54584D50;  // 'TXMP'

// Win11 DWM 属性（旧 SDK 没有这些枚举，直接按数值调用）。
constexpr DWORD kDwmUseImmersiveDarkMode = 20;
constexpr DWORD kDwmWindowCornerPreference = 33;
constexpr DWORD kDwmBorderColor = 34;
constexpr DWORD kDwmCornerRound = 2;       // DWMWCP_ROUND
constexpr DWORD kDwmColorNone = 0xFFFFFFFE;  // DWMWA_COLOR_NONE

HWND g_panel_hwnd = nullptr;
std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
// 弹出瞬间系统常常先回一次失焦（焦点还留在托盘），这个时刻之前忽略失焦，
// 否则面板会一闪即消。抢前台在前台锁下可能要重试一两次，留足窗口。
ULONGLONG g_shown_at_tick = 0;
constexpr ULONGLONG kBlurGuardMs = 600;
// guard 期内只有「窗口已经稳定显示一小会儿」之后的鼠标外击才判为真实关闭：
// 点击托盘那一下左键还没抬起、光标必然在面板之外，过早判断会把刚弹出的面板
// 直接当成外部点击收起，表现为「第一次点托盘没反应，要点第二次」。
constexpr ULONGLONG kAutoHideMinMs = 300;
constexpr UINT_PTR kForegroundRetryTimer = 0x7A01;
constexpr int kForegroundRetryMax = 3;
int g_foreground_retry = 0;

/// guard 期内若检测到用户真的在面板外按下鼠标，就说明这次失焦是「点外部」
/// 而不是弹出瞬间的伪失焦，应当立刻收起。
bool IsRealOutsideClick(HWND hwnd) {
  if ((::GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0) {
    return false;
  }
  POINT cursor{};
  if (!::GetCursorPos(&cursor)) {
    return false;
  }
  RECT rect{};
  if (!::GetWindowRect(hwnd, &rect)) {
    return true;
  }
  return !::PtInRect(&rect, cursor);
}

/// 抢前台并在失败时定时重试：任务栏是前台时 SetForegroundWindow 会被
/// 前台锁拒绝，一次不成就够让面板立刻被判失焦收起。
void GrabForeground(HWND hwnd) {
  HWND foreground = ::GetForegroundWindow();
  if (foreground == hwnd) {
    return;
  }
  if (foreground != nullptr) {
    const DWORD foreground_thread =
        ::GetWindowThreadProcessId(foreground, nullptr);
    const DWORD this_thread = ::GetCurrentThreadId();
    if (foreground_thread != 0 && foreground_thread != this_thread) {
      ::AttachThreadInput(this_thread, foreground_thread, TRUE);
      ::SetForegroundWindow(hwnd);
      ::SetFocus(hwnd);
      ::AttachThreadInput(this_thread, foreground_thread, FALSE);
      if (::GetForegroundWindow() == hwnd) {
        return;
      }
    }
  }
  ::SetForegroundWindow(hwnd);
}

int ReadInt(const flutter::EncodableMap& args, const char* key, int fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  if (const auto* value = std::get_if<double>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

/// 把子窗口改造成「无边框、置顶、不占任务栏」的弹出面板，并套用 Win11 圆角。
void ApplyPanelStyles(HWND hwnd) {
  LONG_PTR style = ::GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~static_cast<LONG_PTR>(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX |
                                 WS_MAXIMIZEBOX | WS_OVERLAPPED);
  style |= static_cast<LONG_PTR>(WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN);
  ::SetWindowLongPtr(hwnd, GWL_STYLE, style);

  LONG_PTR ex_style = ::GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style |= static_cast<LONG_PTR>(WS_EX_TOPMOST | WS_EX_TOOLWINDOW);
  ex_style &= ~static_cast<LONG_PTR>(WS_EX_APPWINDOW);
  ::SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  // 圆角与边框：圆角交给 DWM 抗锯齿，边框线设为 none，深色避免亮边闪一下。
  const DWORD corner = kDwmCornerRound;
  ::DwmSetWindowAttribute(hwnd, kDwmWindowCornerPreference, &corner,
                          sizeof(corner));
  const DWORD border_color = kDwmColorNone;
  ::DwmSetWindowAttribute(hwnd, kDwmBorderColor, &border_color,
                          sizeof(border_color));
  const BOOL dark = TRUE;
  ::DwmSetWindowAttribute(hwnd, kDwmUseImmersiveDarkMode, &dark, sizeof(dark));

  ::SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  ::ShowWindow(hwnd, SW_HIDE);
}

void HidePanel() {
  if (g_panel_hwnd != nullptr && ::IsWindow(g_panel_hwnd)) {
    ::KillTimer(g_panel_hwnd, kForegroundRetryTimer);
    ::ShowWindow(g_panel_hwnd, SW_HIDE);
  }
}

void ShowPanel(const flutter::EncodableMap& args) {
  if (g_panel_hwnd == nullptr || !::IsWindow(g_panel_hwnd)) {
    return;
  }
  const int x = ReadInt(args, "x", 0);
  const int y = ReadInt(args, "y", 0);
  const int width = ReadInt(args, "width", 0);
  const int height = ReadInt(args, "height", 0);

  // Dart 侧坐标与尺寸都是 Flutter 逻辑像素（screen_retriever 口径），
  // SetWindowPos 只认物理像素，高缩放下必须按目标显示器 DPI 折算，
  // 否则面板会缩成 1/scale 大小、位置也会偏到托盘左边。
  const POINT anchor{x, y};
  HMONITOR monitor = ::MonitorFromPoint(anchor, MONITOR_DEFAULTTONEAREST);
  UINT dpi_x = 96;
  UINT dpi_y = 96;
  if (monitor == nullptr ||
      FAILED(::GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) ||
      dpi_x == 0) {
    dpi_x = 96;
    dpi_y = 96;
  }
  const double scale_x = static_cast<double>(dpi_x) / 96.0;
  const double scale_y = static_cast<double>(dpi_y) / 96.0;
  const int device_x = static_cast<int>(std::lround(x * scale_x));
  const int device_y = static_cast<int>(std::lround(y * scale_y));
  const int device_width =
      width <= 0 ? 0 : static_cast<int>(std::lround(width * scale_x));
  const int device_height =
      height <= 0 ? 0 : static_cast<int>(std::lround(height * scale_y));

  UINT flags = SWP_SHOWWINDOW | SWP_NOOWNERZORDER;
  if (device_width <= 0 || device_height <= 0) {
    flags |= SWP_NOSIZE;
  }
  // 时间基准必须在窗口真正显示之前重置：首次弹出时窗口刚创建、g_shown_at_tick
  // 还是旧值（甚至 0），若等到显示之后才刷新，中间那一次 WA_INACTIVE 会被判成
  // 「早已超出 guard」而立刻收起面板。
  ::KillTimer(g_panel_hwnd, kForegroundRetryTimer);
  g_shown_at_tick = ::GetTickCount64();
  g_foreground_retry = 0;
  ::SetWindowPos(g_panel_hwnd, HWND_TOPMOST, device_x, device_y, device_width,
                 device_height, flags);
  ::ShowWindow(g_panel_hwnd, SW_SHOWNORMAL);
  // 点击托盘时前台窗口还是任务栏，直接 SetForegroundWindow 会被前台锁拒绝，
  // 面板拿不到激活就会出现「刚弹出就被判失焦收起」。先借用前台线程的输入
  // 队列抢一次，没抢到就交给定时器重试。
  GrabForeground(g_panel_hwnd);
  ::SetTimer(g_panel_hwnd, kForegroundRetryTimer, 120, nullptr);
}

/// 面板失去激活就收起：这是「点击外部自动关闭」的唯一可靠来源，
/// Flutter 侧的 WindowListener 在子窗口里没有 window_manager 可用。
LRESULT CALLBACK PanelSubclassProc(HWND hwnd, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR subclass_id,
                                   DWORD_PTR ref_data) {
  switch (message) {
    case WM_TIMER:
      if (wparam == kForegroundRetryTimer) {
        if (::GetForegroundWindow() == hwnd ||
            g_foreground_retry >= kForegroundRetryMax ||
            !::IsWindowVisible(hwnd)) {
          ::KillTimer(hwnd, kForegroundRetryTimer);
          break;
        }
        ++g_foreground_retry;
        GrabForeground(hwnd);
        break;
      }
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE && ::IsWindowVisible(hwnd)) {
        const ULONGLONG elapsed = ::GetTickCount64() - g_shown_at_tick;
        const bool out_of_guard = elapsed > kBlurGuardMs;
        // 超出 guard 一律收起；guard 内只有「面板已稳定显示一小会儿后用户又在
        // 面板外按下鼠标」才算真实外部点击，弹出瞬间的伪失焦（含点托盘那一下
        // 尚未抬起的左键）继续忽略。
        const bool real_outside_click =
            elapsed > kAutoHideMinMs && IsRealOutsideClick(hwnd);
        if (out_of_guard || real_outside_click) {
          HidePanel();
          if (g_channel) {
            g_channel->InvokeMethod("dismissed", nullptr);
          }
        }
      }
      break;
    case WM_NCHITTEST:
      // WS_THICKFRAME 只为换来 DWM 圆角，命中测试一律当客户区，
      // 否则面板四周会多出一圈可拖拽的缩放边。
      return HTCLIENT;
    default:
      break;
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "show") {
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      ShowPanel(*args);
    } else {
      ShowPanel(flutter::EncodableMap{});
    }
    result->Success();
    return;
  }
  if (method == "hide") {
    HidePanel();
    result->Success();
    return;
  }
  if (method == "isVisible") {
    // 以 Win32 真实可见性为唯一真相源：主窗口侧缓存的状态可能因失焦上报
    // 丢失而与屏幕上的实际情况错位，导致「点一下只收起、点第二下才弹出」。
    const bool visible = g_panel_hwnd != nullptr &&
                         ::IsWindow(g_panel_hwnd) &&
                         ::IsWindowVisible(g_panel_hwnd) != FALSE;
    result->Success(flutter::EncodableValue(visible));
    return;
  }
  result->NotImplemented();
}

void OnPanelWindowCreated(void* controller_pointer) {
  auto* controller =
      static_cast<flutter::FlutterViewController*>(controller_pointer);
  if (controller == nullptr || controller->view() == nullptr ||
      controller->engine() == nullptr) {
    return;
  }

  const HWND view_handle = controller->view()->GetNativeWindow();
  const HWND hwnd = ::GetAncestor(view_handle, GA_ROOT);
  if (hwnd == nullptr) {
    return;
  }

  g_panel_hwnd = hwnd;
  // 窗口一创建就把 guard 计时起点拉到现在：ApplyPanelStyles 里的 SW_HIDE 会
  // 触发一次 WA_INACTIVE，若基准仍是 0 会被判成「超出 guard」直接收起。
  g_shown_at_tick = ::GetTickCount64();
  ApplyPanelStyles(hwnd);
  ::SetWindowSubclass(hwnd, PanelSubclassProc, kSubclassId, 0);

  auto registrar_reference =
      controller->engine()->GetRegistrarForPlugin("TrayPanelNative");
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
                        ->GetRegistrar<flutter::PluginRegistrarWindows>(
                            registrar_reference);
  if (registrar == nullptr) {
    return;
  }
  g_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(HandleMethodCall);
}

}  // namespace

void TrayPanelNativeInstall() {
  DesktopMultiWindowSetWindowCreatedCallback(&OnPanelWindowCreated);
}
