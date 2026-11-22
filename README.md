# Netice

**Kâğıttan sonuca, saniyeler içinde.**

Netice, öğretmenlerin kâğıt üzerinde yaptığı çoktan seçmeli sınavları telefon kamerasıyla ya da tarayıcıyla okuyan, puanlayan ve analiz eden bir uygulamadır. Tek Flutter kod tabanıyla iOS, Android, Windows ve macOS'ta çalışır.

## Bu sürümde neler var (MVP, ilk adım)

| Alan | Durum |
|---|---|
| Sınav oluşturma (5–100 soru, 4/5 şık, cevap anahtarı tuş takımı ve klavye girişi, yanlış götürme) | ✅ |
| Basılı A4 optik form (PDF): köşe işaretleri, öğrenci numarası ızgarası, öğrenciye özel ad baskısı | ✅ |
| Okuma motoru (cihaz üzerinde, internetsiz): köşe tespiti, perspektif düzeltme, yerel ışık dengeleme, doluluk ölçümü | ✅ |
| Belirsiz işaretler için kontrol kuyruğu (çift işaret, silik/yarım silinmiş işaret, eşleşmeyen öğrenci) | ✅ |
| Fotoğraf/tarama dosyası ve çok sayfalı PDF ile toplu okuma | ✅ |
| Puanlama: D/Y/B, net, yanlış götürme, iptal soru, birden çok doğru kabul, anahtar değişince anında yeniden puanlama | ✅ |
| Analiz: ortalama, medyan, std. sapma, dağılım, KR-20, madde güçlüğü (p), ayırt edicilik (D), çeldirici tablosu, anahtar uyarısı | ✅ |
| Raporlar: PDF sınıf sonuç listesi + madde analizi, Excel'de açılan not listesi (CSV) | ✅ |
| Öğrenci listesi aktarma (Excel'den CSV, Türkçe başlık tanıma, Windows-1254 desteği) | ✅ |
| Pano, mobil/masaüstü uyumlu ekranlar, karanlık mod, Netice tasarım dili ve "Optik N" logosu | ✅ |
| Kurgusal örnek veriyle ilk açılış, "kâğıt basmadan örnek formla dene" | ✅ |

## Sıradaki adımlar

1. Kamerayla **seri okuma modu** (deklanşörsüz, titreşim + ses ile).
2. Gerçek telefon fotoğraflarıyla doğruluk ölçümü ve eşiklerin ayarı (hedef ≥ %99,5).
3. Şifreli SQLite'a geçiş (şu an veriler cihazda tek bir JSON dosyasında).
4. Kazanım etiketleme ve kazanım karnesi, kitapçık türleri (A/B).
5. QR kodlu öğrenci formu, mini optik şerit.
6. Uygulama simgeleri, mağaza ve Windows/macOS kurulum paketleri.
7. Bulut eşitleme ve web paneli (KVKK, yurt içi barındırma).

## Proje yapısı

```
lib/
  core/       veri modeli, puanlama, analiz, içe/dışa aktarma, veri deposu
  omr/        form geometrisi, okuma motoru, perspektif dönüşümü, örnek form çizici
  reports/    PDF optik form ve PDF rapor üretimi
  ui/         ekranlar, tema, logo
test/         puanlama, analiz, okuma motoru, içe aktarma ve PDF testleri
tool/         ekran görüntüsü üretici
```

## Geliştirme

```bash
flutter pub get
flutter test                 # tüm testler
flutter run -d windows       # ya da macos, android, ios
flutter test tool/screenshots_test.dart   # build/screenshots altına ekran görüntüleri
```

Yazı tipi: Plus Jakarta Sans (SIL Open Font License, `assets/fonts/OFL.txt`).
Örnek verideki ad ve sonuçlar kurgusaldır.
