#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// 把本进程放进一个「最后一个句柄关闭时终止整组进程」的 Job。
// 内嵌的 node 音乐服务是子进程，会随 Job 一起被回收，
// 避免客户端被强杀或崩溃后留下孤儿 node 进程占端口和内存。
void EnsureChildProcessesDieWithUs() {
  HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) {
    return;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!::SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                                 sizeof(limits)) ||
      !::AssignProcessToJobObject(job, ::GetCurrentProcess())) {
    ::CloseHandle(job);
    return;
  }
  // 故意不关闭 job 句柄：本进程退出时系统自动关闭它，随即终止组内所有子进程。
}

// 单实例互斥体：Local\ 前缀让它在当前登录会话内唯一，多用户登录互不影响。
constexpr wchar_t kSingleInstanceMutex[] =
    L"Local\\TxMusic.SingleInstance.7B2C4A31-9E5D-4C2A-8F71-1A2B3C4D5E6F";

// 第二个实例启动时，把已运行实例的窗口拉回前台。
// 窗口类名来自 win32_window.cpp 的 kWindowClassName；被拉起的进程可能还在建窗口，
// 所以做有限次重试，找不到就放弃（调用方仍然退出，避免真的双开）。
bool ActivateRunningInstance() {
  for (int attempt = 0; attempt < 20; ++attempt) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
      ::FlashWindow(existing, TRUE);
      return true;
    }
    ::Sleep(150);
  }
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 单实例门禁：互斥体已存在说明已有 TXMusic 在跑，激活它并立刻退出本进程。
  // 句柄故意不关闭，进程退出时由系统回收。
  HANDLE single_instance = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  EnsureChildProcessesDieWithUs();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"txmusic", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
