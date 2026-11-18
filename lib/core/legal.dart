/// Uygulama sürümü (pubspec.yaml ile aynı tutulur).
const appVersion = '1.0.0';

/// Geliştirici iletişim adresi. Mağazaya çıkmadan önce doldurulmalı; boşsa
/// metinlerde iletişim satırı gösterilmez.
const contactEmail = '';

/// Mağaza bağlantıları. Uygulama yayımlanınca [storePublished] true yapılır;
/// o zamana kadar paylaşım metni bağlantısız gider, yıldızlar uygulamada kalır.
const storePublished = false;
const androidPackage = 'com.netice.netice';
const playStoreUrl = 'https://play.google.com/store/apps/details?id=$androidPackage';

/// Belgelerin ve paylaşım mesajlarının altındaki indirme bağlantısı:
/// tanıtım sayfası varsa o, yoksa Google Play sayfası.
String get downloadUrl => websiteUrl.isNotEmpty ? websiteUrl : playStoreUrl;
String get downloadLabel => downloadUrl.replaceFirst(RegExp(r'^https?://'), '');

/// Mesajların sonuna eklenen kısa imza.
String get downloadSignature => '\n\n— Netice ile hazırlandı. Siz de deneyin: $downloadUrl';

/// Tanıtım sayfasının adresi (yayımlanınca doldurulur).
const websiteUrl = '';

String get shareText => 'Optik kâğıtları telefonla okutup puan, analiz ve karneyi saniyeler içinde hazırlayan '
    'Netice\'yi kullanıyorum, sana da öneririm. Çevrimdışı çalışıyor, veriler telefonda kalıyor.'
    '\n\nİndir: $downloadUrl';

String _contact(String prefix) => contactEmail.isEmpty ? '' : '\n\n$prefix $contactEmail';

/// Uygulama içi gizlilik politikası (mağazadaki metnin kısa hâli).
final privacyPolicy = '''Netice, öğretmenlerin optik cevap kâğıtlarını okutup sonuçları analiz etmesi için tasarlanmıştır.

Çevrimdışı çalışır, veriler cihazınızda kalır
Netice internet bağlantısı olmadan çalışır. Girdiğiniz ve okuttuğunuz tüm bilgiler yalnızca uygulamayı kullandığınız telefonda (veya bilgisayarda), uygulamaya ait klasörde saklanır. Uygulama reklam göstermez, hesap açmayı zorunlu tutmaz ve hiçbir veriyi geliştiriciye ya da üçüncü kişilere göndermez.

İsteğe bağlı Google hesabı
Ayarlar > Hesap bölümünden dilerseniz Google hesabınızla giriş yapıp yedeğinizi kendi Google Drive alanınıza kaydedebilirsiniz. Bu özellik yalnızca siz açtığınızda internete bağlanır; yedek, Drive'ınızda yalnızca Netice'nin görebildiği gizli uygulama klasöründe tutulur ve geliştiriciye ulaşmaz. Kullanmazsanız uygulama tamamen çevrimdışı kalır.

Tutulan bilgiler
Öğrenci adı, soyadı, okul numarası ve sınıfı; sınav adı, tarihi, cevap anahtarı ve kazanımları; okutulan kâğıtlardaki işaretler, puanlar ve istatistikler; okul ve öğretmen bilgileri. Bu bilgiler yalnızca bu cihazda, uygulamaya ait klasörde saklanır; hiçbir sunucuya yüklenmez.

Kamera ve fotoğraflar
Kamera yalnızca siz izin verdiğinizde, cevap kâğıtlarını okumak için kullanılır. Görüntüler cihazda işlenir; fotoğrafların kendisi saklanmaz ve gönderilmez.

Paylaşım ve yedek
Rapor, liste ve yedek dosyalarını paylaşmayı siz seçersiniz. Paylaştığınız dosya, seçtiğiniz uygulamanın (e-posta, bulut, yazıcı) kurallarına tabidir. Yedek dosyaları öğrenci bilgisi içerir; güvenli bir yerde saklayın.

Toplanmayan veriler
Konum, rehber, cihaz kimliği, kullanım istatistiği, çökme raporu ve reklam kimliği toplanmaz.

Silme
Öğrenci, sınav ve kâğıtları tek tek ya da Ayarlar > "Tüm verileri sil" ile bir seferde silebilirsiniz; otomatik yedekleri de birlikte silmeyi seçebilirsiniz. Google Drive yedeği kullanıyorsanız onu da Ayarlar > Hesap bölümünden silebilirsiniz. Uygulama kaldırıldığında tüm veriler cihazdan silinir.${_contact('İletişim:')}''';

/// KVKK aydınlatma metni.
final kvkkNotice = '''6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında bilgilendirme

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
Öğrenciler ve velileri KVKK m. 11'deki haklarını veri sorumlusu olan öğretmene veya okula başvurarak kullanır.${_contact('Uygulama ile ilgili sorular:')}''';
