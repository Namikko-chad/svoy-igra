#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

// «Своя игра» — the window title; also how a second launch finds the first.
static const wchar_t kWindowTitle[] =
    L"\x0421\x0432\x043E\x044F \x0438\x0433\x0440\x0430";

// Single instance: a svoyigra:// link opened while the app runs is handed to
// the existing window (app_links), which is brought to the front.
static bool SendAppLinkToInstance() {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  if (!hwnd) {
    return false;
  }
  SendAppLink(hwnd);
  WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
  GetWindowPlacement(hwnd, &place);
  ShowWindow(hwnd, place.showCmd == SW_SHOWMAXIMIZED ? SW_SHOWMAXIMIZED
                                                     : SW_RESTORE);
  SetForegroundWindow(hwnd);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (SendAppLinkToInstance()) {
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

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(kWindowTitle, origin, size)) {
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
