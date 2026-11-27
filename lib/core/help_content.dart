/// Uygulama içi kullanma kılavuzu ve sık sorulan sorular.
library;

import '../l10n/l10n.dart';

class GuideTopic {
  final String title;
  final List<String> steps;
  final String? tip;
  const GuideTopic(this.title, this.steps, {this.tip});
}

class GuideSection {
  final String title;
  final String icon; // help_screen'de ikon adına çevrilir
  final List<GuideTopic> topics;
  const GuideSection(this.title, this.icon, this.topics);
}

class Faq {
  final String category;
  final String q;
  final String a;
  const Faq(this.category, this.q, this.a);
}

List<GuideSection> get guideSections => <GuideSection>[
  GuideSection(tr('Başlarken'), 'start', [
    GuideTopic(tr('Kurum bilgilerini girin'), [
      tr('Ana ekrandaki dişli simgesine (Ayarlar) dokunun.'),
      tr('"Kurum bilgileri"ni açın; kurum türünü (okul, üniversite, Polis Akademisi, askerî okul, kurs…) seçin, kurum adını, ders, öğretmen ve amir bilgilerini yazın.'),
      tr('"Resmi yazı başlığı" açıksa tüm PDF raporların başında kurumunuzun resmi başlığı ve sonunda imza alanı çıkar. Türkiye dışında "Türkiye resmi yazı biçimi"ni kapatın.'),
    ]),
    GuideTopic(tr('Öğrencileri ekleyin'), [
      tr('Alttaki "Sınıflar" sekmesine geçin.'),
      tr('Tek tek eklemek için "+" düğmesini, toplu eklemek için "Excel / PDF aktar"ı kullanın.'),
      tr('Excel dosyasında "Okul No, Adı, Soyadı, Sınıf" sütunları olması yeterlidir. e-Okul\'dan aldığınız liste de doğrudan okunur.'),
      tr('Excel\'in yeni (.xlsx) ve eski (.xls) dosyaları, LibreOffice (.ods), CSV, PDF ve Word listeleri okunur.'),
      tr('Bütün sınıflar tek dosyada olabilir: Excel\'in her sayfası ya da PDF\'teki her "9. Sınıf / A Şubesi" başlığı ayrı sınıfa yazılır. Sınıf, sayfanın adından da alınır (ör. 9-A).'),
    ], tip: tr('Okul numarası doğru girilirse kâğıtlar öğrenciyle kendiliğinden eşleşir.')),
    GuideTopic(tr('Örnek verileri silin'), [
      tr('Uygulama ilk açılışta örnek bir sınıf ve sınav gösterir.'),
      tr('Kendi verilerinizle çalışmaya başlamadan önce Ayarlar > "Örnek verileri sil" ile temizleyin.'),
    ]),
  ]),
  GuideSection(tr('Sınav hazırlama'), 'exam', [
    GuideTopic(tr('Yeni sınav oluşturun'), [
      tr('Ana ekranda "Yeni sınav"a dokunun.'),
      tr('Sınav adı, sınıf, tarih, soru sayısı ve şık sayısını seçin.'),
      tr('Cevap anahtarını şıklara dokunarak girin ya da "Fotoğraftan oku" ile doldurulmuş anahtar formunu okutun.'),
    ]),
    GuideTopic(tr('Puanlama ayarları'), [
      tr('Sınav ekranında sağ üstteki ayar simgesine dokunun.'),
      tr('Tam puan, geçme puanı ve "kaç yanlış bir doğruyu götürür" ayarlanabilir.'),
      tr('Bir soruyu iptal edebilir, birden çok doğru cevap verebilir, sorulara farklı puan ve kazanım kodu yazabilirsiniz.'),
    ]),
    GuideTopic(tr('Klasik (açık uçlu) sorular'), [
      tr('Sınav ayarlarında "Klasik sorular" kartından soru ekleyin ve her birinin puanını yazın.'),
      tr('Test kısmı kalan puana göre hesaplanır. Örnek: 100 puanlık sınavda 2 klasik soru 20\'şer puansa test 60 puan üzerinden değerlendirilir.'),
      tr('Kâğıtları okuttuktan sonra sınav ekranındaki "Klasik puan gir" ile her öğrencinin puanını yazın.'),
    ]),
    GuideTopic(tr('Kitapçık türleri (A, B, C…)'), [
      tr('Sınav ayarlarında "Kitapçık türü"nü açın ve kitapçık sayısını seçin (en fazla 8: A–H).'),
      tr('A dışındaki her kitapçık için soruların A\'daki numaralarını sırayla yazın (veya "Karışık sıra öner").'),
      tr('Öğrenci formunda kendi kitapçığını işaretler; uygulama cevapları kendiliğinden A sırasına çevirir ve doğru anahtarla puanlar.'),
    ]),
  ]),
  GuideSection(tr('Form yazdırma'), 'print', [
    GuideTopic(tr('Başka firma formu (yayınevi formu) kullanma'), [
      tr('Ayarlar > "Başka firma formları" > "Yeni şablon"a dokunun ve formun fotoğrafını seçin. Kâğıdı koyu bir zemine koyun; dört kenarı görünsün.'),
      tr('Netice formdaki cevap dairelerini, öğrenci numarasını ve kitapçık türünü kendisi bulur. Renkli halkalar dairelerin üstündeyse doğru bulunmuştur; soru numarası farklıysa bloğa dokunup ilk soru numarasını değiştirin.'),
      tr('Formda ad soyad harf alanı, TC kimlik no gibi ikinci bir numara alanı varsa onları da bulur. Numara listede yoksa öğrenci TC numarasından ya da kâğıttaki adından tanınır; harfler uygulamanın diline göre seçilir.'),
      tr('Yanlış bulunan bloğu kaldırıp "Cevap bloğu ekle" ile elle işaretleyin: ilk sorunun A şıkkına, sonra son sorunun son şıkkına dokunun.'),
      tr('Dolu bir formun fotoğrafıyla "Bu fotoğrafla dene"ye basın; yeşil daireler doğru yerlerdeyse kaydedin.'),
      tr('Sınav ayarları > "Form türü"nden şablonu seçin. Okutma, Netice formundaki gibi çalışır.'),
      tr('Şablonu paylaş düğmesiyle diğer öğretmenlere gönderin; onlar "Şablon dosyası aç" ile ekler, formu yeniden tanıtmaları gerekmez.'),
    ], tip: tr('Netice formu köşe kareleri sayesinde daha hızlı ve güvenilir okunur; mümkünse Netice formunu basın.')),
    GuideTopic(tr('Optik formu yazdırın'), [
      tr('Sınav ekranında "Form yazdır"a dokunun.'),
      tr('"İsimli öğrenci formları" her öğrenci için adı ve numarası basılı bir sayfa üretir; "Boş öğrenci formu" ile istediğiniz kadar boş kâğıt alırsınız.'),
      tr('A4 kâğıda, ölçeklendirme yapmadan (gerçek boyut / %100) yazdırın.'),
    ], tip: tr('Formun sol kenarındaki kareler makine kodudur (barkod). Sınavı ve öğrenciyi tanıtır; üzerine yazmayın.')),
    GuideTopic(tr('Cevap anahtarı formu'), [
      tr('"Cevap anahtarı" seçeneği doğru cevapları işaretlenmiş bir form ve okunaklı bir liste verir.'),
      tr('"Boş cevap anahtarı formu"nu elle doldurup Sınav ayarlarındaki "Anahtarı fotoğraftan oku" ile uygulamaya aktarabilirsiniz.'),
    ]),
  ]),
  GuideSection(tr('Kâğıt okutma'), 'scan', [
    GuideTopic(tr('Kamerayla seri okuma'), [
      tr('Sınav ekranında "Okut"a dokunun.'),
      tr('Kâğıdı düz bir zemine koyun; dört köşedeki siyah kareler ekranda görünsün.'),
      tr('Kâğıt tanınınca uygulama kendiliğinden çeker, sesli/titreşimli onay verir ve bir sonraki kâğıdı bekler. Kâğıtları sırayla değiştirmeniz yeterli.'),
      tr('Aynı kâğıdı yanlışlıkla iki kez okutursanız ikinci okuma eklenmez. Aynı numarayla farklı cevaplı bir kâğıt gelirse "Kontrol" listesine alınır ve numarası en yakın öğrenciler önerilir.'),
      tr('Sonuç ekranında kâğıdı okutulmamış öğrenciler ayrıca listelenir.'),
      tr('Okuma gecikirse ekranın üstündeki sarı ampullü ipucuna bakın: "Biraz yaklaşın", "Telefonu kâğıda paralel tutun", "Işık yansıyor", "Ortam karanlık · feneri açın" gibi.'),
    ], tip: tr('Gölge düşürmemeye çalışın; gün ışığı veya tavan ışığı en iyisidir.')),
    GuideTopic(tr('Fotoğraf veya PDF\'ten okuma'), [
      tr('Bilgisayarda "PDF / tarama yükle" ile tarayıcıdan aldığınız çok sayfalı PDF\'i veya fotoğrafları seçin.'),
      tr('Her sayfa ayrı bir kâğıt olarak okunur.'),
      tr('Telefonda okutma ekranındaki "Galeriden" ile önceden çektiğiniz fotoğrafların hepsini birden seçebilirsiniz. Uygulama hepsini sırayla okur, ilerlemeyi gösterir ve sonunda kaç kâğıdın okunduğunu, hangilerinin kontrol beklediğini özetler.'),
      tr('"Yalnızca sorunlular" ile okunamayan veya kontrol bekleyen kâğıtları ayıklayabilirsiniz.'),
    ]),
    GuideTopic(tr('Kontrol ve düzeltme'), [
      tr('Okunan bir kâğıda dokunun; işaretlenen şıklar görünür.'),
      tr('Belirsiz (iki şık işaretli veya çok silik) sorular sarı uyarıyla gösterilir; dokunarak düzeltebilirsiniz.'),
      tr('Eşleşmeyen kâğıtta öğrenciyi listeden seçin.'),
    ]),
  ]),
  GuideSection(tr('Sonuçlar ve raporlar'), 'report', [
    GuideTopic(tr('Sınav raporu'), [
      tr('Sınav ekranındaki "Analiz" bölümünde ortalama, başarı dağılımı, soru analizi ve kazanım başarısı görünür.'),
      tr('"Sınav raporu" tüm bunları resmi formatta, yazdırılabilir şekilde verir.'),
    ]),
    GuideTopic(tr('Öğrenci karnesi ve veliye gönderme'), [
      tr('Sonuç listesinde bir öğrenciye dokunun.'),
      tr('"Karneyi önizle" ile PDF karnesini görün, "Karneyi veliye gönder" ile WhatsApp, e-posta veya başka bir uygulamayla paylaşın.'),
      tr('Tüm sınıfın karnelerini tek PDF olarak almak için sınav ekranındaki "Öğrenci karnesi"ni kullanın.'),
    ]),
    GuideTopic(tr('Excel ve e-Okul'), [
      tr('"Excel" tüm sonuçları, soru ve kazanım ayrıntılarıyla Excel\'in açabildiği bir dosyaya kaydeder.'),
      tr('"e-Okul listesi" okul numarasına göre sıralı, tam sayıya yuvarlanmış puanları verir; e-Okul\'a not girerken yanınızda açık tutun.'),
    ]),
    GuideTopic(tr('Dönem sonu raporu'), [
      tr('Ana ekrandaki "Dönem sonu raporu"nu açın; sınıfı ve dönemi seçin.'),
      tr('Dahil edilecek sınavları işaretleyin ve gerekirse ağırlık verin (1×, 2×, 3×).'),
      tr('"Not çizelgesi" dönem sonu notlarını, "Kazanım karneleri" her öğrencinin dönem boyunca kazanım başarısını verir.'),
    ]),
    GuideTopic(tr('Ülkenizin not sistemi'), [
      tr('Ayarlar > "Not sistemi"ni açın.'),
      tr('Hazır sistemlerden birini seçin (Türkiye 5\'li, üniversite AA–FF, ABD A–F, Almanya 1–6, Fransa 20 üzerinden ve diğerleri).'),
      tr('Listede yoksa "Kendim yazacağım" ile düzeylerin adını ve alt sınırını yazın (2–12 düzey).'),
      tr('Karneler, raporlar ve grafikler bu düzeylerle hazırlanır.'),
    ], tip: tr('Puanı 100 yerine 20 ya da 10 üzerinden vermek için Sınav ayarları > "Tam puan"ı değiştirin.')),
    GuideTopic(tr('Şube karşılaştırması'), [
      tr('Aynı sınavı birden çok şubede yaptıysanız ana ekrandaki "Şube karşılaştırması" şubeleri yan yana gösterir.'),
      tr('Öne çıkanlar, genel ortalamaya göre fark, geçme ve katılım oranı, özet tablo ve soru soru doğru oranları herkese açıktır.'),
      tr('Pro ile her şubenin puan yayılımı, başarı düzeyleri, doğru / yanlış / boş dağılımı, en çok ayrışan sorular ve sınıf birincileri de görünür.'),
    ]),
    GuideTopic(tr('Genel analiz'), [
      tr('Ana ekrandaki "Genel analiz" tüm sınıfların ve sınava giren tüm öğrencilerin sonuçlarını bir arada gösterir.'),
      tr('Üstten dönemi (tüm zamanlar, son 30 gün, son 90 gün) ve sınıfları seçerek daraltın.'),
      tr('Genel başarı, katılım, sınıf sıralaması, başarı düzeyleri ve sınav listesi herkese açıktır; Pro ile puan dağılımı, gelişim çizgileri, en başarılı, en çok gelişen ve desteğe ihtiyaç duyan öğrenciler ile kazanım özeti eklenir.'),
      tr('Sağ üstteki PDF düğmesiyle tüm istatistiği rapor olarak alabilirsiniz.'),
    ]),
  ]),
  GuideSection(tr('Soru bankası ve kitapçık'), 'library', [
    GuideTopic(tr('Soru bankasına soru ekleyin'), [
      tr('Alttaki "Kütüphane" sekmesini açın ve "Soru ekle"ye dokunun.'),
      tr('"Soru yaz" ile metni, şıkları, görseli ve çözümü tek tek girin; doğru şıkkın harfine dokunun.'),
      tr('"PDF ya da fotoğraftan kes" ile kitap veya deneme sayfasını açın, sorunun çevresine dikdörtgen çizin, doğru cevabı seçip "Soru olarak ekle"ye basın.'),
      tr('Çok sayıda soru için "Excel şablonunu indir"i doldurup "Excel\'den aktar" ile tek seferde ekleyin.'),
      tr('Her soruya ders, sınıf, konu ve kolay / orta / zor etiketi verin; süzgeçler ve otomatik seçim bunlarla çalışır.'),
    ], tip: tr('Banka tamamen bu cihazda saklanır. Başka cihaza ya da meslektaşınıza "Banka paketini paylaş" ile aktarabilirsiniz.')),
    GuideTopic(tr('Konu özeti ve hap bilgi ekleyin'), [
      tr('Kütüphane › Notlar sekmesinde "Not ekle"ye dokunun.'),
      tr('Hap bilgi kısa bir kural ya da formüldür; konu özeti daha uzun ders notudur.'),
      tr('Notu elle yazabilir, PDF / Word belgesinden aktarabilir ya da fotoğrafını çekebilirsiniz (telefonda fotoğraftaki yazı da okunur).'),
      tr('Notun konusunu sınavdaki konu adıyla aynı yazın; böylece analizde o konuda zayıf kalan öğrencilere önerilir.'),
    ]),
    GuideTopic(tr('Nottan soru üretin (yapay zekâ)'), [
      tr('Kütüphane › Notlar\'da bir notu açın ve "Bu nottan soru üret"e dokunun.'),
      tr('Soru sayısını, şık sayısını, zorluğu ve soru türlerini seçin. İlkokul notlarında "Çocuklar için (ilkokul)" kendiliğinden açılır.'),
      tr('Yapay zekâ sorular, doğru cevaplar ve kısa çözümler önerir. Her soruyu kontrol edin, gerekirse düzenleyin ve beğendiklerinizi bankaya ekleyin.'),
      tr('Bu özellik internet kullanır; notun metni yalnız soru üretmek için gönderilir ve saklanmaz.'),
    ], tip: tr('Ücretsiz denemede toplam 20 soru, Netice Pro\'da ayda 50, Pro + Yapay Zekâ\'da ayda 300 soru hakkınız vardır. Hak bitince ek soru paketi alabilirsiniz.')),
    GuideTopic(tr('Çocuklar için kitapçık (ilkokul)'), [
      tr('Kitapçık sihirbazının "Görünüm" adımında şablon olarak "Çocuk / İlkokul"u seçin.'),
      tr('İri yazı, renkli soru numaraları, A–B–C şıkları ve çocuklara uygun yönerge gelir.'),
      tr('30 soruya kadar cevaplar ilk sayfanın köşesindeki küçük kutuya işaretlenir ve telefonla okunur; ayrı optik form gerekmez.'),
      tr('İsimli cevap kartlarını sınav ekranındaki "Form yazdır" ile basabilirsiniz. Çocuk sınavlarının karnesi de yıldızlı, sade bir tasarımla çıkar.'),
    ]),
    GuideTopic(tr('Soru kitapçığı oluşturun'), [
      tr('Kütüphane › Kitapçıklar sekmesinde "Yeni kitapçık"a dokunun.'),
      tr('Soruları "Bankadan seç" ile tek tek ya da "Otomatik seç" ile sayı ve kolay / orta / zor oranı vererek seçin; sürükleyerek sıralayın.'),
      tr('"Görünüm" adımında resmi başlık, süre, yönerge, tek / iki sütun, yazı boyutu ve kâğıt boyutunu ayarlayın.'),
      tr('"Kitapçık" adımında A–H arası kitapçık sayısını, soruların ve şıkların karışmasını, puanlamayı ve cevap anahtarı, çözümlü kitapçık, hap bilgi eki gibi ekleri seçin.'),
      tr('"Önizleme"de PDF\'i yazdırın ya da paylaşın, sonra "Sınav oluştur" ile sınavı sınıflarınız için tek dokunuşla açın.'),
    ], tip: tr('"Sınav oluştur" cevap anahtarını, kitapçık sıralarını, karışan şıkları ve konuları kendisi girer. Optik formu sınav ekranındaki "Form yazdır" ile basın.')),
    GuideTopic(tr('Analiz ve hap bilgi önerileri'), [
      tr('Kütüphane › Analiz sekmesinde zorluk dağılımını ve hangi konuda kaç soru ve not olduğunu görürsünüz.'),
      tr('Bankadan yapılan sınavlar okutuldukça her sorunun gerçek zorluğu hesaplanır; etiketi yanlış olanları tek dokunuşla güncelleyebilirsiniz.'),
      tr('Sınav analizinde "Zayıf konular ve hap bilgiler" kartından sınıfa çalışma föyü (PDF) alabilirsiniz.'),
      tr('Öğrenci karnesinde "Çalışması gereken konular" bölümü, öğrencinin zayıf kaldığı konuların hap bilgileriyle otomatik dolar.'),
    ]),
  ]),
  GuideSection(tr('Netice Pro'), 'pro', [
    GuideTopic(tr('Planlar'), [
      tr('Profil > "Netice Pro"ya dokunun. Planlar ve güncel fiyatlar orada görünür.'),
      tr('Pro · yıllık: bütün raporlar, karneler, Drive yedeği, A–H kitapçıklar ve ayda 50 yapay zekâ sorusu.'),
      tr('Pro + Yapay Zekâ · yıllık: Pro\'nun hepsi ve ayda 300 yapay zekâ sorusu. Nottan sık soru üretenler için.'),
      tr('Sınav dönemi paketi: 3 ay Pro, tek seferlik ödeme, kendiliğinden yenilenmez.'),
    ], tip: tr('Okumak, sonuçlar ve Excel her zaman ücretsizdir. Yeni kurulumda 14 gün (Eylül\'de 30 gün) bütün Pro özellikleri ücretsiz denenir.')),
    GuideTopic(tr('Yapay zekâ soru hakkı ve ek paket'), [
      tr('Aylık soru hakkınız her ay yenilenir; kalan hakkınızı soru üretme ekranında görürsünüz.'),
      tr('Hakkınız bitince Netice Pro ekranındaki "Ek soru paketi" ile 200 soru alabilirsiniz. Ek paket tek seferliktir ve süresi dolmaz.'),
      tr('Önce aylık hak, o bitince ek paket kullanılır.'),
    ]),
    GuideTopic(tr('Kampanyalar ve fiyat güvencesi'), [
      tr('Okula dönüş (Eylül), Öğretmenler Günü (20–30 Kasım) ve karne dönemlerinde yıllık planlar ilk yıl indirimlidir. Kampanya varsa Netice Pro ekranının üstünde görünür.'),
      tr('Arkadaşınızın davet koduyla yıllık Pro ilk yıl %15 indirimli olur; siz davet ettiğinizde her arkadaşınız için 1 ay ek Pro kazanırsınız.'),
      tr('Fiyat güvencesi: abone olduğunuz fiyat, aboneliğiniz sürdükçe değişmez.'),
    ]),
    GuideTopic(tr('Okul / zümre paketi'), [
      tr('Aynı okuldan 5 ve daha fazla öğretmen birlikte alırsa her öğretmene Pro indirimli olur (5–9 öğretmen %25, 10–24 %35, 25–49 %45; 50 ve üzeri özel teklif).'),
      tr('Netice Pro ekranındaki "Okul / zümre paketi"ne dokunun, okul bilgilerinizi ve öğretmen sayısını girin, "Okulunuza teklif isteyin"e basın.'),
      tr('Teklif onaylanınca okulunuza bir kurum kodu verilir. Her öğretmen bu kodu Profil > "Kurum lisansı" ekranına girer.'),
    ]),
  ]),
  GuideSection(tr('Silme ve düzeltme'), 'fix', [
    GuideTopic(tr('Sınavları seçip silin'), [
      tr('Ana sayfayı aşağı kaydırın ve "Son sınavlar" bölümündeki "Seç ve sil"e dokunun. Bir sınav kartına uzun basarak da seçmeye başlayabilirsiniz.'),
      tr('Silmek istediğiniz sınavlara dokunun ya da "Tümünü seç"i kullanın.'),
      tr('Çöp kutusuna dokunup onaylayın. Öğrencileriniz ve sınıflarınız silinmez.'),
    ], tip: tr('Yanlışlıkla silerseniz altta beliren "Geri al" düğmesine 6 saniye içinde dokunun.')),
    GuideTopic(tr('Bir kâğıdı silin veya yeniden okutun'), [
      tr('Sonuçlar listesinde öğrenciye dokunun.'),
      tr('"Bu okumayı sil" yalnızca bu kâğıdı siler. Öğrenci kaydı kalır, kâğıdı yeniden okutabilirsiniz.'),
    ]),
    GuideTopic(tr('Kontrol ve düzeltme'), [
      tr('Okunan bir kâğıda dokunun; işaretlenen şıklar görünür.'),
      tr('Belirsiz (iki şık işaretli veya çok silik) sorular sarı uyarıyla gösterilir; dokunarak düzeltebilirsiniz.'),
      tr('Eşleşmeyen kâğıtta öğrenciyi listeden seçin.'),
    ]),
  ]),
  GuideSection(tr('Verileriniz'), 'data', [
    GuideTopic(tr('Yedekleme'), [
      tr('Netice çevrimdışı çalışır; verilerinizi yalnızca bu telefonda (veya bilgisayarda) saklar, internete göndermez.'),
      tr('Uygulama her gün kendiliğinden bir yedek alır (son 14 gün).'),
      tr('Telefon değiştirirken veya bilgisayara geçerken Ayarlar > "Yedeği dosyaya kaydet" ile yedek alın, yeni cihazda "Yedekten geri yükle" ile açın.'),
    ], tip: tr('Uygulamayı silmeden önce mutlaka yedeği dosyaya kaydedin; aksi hâlde veriler silinir.')),
    GuideTopic(tr('Verileri silme'), [
      tr('Tek bir öğrenciyi, sınavı veya kâğıdı kendi ekranından silebilirsiniz.'),
      tr('Okunan kâğıtların görüntüsü (İşaretli kâğıdı gör) yalnızca bu cihazda durur ve yedeğe eklenmez; sınavı sildiğinizde görüntüler de silinir.'),
      tr('Ayarlar > "Tüm verileri sil" bu cihazdaki bütün bilgileri siler; onay için "SİL" yazmanız istenir.'),
      tr('Google Drive yedeğini Ayarlar > Hesap > "Drive\'daki yedeği sil" ile kaldırabilirsiniz.'),
    ]),
  ]),
];

List<Faq> get faqs => <Faq>[
  Faq(tr('Okutma'), tr('Kâğıt okunmuyor, ne yapmalıyım?'),
      tr('Dört köşedeki siyah karelerin görüntüde tam göründüğünden emin olun. Kâğıdı düz bir zemine koyun, gölge ve parlamayı önleyin, telefonu kâğıda paralel tutun. Kâğıt buruşuksa düzeltin.')),
  Faq(tr('Okutma'), tr('Kurşun kalem mi, tükenmez kalem mi kullanılmalı?'),
      tr('Koyu yumuşak kurşun kalem (2B) en iyi sonucu verir. Tükenmez ve keçeli kalem de okunur. Daireyi taşırmadan tamamen doldurmak yeterlidir.')),
  Faq(tr('Okutma'), tr('Öğrenci yanlış şıkkı silip başkasını işaretlemiş. Ne olur?'),
      tr('İyi silinen işaretler boş sayılır. Silgi izi koyu kalırsa uygulama o soruyu "belirsiz" diye sarıyla gösterir; kâğıda dokunup düzeltebilirsiniz.')),
  Faq(tr('Okutma'), tr('Kâğıt yanlış öğrenciyle eşleşti.'),
      tr('Kâğıda dokunun ve doğru öğrenciyi listeden seçin. Eşleşme okul numarasına göre yapılır; öğrencinin numarayı doğru kodladığından ve listedeki numaranın doğru olduğundan emin olun.')),
  Faq(tr('Okutma'), tr('Formlar barkodlu mu?'),
      tr('Evet. Formun sol kenarındaki kare dizisi makine kodudur. Hangi sınava ve hangi öğrenciye ait olduğunu taşır; başka sınavın kâğıdı okutulursa uygulama bunu fark edip doğru sınava kaydeder.')),
  Faq(tr('Okutma'), tr('Bir kâğıdı iki kez okuttum.'),
      tr('Aynı öğrenciye ait ikinci okuma eskisinin yerine geçer; çift kayıt oluşmaz.')),
  Faq(tr('Formlar'), tr('Formu fotokopiyle çoğaltabilir miyim?'),
      tr('Evet. Fotokopinin küçültülmemiş (%100) ve köşe karelerinin net olması yeterlidir. İsimli formlar yerine boş öğrenci formunu çoğaltıp öğrencilerin numaralarını kodlamasını isteyebilirsiniz.')),
  Faq(tr('Formlar'), tr('Kaç soruya kadar form hazırlanabilir?'),
      tr('Bir sınavda 5 ile 100 arasında soru olabilir; sorular 2 ile 5 arasında şıklı olabilir.')),
  Faq(tr('Puanlama'), tr('Sınavda A ve B dışında C, D gibi kitapçıklar da var. Olur mu?'),
      tr('Evet. Sınav ayarları > Kitapçık türü bölümünden kitapçık sayısını 8\'e kadar (A–H) artırabilirsiniz. Her kitapçığın soru sırasını girdiğinizde formda o kadar kitapçık dairesi çıkar; her kâğıt kendi kitapçığının anahtarıyla puanlanır.')),
  Faq(tr('Puanlama'), tr('Yanlışlar doğruyu götürüyor mu?'),
      tr('Varsayılan olarak hayır. Sınav ayarlarında "3 yanlış 1 doğruyu götürür" gibi bir kural seçebilirsiniz.')),
  Faq(tr('Puanlama'), tr('Hatalı bir soruyu iptal edersem ne olur?'),
      tr('İptal edilen soru kimsenin puanına katılmaz; puanlar kalan sorulara göre yeniden hesaplanır. Okutulmuş kâğıtları yeniden okutmanız gerekmez.')),
  Faq(tr('Puanlama'), tr('Cevap anahtarında hata yaptım, kâğıtları yeniden mi okutmalıyım?'),
      tr('Hayır. Anahtarı düzeltin; tüm sonuçlar anında yeniden hesaplanır.')),
  Faq(tr('Puanlama'), tr('Klasik soru puanları nasıl eklenir?'),
      tr('Sınav ayarlarında klasik soruları tanımlayın, kâğıtları okutun, ardından "Klasik puan gir" ekranından her öğrencinin puanını yazın. Eksik puan kalırsa sonuç ekranında uyarı görünür.')),
  Faq(tr('Raporlar'), tr('Raporlarda kurumumun adı görünmüyor.'),
      tr('Profil > Kurum bilgileri ekranından kurum adını ve diğer bilgileri girin. "Resmi yazı başlığı" açıksa tüm PDF\'lerde resmi başlık çıkar.')),
  Faq(tr('Raporlar'), tr('Polis Akademisi, askerî okul ya da üniversitede kullanılabilir mi?'),
      tr('Evet. Profil > Kurum bilgileri ekranında kurum türünü seçin (üniversite, Polis Akademisi, askerî okul, kurs…). Başlık, amir ve öğretmen unvanları ile grup adı (sınıf, bölük, takım, grup) buna göre gelir; hepsini değiştirebilirsiniz. Başka ülkelerde "Türkiye resmi yazı biçimi"ni kapatın.')),
  Faq(tr('Raporlar'), tr('Ülkemin not sistemi farklı. Değiştirebilir miyim?'),
      tr('Evet. Ayarlar > "Not sistemi"nden hazır sistemlerden birini seçin ya da düzeylerin adını ve alt sınırlarını kendiniz girin. Karneler ve raporlar bu sisteme göre hazırlanır.')),
  Faq(tr('Raporlar'), tr('Karneyi veliye nasıl gönderirim?'),
      tr('Sonuç listesinde öğrenciye dokunun ve "Karneyi veliye gönder"i seçin. Açılan paylaşım menüsünden WhatsApp, e-posta veya istediğiniz uygulamayı seçin; hazır bir mesaj da eklenir.')),
  Faq(tr('Raporlar'), tr('Dönem sonu notu nasıl hesaplanıyor?'),
      tr('Seçtiğiniz sınavların puanları 100 üzerinden alınır ve verdiğiniz ağırlıklarla ortalaması hesaplanır. Öğrencinin girmediği sınav ortalamaya katılmaz. Dönem notu, ortalamanın tam sayıya yuvarlanmış hâlidir.')),
  Faq(tr('Raporlar'), tr('Notları e-Okul\'a otomatik aktarabilir miyim?'),
      tr('e-Okul dışarıdan otomatik veri girişine izin vermez. "e-Okul listesi" numara sırasına göre hazırlandığı için notları elle girmek birkaç dakika sürer.')),
  Faq(tr('Okuma'), tr('Kısa quiz formu nedir?'),
      tr('Form yazdır > "Kısa quiz formu" bir A4 kâğıda dört çeyrek A4 form basar (en fazla 20 soru). Kesik çizgiden kesip dağıtın; okuturken her kâğıdı tek tek çekin. Netice formun kısa mı tam mı olduğunu kendisi anlar. Köşedeki QR kod, telefon kamerasıyla okunduğunda kâğıdın hangi quize ve öğrenciye ait olduğunu gösterir.')),
  Faq(tr('Raporlar'), tr('Kişiye özel tekrar testi nasıl hazırlanır?'),
      tr('Sınav ekranında menüden "Kişiye özel tekrar testi"ni seçin. Her öğrenciye, yanlış yaptığı ya da boş bıraktığı soruların konusundan soru bankanızdaki benzer sorular seçilir; konunun hap bilgisi de eklenir. Sorularda konu ya da kazanım yazılı olmalı ve bankada o konudan sorular bulunmalıdır.')),
  Faq(tr('Raporlar'), tr('Bütün sınıfın karnesini velilere nasıl gönderirim?'),
      tr('Sınav ekranında menüden "Velilere toplu gönder"i seçin. "Sıradaki" düğmesi her öğrencinin karnesini hazır mesajla açar; WhatsApp\'ta veliyi seçip gönderin ve geri dönün. Veli telefonu kayıtlıysa WhatsApp sohbeti doğrudan açılır. Telefonları öğrenciyi düzenleyerek ya da Excel listesine "Veli Telefonu" sütunu ekleyerek girebilirsiniz.')),
  Faq(tr('Raporlar'), tr('Kazanım takip çizelgesi neyi gösterir?'),
      tr('Dönem raporunda "Kazanım takip çizelgesi", seçtiğiniz sınavlarda her kazanımın sınıf başarısını sınav sınav renkli olarak, dönem ortalamasını ve ilk sınavdan son sınava değişimi gösterir. İkinci bölümde her öğrencinin kazanımlardaki dönem başarısı yer alır.')),
  Faq(tr('Ortak sınav'), tr('Sonuçları dosya göndermeden toplayabilir miyim?'),
      tr('Evet, aynı Wi-Fi ağındaysanız. Sınavı hazırlayan öğretmen Ortak sınav > "Aynı Wi-Fi\'daki öğretmenlerle eşitle" > "Toplamaya başla"ya dokunur ve ekrandaki 4 haneli kodu söyler. Diğer öğretmenler aynı ekranda "Ara"ya dokunup kodu yazar: sonuçları gönderir ya da sınavı alır. İnternet gerekmez; veriler yalnızca okulun ağı içinde dolaşır.')),
  Faq(tr('Soru bankası'), tr('Kitapçığı Word\'de düzenleyebilir miyim?'),
      tr('Evet. Kitapçık oluşturucunun önizleme adımındaki "Word" düğmesi kitapçığı .docx belgesi olarak kaydeder; soruları, görselleri ve cevap anahtarını Word\'de değiştirebilirsiniz.')),
  Faq(tr('Soru bankası'), tr('Soru bankası internet gerektirir mi?'),
      tr('Hayır. Sorular, notlar, görseller ve kitapçıklar yalnızca bu cihazda saklanır; internet olmadan çalışır. Yalnızca isteğe bağlı "Nottan soru üret" özelliği internet kullanır.')),
  Faq(tr('Soru bankası'), tr('Ders notumdan otomatik soru üretebilir miyim?'),
      tr('Evet. Notu PDF, Word, fotoğraf ya da elle ekleyin; notu açıp "Bu nottan soru üret"e dokunun. Yapay zekâ çoktan seçmeli sorular, doğru cevaplar ve kısa çözümler önerir; kontrol edip beğendiklerinizi bankaya eklersiniz. İnternet gerekir. Ücretsiz denemede toplam {0} soru, Netice Pro\'da ayda {1}, Pro + Yapay Zekâ\'da ayda {2} soru hakkınız vardır.', [20, 50, 300])),
  Faq(tr('Soru bankası'), tr('İlkokul öğrencileri optik form doldurabilir mi?'),
      tr('Gerek yok. Kitapçık sihirbazında "Çocuk / İlkokul" şablonunu seçin; çocuklar cevaplarını ilk sayfanın köşesindeki küçük kutuya işaretler ve kutu telefonla okunur (30 soruya kadar).')),
  Faq(tr('Soru bankası'), tr('Kitaptaki soruları yazmadan ekleyebilir miyim?'),
      tr('Evet. "PDF ya da fotoğraftan kes" ile sayfayı açıp soruları dikdörtgenle seçin; her biri görsel olarak bankaya girer. Doğru cevabı seçmeniz yeterli.')),
  Faq(tr('Soru bankası'), tr('Kitapçıklar arasında şıklar da karışıyor mu?'),
      tr('İsterseniz. "Şıkları karıştır" açıksa B ve sonraki kitapçıklarda şıkların yeri değişir; "Hepsi / hiçbiri" gibi son şıklar yerinde kalır. Okuma ve puanlama bunu kendiliğinden hesaba katar.')),
  Faq(tr('Soru bankası'), tr('Bankamı meslektaşımla paylaşabilir miyim?'),
      tr('Kütüphane menüsündeki "Banka paketini paylaş" ile .netbank dosyası oluşturun; meslektaşınız "Banka paketi aç" ile kendi bankasına ekler. Paylaştığınız içeriğin telif hakkı size ait olmalıdır.')),
  Faq(tr('Soru bankası'), tr('Kütüphanenin depolama alanı ne kadar?'),
      tr('Sabit bir sınır yoktur; her şey cihazınızda saklanır ve sınırı cihazınızdaki boş alan belirler. Yalnız metin olan bir soru yaklaşık 1 KB, görselli bir soru 100–300 KB tutar; 1.000 görselli soru yaklaşık 150–300 MB eder. Kütüphanenin şu an ne kadar yer kapladığını Kütüphane > Analiz sekmesinin en altında görürsünüz.')),
  Faq(tr('Veriler'), tr('Verilerim nerede saklanıyor?'),
      tr('Yalnızca bu cihazda, uygulamanın kendi klasöründe. Hiçbir veri internete gönderilmez; bu nedenle KVKK açısından da güvenlidir. Yalnızca isteğe bağlı Google Drive yedeğini açarsanız yedek, kendi Google hesabınıza kaydedilir.')),
  Faq(tr('Veriler'), tr('Telefonu değiştirirsem verilerim ne olur?'),
      tr('Eski telefonda Ayarlar > "Yedeği dosyaya kaydet" ile yedek alın, dosyayı yeni cihaza aktarın ve "Yedekten geri yükle"yi seçin.')),
  Faq(tr('Veriler'), tr('Telefon ve bilgisayar birbirini görüyor mu?'),
      tr('Hayır, her cihazın verisi ayrıdır. Bir cihazdaki yedeği diğerine geri yükleyerek verileri taşıyabilirsiniz.')),
  Faq(tr('Veriler'), tr('Verilerimi nasıl silerim?'),
      tr('Ayarlar > "Tüm verileri sil" bu cihazdaki öğrenci, sınav, kâğıt ve okul bilgilerini siler. İsterseniz otomatik yedekleri de birlikte silebilirsiniz. Google Drive yedeği kullanıyorsanız Ayarlar > Hesap > "Drive\'daki yedeği sil" ile onu da kaldırabilirsiniz.')),
  Faq(tr('Veriler'), tr('Yanlışlıkla bir şeyi sildim.'),
      tr('Ayarlar > Yedekleme bölümündeki otomatik yedekler listesinden, silmeden önceki günün yedeğini "Geri yükle" ile açabilirsiniz.')),
  Faq(tr('Netice Pro'), tr('Netice ücretsiz mi?'),
      tr('Evet. Kâğıt okutma, sonuçlar, temel istatistikler, sonuç listesi ve Excel her zaman ücretsizdir. Dönem raporu, öğrenci ve kazanım karneleri, karneyi veliye gönderme, Google Drive yedeği, gelişmiş grafikler ve resmi yazı başlığı Netice Pro ile açılır.')),
  Faq(tr('Netice Pro'), tr('Ücretsiz deneme var mı?'),
      tr('Evet. Uygulamayı kurduğunuz andan itibaren 14 gün boyunca tüm Pro özellikleri ücretsizdir; kart bilgisi istenmez ve süre bitince ücret çekilmez. Eylül\'deki okula dönüş kampanyasında yeni kurulumlarda deneme 30 gündür. Kalan gün sayısını Profil > Netice Pro bölümünde görebilirsiniz.')),
  Faq(tr('Netice Pro'), tr('Aboneliğimi nasıl iptal ederim?'),
      tr('Google Play > Profil > Ödemeler ve abonelikler > Abonelikler bölümünden Netice Pro\'yu seçip iptal edin. Abonelik dönem sonuna kadar geçerli kalır. Profil > Netice Pro > "Aboneliği yönet" de sizi aynı sayfaya götürür. iPhone\'da Ayarlar > Apple hesabınız > Abonelikler bölümünü kullanın.')),
  Faq(tr('Netice Pro'), tr('Telefonu değiştirdim, Pro\'m ne olacak?'),
      tr('Aynı Google (ya da Apple) hesabıyla girdiğiniz yeni telefonda Profil > Netice Pro > "Satın alımları geri yükle"ye dokunun.')),
  Faq(tr('Netice Pro'), tr('Pro ile Pro + Yapay Zekâ arasındaki fark nedir?'),
      tr('İkisinde de bütün Pro özellikleri vardır. Fark yalnız yapay zekâ soru hakkındadır: Pro\'da ayda 50, Pro + Yapay Zekâ\'da ayda 300 soru. Nottan az soru üretiyorsanız Pro yeterlidir.')),
  Faq(tr('Netice Pro'), tr('Yapay zekâ soru hakkım bitti. Ne yapabilirim?'),
      tr('Hakkınız her ay yenilenir. Beklemek istemezseniz Netice Pro ekranından 200 soruluk ek paketi alabilirsiniz; ek paketin süresi dolmaz. Sık soru üretiyorsanız Pro + Yapay Zekâ\'ya geçmek daha ucuza gelir.')),
  Faq(tr('Netice Pro'), tr('Okulumuzdaki öğretmenler birlikte alırsa indirim var mı?'),
      tr('Evet. 5 ve daha fazla öğretmene okul / zümre paketiyle %45\'e varan indirim uygulanır. Netice Pro ekranındaki "Okul / zümre paketi"nden teklif isteyin; ödeme okul adına tek faturayla yapılır, öğretmenler kurum kodunu girer.')),
  Faq(tr('Netice Pro'), tr('Fiyat her yıl artacak mı?'),
      tr('Yeni abonelerin fiyatı yılda bir güncellenir. Abone olduğunuz fiyat ise aboneliğiniz sürdükçe değişmez.')),
  Faq(tr('Netice Pro'), tr('Kampanya ya da indirim oluyor mu?'),
      tr('Evet. Okula dönüş (Eylül), Öğretmenler Günü (20–30 Kasım) ve karne dönemlerinde yıllık planlar ilk yıl indirimlidir. Kampanya dönemindeyseniz Netice Pro ekranının üstünde görürsünüz.')),
  Faq(tr('Genel'), tr('İnternet gerekiyor mu?'),
      tr('Hayır. Netice tamamen çevrimdışı çalışır ve tüm veriler telefonunuzda kalır. İnternet yalnızca isteğe bağlı Google Drive yedeği ve paylaşım için kullanılır.')),
];
