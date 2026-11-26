#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <functional>
#include <memory>
#include <mutex>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Microsoft Store satın alma kanalı (netice/msstore). Store çağrıları
  // ayrı iş parçacığında çalışır; sonuçlar pencere mesajıyla arayüz
  // iş parçacığına taşınıp Dart'a orada iletilir.
  void RegisterStoreChannel();
  void DrainStoreResults();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> store_channel_;
  std::mutex store_mutex_;
  std::vector<std::function<void()>> store_results_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
