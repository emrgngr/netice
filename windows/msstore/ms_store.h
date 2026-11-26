// Microsoft Store satın alma köprüsü (Windows.Services.Store).
// Program Microsoft Store'dan kurulduğunda (MSIX paketi) Pro eklentileri
// Store penceresiyle satın alınır ve lisanslar Store'dan okunur. Paketsiz
// (kurulum programıyla) çalışan sürümde IsPackaged() false döner.
//
// Bütün işlevler bekler (engelleyicidir); arayüz iş parçacığında değil,
// ayrı bir iş parçacığında çağrılmalıdır. Hiçbiri istisna fırlatmaz.
#ifndef NETICE_MS_STORE_H_
#define NETICE_MS_STORE_H_

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

namespace msstore {

struct Product {
  std::string token;     // Partner Center'daki ürün kimliği (InAppOfferToken)
  std::string store_id;  // Store kimliği (9N...)
  std::string title;
  std::string price;     // biçimlenmiş fiyat (abonelikte yenileme fiyatı)
  std::string kind;      // Durable, Consumable, UnmanagedConsumable
  bool subscription = false;
};

struct License {
  std::string token;
  std::string store_id;  // ürünün Store kimliği (SKU eki olmadan)
  bool active = false;
  int64_t expires_ms = 0;  // Unix zamanı (ms); süresizse 0
};

// Program bir MSIX paketi olarak mı çalışıyor (Store'dan kurulmuş)?
bool IsPackaged();

std::vector<Product> Products(HWND window, std::string* error);

// Sonuç: Succeeded, AlreadyPurchased, NotPurchased, NetworkError,
// ServerError ya da "Error: ..." ile başlayan hata.
std::string Purchase(HWND window, const std::string& store_id);

std::vector<License> Licenses(HWND window, std::string* error);

// Geliştiricinin yönettiği tüketilebilir ürünü (dönem paketi, soru paketi)
// "teslim edildi" olarak bildirir. Sonuç: Succeeded ya da hata metni.
std::string Fulfill(HWND window, const std::string& store_id);

}  // namespace msstore

#endif  // NETICE_MS_STORE_H_
