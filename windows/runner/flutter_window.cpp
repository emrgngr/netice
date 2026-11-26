#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <thread>

#include "flutter/generated_plugin_registrant.h"
#include "ms_store.h"

namespace {

// Store iş parçacığı sonucu hazır olunca pencereye gönderilen mesaj.
constexpr UINT kStoreResultMessage = WM_APP + 0x51;

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::string StringArg(const EncodableValue* args, const char* key) {
  const auto* map = std::get_if<EncodableMap>(args);
  if (!map) return "";
  auto it = map->find(EncodableValue(key));
  if (it == map->end()) return "";
  const auto* s = std::get_if<std::string>(&it->second);
  return s ? *s : "";
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterStoreChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterStoreChannel() {
  store_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "netice/msstore",
      &flutter::StandardMethodCodec::GetInstance());
  store_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string method = call.method_name();
        if (method == "isPackaged") {
          result->Success(EncodableValue(msstore::IsPackaged()));
          return;
        }
        if (method != "products" && method != "purchase" &&
            method != "licenses" && method != "fulfill") {
          result->NotImplemented();
          return;
        }
        const std::string store_id = StringArg(call.arguments(), "storeId");
        HWND window = GetHandle();
        std::shared_ptr<flutter::MethodResult<EncodableValue>> shared(
            std::move(result));
        std::thread([this, method, store_id, window, shared]() {
          EncodableValue value;
          std::string error;
          if (method == "products") {
            EncodableList list;
            for (const auto& p : msstore::Products(window, &error)) {
              list.push_back(EncodableValue(EncodableMap{
                  {EncodableValue("token"), EncodableValue(p.token)},
                  {EncodableValue("storeId"), EncodableValue(p.store_id)},
                  {EncodableValue("title"), EncodableValue(p.title)},
                  {EncodableValue("price"), EncodableValue(p.price)},
                  {EncodableValue("kind"), EncodableValue(p.kind)},
                  {EncodableValue("subscription"), EncodableValue(p.subscription)},
              }));
            }
            value = EncodableValue(EncodableMap{
                {EncodableValue("items"), EncodableValue(list)},
                {EncodableValue("error"), EncodableValue(error)},
            });
          } else if (method == "licenses") {
            EncodableList list;
            for (const auto& l : msstore::Licenses(window, &error)) {
              list.push_back(EncodableValue(EncodableMap{
                  {EncodableValue("token"), EncodableValue(l.token)},
                  {EncodableValue("storeId"), EncodableValue(l.store_id)},
                  {EncodableValue("active"), EncodableValue(l.active)},
                  {EncodableValue("expiresMs"), EncodableValue(l.expires_ms)},
              }));
            }
            value = EncodableValue(EncodableMap{
                {EncodableValue("items"), EncodableValue(list)},
                {EncodableValue("error"), EncodableValue(error)},
            });
          } else if (method == "purchase") {
            value = EncodableValue(msstore::Purchase(window, store_id));
          } else {
            value = EncodableValue(msstore::Fulfill(window, store_id));
          }
          {
            std::lock_guard<std::mutex> lock(store_mutex_);
            store_results_.push_back(
                [shared, value]() { shared->Success(value); });
          }
          ::PostMessage(window, kStoreResultMessage, 0, 0);
        }).detach();
      });
}

void FlutterWindow::DrainStoreResults() {
  std::vector<std::function<void()>> ready;
  {
    std::lock_guard<std::mutex> lock(store_mutex_);
    ready.swap(store_results_);
  }
  for (auto& f : ready) f();
}

void FlutterWindow::OnDestroy() {
  store_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kStoreResultMessage:
      DrainStoreResults();
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
