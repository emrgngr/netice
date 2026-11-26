#include "ms_store.h"

#include <appmodel.h>
#include <shobjidl.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Services.Store.h>

namespace msstore {

namespace {

using winrt::Windows::Services::Store::StoreContext;

std::string Narrow(const winrt::hstring& s) { return winrt::to_string(s); }

winrt::hstring Wide(const std::string& s) { return winrt::to_hstring(s); }

// Masaüstü programında Store penceresinin hangi pencereye bağlanacağı
// IInitializeWithWindow ile bildirilmelidir.
StoreContext Context(HWND window) {
  StoreContext ctx = StoreContext::GetDefault();
  if (window != nullptr) {
    auto init = ctx.as<::IInitializeWithWindow>();
    init->Initialize(window);
  }
  return ctx;
}

std::string ErrorText(const winrt::hresult_error& e) {
  return "Error: " + Narrow(e.message());
}

// Ayrı iş parçacığında WinRT kullanmak için çok iş parçacıklı daire.
struct Apartment {
  Apartment() {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
    } catch (...) {
    }
  }
};

int64_t ToUnixMs(const winrt::Windows::Foundation::DateTime& t) {
  // DateTime: 1601'den beri 100 ns. 1601 → 1970 farkı 11644473600 s.
  const int64_t ticks = t.time_since_epoch().count();
  return ticks / 10000 - 11644473600000LL;
}

}  // namespace

bool IsPackaged() {
  UINT32 length = 0;
  const LONG rc = ::GetCurrentPackageFullName(&length, nullptr);
  return rc != APPMODEL_ERROR_NO_PACKAGE;
}

std::vector<Product> Products(HWND window, std::string* error) {
  Apartment apartment;
  std::vector<Product> out;
  try {
    StoreContext ctx = Context(window);
    auto kinds = winrt::single_threaded_vector<winrt::hstring>(
        {L"Durable", L"Consumable", L"UnmanagedConsumable"});
    auto result = ctx.GetAssociatedStoreProductsAsync(kinds).get();
    if (result.ExtendedError() != winrt::hresult{0}) {
      if (error) *error = "Error: products " + std::to_string(result.ExtendedError().value);
    }
    for (auto const& pair : result.Products()) {
      auto p = pair.Value();
      Product item;
      item.token = Narrow(p.InAppOfferToken());
      item.store_id = Narrow(p.StoreId());
      item.title = Narrow(p.Title());
      item.kind = Narrow(p.ProductKind());
      auto price = p.Price();
      const std::string recurring = Narrow(price.FormattedRecurrencePrice());
      item.price = recurring.empty() ? Narrow(price.FormattedPrice()) : recurring;
      for (auto const& sku : p.Skus()) {
        if (sku.IsSubscription()) item.subscription = true;
      }
      out.push_back(item);
    }
  } catch (const winrt::hresult_error& e) {
    if (error) *error = ErrorText(e);
  } catch (...) {
    if (error) *error = "Error: products";
  }
  return out;
}

std::string Purchase(HWND window, const std::string& store_id) {
  Apartment apartment;
  try {
    StoreContext ctx = Context(window);
    auto result = ctx.RequestPurchaseAsync(Wide(store_id)).get();
    using winrt::Windows::Services::Store::StorePurchaseStatus;
    switch (result.Status()) {
      case StorePurchaseStatus::Succeeded:
        return "Succeeded";
      case StorePurchaseStatus::AlreadyPurchased:
        return "AlreadyPurchased";
      case StorePurchaseStatus::NotPurchased:
        return "NotPurchased";
      case StorePurchaseStatus::NetworkError:
        return "NetworkError";
      case StorePurchaseStatus::ServerError:
        return "ServerError";
    }
    return "Error: unknown";
  } catch (const winrt::hresult_error& e) {
    return ErrorText(e);
  } catch (...) {
    return "Error: purchase";
  }
}

std::vector<License> Licenses(HWND window, std::string* error) {
  Apartment apartment;
  std::vector<License> out;
  try {
    StoreContext ctx = Context(window);
    auto app = ctx.GetAppLicenseAsync().get();
    for (auto const& pair : app.AddOnLicenses()) {
      auto l = pair.Value();
      License item;
      item.token = Narrow(l.InAppOfferToken());
      // SkuStoreId "9NXXXX/0010" biçimindedir; ürün kimliği eğik çizgiden öncesi.
      std::string sku = Narrow(l.SkuStoreId());
      const auto slash = sku.find('/');
      item.store_id = slash == std::string::npos ? sku : sku.substr(0, slash);
      item.active = l.IsActive();
      item.expires_ms = ToUnixMs(l.ExpirationDate());
      out.push_back(item);
    }
  } catch (const winrt::hresult_error& e) {
    if (error) *error = ErrorText(e);
  } catch (...) {
    if (error) *error = "Error: licenses";
  }
  return out;
}

std::string Fulfill(HWND window, const std::string& store_id) {
  Apartment apartment;
  try {
    StoreContext ctx = Context(window);
    GUID guid;
    if (FAILED(::CoCreateGuid(&guid))) return "Error: guid";
    winrt::guid tracking(guid);
    auto result = ctx.ReportConsumableFulfillmentAsync(Wide(store_id), 1, tracking).get();
    using winrt::Windows::Services::Store::StoreConsumableStatus;
    switch (result.Status()) {
      case StoreConsumableStatus::Succeeded:
        return "Succeeded";
      case StoreConsumableStatus::InsufficentQuantity:
        return "InsufficientQuantity";
      case StoreConsumableStatus::NetworkError:
        return "NetworkError";
      case StoreConsumableStatus::ServerError:
        return "ServerError";
    }
    return "Error: unknown";
  } catch (const winrt::hresult_error& e) {
    return ErrorText(e);
  } catch (...) {
    return "Error: fulfill";
  }
}

}  // namespace msstore
