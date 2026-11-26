import '../l10n/l10n.dart';
/// Uygulama sürümü (pubspec.yaml ile aynı tutulur).
const appVersion = '1.0.0';

/// Geliştirici iletişim adresi. Mağazaya çıkmadan önce doldurulmalı; boşsa
/// metinlerde iletişim satırı gösterilmez.
const contactEmail = 'info@neticeoptik.com';

/// Mağaza bağlantıları. Uygulama yayımlanınca [storePublished] true yapılır;
/// o zamana kadar paylaşım metni bağlantısız gider, yıldızlar uygulamada kalır.
const storePublished = false;
const androidPackage = 'com.netice.netice';
/// App Store'da yayımlanınca doldurulur (ör. https://apps.apple.com/app/id123…).
const appStoreUrl = '';
const playStoreUrl = 'https://play.google.com/store/apps/details?id=$androidPackage';

/// Belgelerin ve paylaşım mesajlarının altındaki indirme bağlantısı:
/// tanıtım sayfası varsa o, yoksa Google Play sayfası.
String get downloadUrl => websiteUrl.isNotEmpty ? websiteUrl : playStoreUrl;
String get downloadLabel => downloadUrl.replaceFirst(RegExp(r'^https?://'), '');

/// Mesajların sonuna eklenen kısa imza.
String get downloadSignature => tr('\n\n— Netice ile hazırlandı. Siz de deneyin: {0}', [downloadUrl]);

/// Kullanım koşulları: kendi sayfamız yayımlanana kadar Apple'ın standart
/// son kullanıcı lisans sözleşmesi (App Store'un da kabul ettiği metin).
const termsUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/// Tanıtım sayfasının adresi (yayımlanınca doldurulur).
const websiteUrl = '';

String get shareText => tr('Optik kâğıtları telefonla okutup puan, analiz ve karneyi saniyeler içinde hazırlayan Netice\'yi kullanıyorum, sana da öneririm. Çevrimdışı çalışıyor, veriler telefonda kalıyor.\n\nİndir: {0}', [downloadUrl]);

String _contact(String prefix) => contactEmail.isEmpty ? '' : '\n\n$prefix $contactEmail';

/// Uygulama içi gizlilik politikası (mağazadaki metnin kısa hâli).
String get privacyPolicy => [_privacy, _privacyPromo, _privacy2, _privacyNot, _privacy3, _privacyAi].map(tr).join('\n\n') +
    _contact(tr('İletişim:'));

const _privacyAi = '''Nottan soru üretme (isteğe bağlı)
Kütüphanede "Bu nottan soru üret" dediğinizde ve onay verdiğinizde, yalnızca o notun metni ve görselleri Netice'nin soru sunucusu üzerinden yapay zekâ hizmetine (Anthropic Claude) gönderilir. Netice notu ve üretilen soruları saklamaz; sunucuda yalnızca kota için cihaza özel rastgele bir kimlik ve aylık soru sayısı tutulur. Anthropic bu içeriği yapay zekâ eğitiminde kullanmaz. Öğrenci bilgisi içeren notları göndermeyin. Bu özelliği kullanmazsanız hiçbir içerik gönderilmez.''';

const _privacy = '''Netice, öğretmenlerin optik cevap kâğıtlarını okutup sonuçları analiz etmesi için tasarlanmıştır.

Çevrimdışı çalışır, veriler cihazınızda kalır
Netice internet bağlantısı olmadan çalışır. Girdiğiniz ve okuttuğunuz tüm bilgiler yalnızca uygulamayı kullandığınız telefonda (veya bilgisayarda), uygulamaya ait klasörde saklanır. Uygulama hesap açmayı zorunlu tutmaz ve hiçbir veriyi geliştiriciye ya da üçüncü kişilere göndermez.

İsteğe bağlı Google hesabı
Ayarlar > Hesap bölümünden dilerseniz Google hesabınızla giriş yapıp yedeğinizi kendi Google Drive alanınıza kaydedebilirsiniz. Bu özellik yalnızca siz açtığınızda internete bağlanır; yedek, Drive'ınızda yalnızca Netice'nin görebildiği gizli uygulama klasöründe tutulur ve geliştiriciye ulaşmaz. Kullanmazsanız uygulama tamamen çevrimdışı kalır.''';

const _privacyPromo = '''Tanıtımlar ve ürün önerileri
Netice'de üçüncü taraf reklam ve reklam ağı yoktur. Ücretsiz sürümde bazı sayfalarda yalnızca geliştiricinin kendi uygulamalarının, web sitelerinin ve mağazasının tanıtımları (görsel veya video) ile kapatılabilir bir ürün öneri kartı gösterilir; Netice Pro'da tanıtım gösterilmez. Reklam kimliği okunmaz ve kullanıcı izlenmez. Tanıtımların işe yarayıp yaramadığını görmek için yalnızca her tanıtımın günlük toplam görülme ve tıklanma sayısı kimliksiz olarak Netice'nin sayaç sunucusuna gönderilir; bu sayılarla birlikte cihaz kimliği, hesap, konum, öğrenci bilgisi ya da size ait başka bir bilgi gönderilmez ve IP adresi saklanmaz. İnternet varsa tanıtım ve ürün listeleri herkese açık bir adresten indirilip cihazda saklanır; bu isteklerde size ya da öğrencilerinize ait hiçbir bilgi bulunmaz. Bir tanıtıma veya ürüne dokunduğunuzda ilgili sayfa tarayıcınızda açılır ve o sitenin kendi kuralları geçerli olur.''';

const _privacy2 = '''Netice Pro aboneliği
Okuma ve temel sonuçlar ücretsizdir. Dönem raporu, karneler, veliye gönderme, Google Drive yedeği, gelişmiş grafikler ve resmi yazı başlığı Netice Pro aboneliğiyle açılır; ilk kurulumda 14 gün ücretsiz denenebilir, kart bilgisi istenmez. Ödeme Google Play tarafından alınır; kart ve ödeme bilgileriniz geliştiriciye ulaşmaz. Abonelik dönem sonunda kendiliğinden yenilenir ve Google Play > Abonelikler bölümünden istediğiniz zaman iptal edilebilir.

Tutulan bilgiler
Öğrenci adı, soyadı, okul numarası ve sınıfı; sınav adı, tarihi, cevap anahtarı ve kazanımları; okutulan kâğıtlardaki işaretler, puanlar ve istatistikler; okul ve öğretmen bilgileri. Bu bilgiler yalnızca bu cihazda, uygulamaya ait klasörde saklanır; hiçbir sunucuya yüklenmez.

Kamera ve fotoğraflar
Kamera yalnızca siz izin verdiğinizde, cevap kâğıtlarını okumak için kullanılır. Görüntüler cihazda işlenir. Okunan her kâğıdın düzleştirilmiş görüntüsü, işaretli kâğıdı sonradan görebilmeniz için yalnızca bu cihazda saklanır; hiçbir yere gönderilmez ve sınavı veya verileri sildiğinizde silinir.

Paylaşım ve yedek
Rapor, liste ve yedek dosyalarını paylaşmayı siz seçersiniz. Paylaştığınız dosya, seçtiğiniz uygulamanın (e-posta, bulut, yazıcı) kurallarına tabidir. Yedek dosyaları öğrenci bilgisi içerir; güvenli bir yerde saklayın.''';

const _privacyNot = '''Toplanmayan veriler
Konum, rehber, cihaz kimliği, kullanım istatistiği, çökme raporu ve reklam kimliği toplanmaz. Tanıtımlar için yalnızca yukarıda anlatılan kimliksiz toplam sayılar gönderilir.''';

const _privacy3 = '''Silme
Öğrenci, sınav ve kâğıtları tek tek ya da Ayarlar > "Tüm verileri sil" ile bir seferde silebilirsiniz; otomatik yedekleri de birlikte silmeyi seçebilirsiniz. Google Drive yedeği kullanıyorsanız onu da Ayarlar > Hesap bölümünden silebilirsiniz. Uygulama kaldırıldığında tüm veriler cihazdan silinir.''';

/// KVKK aydınlatma metni.
String get kvkkNotice => tr(_kvkk) + _contact(tr('Uygulama ile ilgili sorular:'));

const _kvkk = '''6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında bilgilendirme

Veri sorumlusu
Uygulamaya öğrenci bilgilerini giren öğretmen ve bağlı olduğu okul veri sorumlusudur. Uygulama geliştiricisi bu verilere erişmez ve onları işlemez.

İşlenen veriler
Öğrenci adı, soyadı, okul numarası, sınıfı; sınav cevapları, puanları ve başarı istatistikleri.

Amaç ve hukuki sebep
Sınavların değerlendirilmesi, öğrenci başarısının izlenmesi ve sonuç raporlarının hazırlanması (KVKK m. 5/2-ç ve 5/2-f; eğitim-öğretim hizmetinin yürütülmesi).

Saklama ve aktarım
Uygulama çevrimdışı çalışır. Veriler yalnızca öğretmenin kullandığı telefonda (veya bilgisayarda) saklanır; uygulama tarafından yurt içinde veya yurt dışında hiçbir sunucuya ya da üçüncü kişiye aktarılmaz. Öğretmen isterse yedeğini kendi Google Drive hesabına kaydedebilir; bu durumda aktarım öğretmenin kendi tercihi ve Google'ın koşullarıyla yapılır. Öğretmenin kendi isteğiyle paylaştığı rapor ve yedeklerin sorumluluğu öğretmene aittir.

Toplama yöntemi
Elle giriş, Excel listesinden aktarım ve cevap kâğıtlarının kamerayla okunması.

Saklama süresi
Öğretmen silene veya uygulamayı kaldırana kadar.

Haklar
Öğrenciler ve velileri KVKK m. 11'deki haklarını veri sorumlusu olan öğretmene veya okula başvurarak kullanır.''';
