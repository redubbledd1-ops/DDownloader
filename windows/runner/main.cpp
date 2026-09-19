#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Een instantie per gebruiker. De browser-extentie hoeft hier niets voor te
// weten: de native host zet zijn opdracht altijd eerst in de inbox-wachtrij
// (die de draaiende app elke seconde leest) en start de exe alleen als er nog
// geen draait. Een tweede start is dus altijd "breng het venster naar voren".
constexpr const wchar_t kSingleInstanceMutex[] =
    L"Local\\Downoader_SingleInstance";
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"Downloader";

std::wstring ExecutablePathOf(DWORD process_id) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    return std::wstring();
  }
  wchar_t buffer[MAX_PATH] = {};
  DWORD length = MAX_PATH;
  std::wstring path;
  if (::QueryFullProcessImageNameW(process, 0, buffer, &length)) {
    path.assign(buffer, length);
  }
  ::CloseHandle(process);
  return path;
}

std::wstring OwnExecutablePath() {
  wchar_t buffer[MAX_PATH] = {};
  DWORD length = ::GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  return std::wstring(buffer, length);
}

struct FindWindowContext {
  std::wstring executable;
  HWND result = nullptr;
};

BOOL CALLBACK FindOwnWindow(HWND window, LPARAM param) {
  auto* context = reinterpret_cast<FindWindowContext*>(param);

  wchar_t class_name[256] = {};
  ::GetClassNameW(window, class_name, 256);
  if (::wcscmp(class_name, kWindowClassName) != 0) {
    return TRUE;
  }

  // De vensterklasse komt van Flutter zelf en is dus niet uniek voor deze
  // app; pas het exe-pad maakt zeker dat we niet een andere Flutter-app naar
  // voren halen.
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (ExecutablePathOf(process_id) != context->executable) {
    return TRUE;
  }

  context->result = window;
  return FALSE;
}

bool ActivateRunningInstance() {
  FindWindowContext context;
  context.executable = OwnExecutablePath();
  if (context.executable.empty()) {
    return false;
  }
  ::EnumWindows(FindOwnWindow, reinterpret_cast<LPARAM>(&context));
  if (context.result == nullptr) {
    return false;
  }
  if (::IsIconic(context.result)) {
    ::ShowWindow(context.result, SW_RESTORE);
  }
  ::SetForegroundWindow(context.result);
  ::BringWindowToTop(context.result);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // De eerste instantie kan net aan het opstarten zijn en nog geen venster
    // hebben; even doorproberen is beter dan meteen opgeven.
    for (int attempt = 0; attempt < 20 && !ActivateRunningInstance();
         ++attempt) {
      ::Sleep(100);
    }
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

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    if (single_instance != nullptr) {
      ::CloseHandle(single_instance);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance != nullptr) {
    ::CloseHandle(single_instance);
  }
  return EXIT_SUCCESS;
}
