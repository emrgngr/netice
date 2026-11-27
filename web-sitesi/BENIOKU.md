# neticeoptik.com web sitesi

Sitenin asıl kaynağı bu klasördür. Buradaki bir değişiklik `ilk-surum` veya `main`
dalına girince `.github/workflows/web-sitesi.yml` siteyi Cloudflare Pages'teki
**neticeoptik** projesine kendiliğinden yayınlar (www.neticeoptik.com).
Bir PR açıldığında aynı iş sitenin önizlemesini ayrı bir adrese koyar
(`https://onizleme.neticeoptik.pages.dev`); adres işin özetinde yazar.

Gerekli secret'lar: `CLOUDFLARE_API_TOKEN` (Cloudflare Pages: Edit izni olmalı),
`CLOUDFLARE_ACCOUNT_ID`.

## 15 dil

Buradaki sayfalar **Türkçe asıl metindir**; yalnız bunları düzenleyin. Yayın sırasında
`tool/site/cevir.py` her sayfayı 14 dile daha çevirir (`/en/`, `/de/`, … `/ar/` sağdan sola)
ve dil menüsünü ekler. Çeviri Claude API ile yapılır (`ANTHROPIC_API_KEY` secret'ı); daha önce
çevrilmiş cümleler "site-ceviri" sürümündeki bellekten alınır, yalnız değişen cümleler yeniden
çevrilir. Bir çeviriyi elle düzeltmek için `tool/site/ceviri/<dil>.json` dosyasına aynı anahtarla
yazın. Türkçe sayfaya ilk kez gelen ziyaretçi tarayıcı diline göre kendi diline yönlendirilir.

Her dilin videoları `site-videolari.yml` ile üretilir (o dilde sesli bilgisayar tanıtımı ve
telefon rehber videosu) ve yayında `video/<dil>/` altına konur.

## Örnek raporlar sayfası

`ornek-raporlar.html` uygulamanın ürettiği raporların ilk sayfalarını gösterir. Rapor listesi
uygulamadaki "Örnek raporlar" ekranıyla aynıdır (`lib/ui/sample_reports.dart`). Yayın sırasında
`tool/ornek_raporlar_test.dart` raporları 15 dilde üretir, `tool/site/ornek_raporlar.sh` ilk
sayfaları `img/raporlar/<dil>/` altına JPG olarak koyar; her dil sayfası kendi görsellerini
gösterir. `img/raporlar/*.jpg` Türkçe görsellerdir ve bu adım çalışmazsa yedek olarak kalır.
Yalnız bir ülkeye ait kartlara `data-yalniz="tr"` yazılır (ör. e-Okul); diğer dillerde kaldırılır.
