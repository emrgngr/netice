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
      tr('"Cevap bloğu ekle" ile her soru sütununu tanımlayın: ilk sorunun A şıkkına, sonra son sorunun son şıkkına dokunun. Aradaki daireler kendiliğinden çizilir.'),
      tr('Öğrenci numarası bölümü varsa "Numara bloğu ekle" ile ilk basamağın 0\'ına ve son basamağın 9\'una dokunun.'),
      tr('Dolu bir formun fotoğrafıyla "Bu fotoğrafla dene"ye basın; yeşil daireler doğru yerlerdeyse kaydedin.'),
      tr('Sınav ayarları > "Form türü"nden şablonu seçin. Okutma, Netice formundaki gibi çalışır.'),
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
    GuideTopic(tr('Dönem raporu'), [
      tr('Ana ekrandaki "Dönem raporu"nu açın; sınıfı ve dönemi seçin.'),
      tr('Dahil edilecek sınavları işaretleyin ve gerekirse ağırlık verin (1×, 2×, 3×).'),
      tr('"Not çizelgesi" dönem sonu notlarını, "Kazanım karneleri" her öğrencinin dönem boyunca kazanım başarısını verir.'),
    ]),
    GuideTopic(tr('Sınıf sınıf analiz'), [
      tr('Aynı sınavı birden çok şubede yaptıysanız ana ekrandaki "Sınıf sınıf analiz" şubeleri yan yana gösterir.'),
      tr('Öne çıkanlar, genel ortalamaya göre fark, geçme ve katılım oranı, özet tablo ve soru soru doğru oranları herkese açıktır.'),
      tr('Pro ile her şubenin puan yayılımı, başarı düzeyleri, doğru / yanlış / boş dağılımı, en çok ayrışan sorular ve sınıf birincileri de görünür.'),
    ]),
    GuideTopic(tr('Genel istatistik'), [
      tr('Ana ekrandaki "Genel istatistik" tüm sınıfların ve sınava giren tüm öğrencilerin sonuçlarını bir arada gösterir.'),
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
      tr('Bir sınavda 5 ile 100 arasında soru olabilir; sorular 4 veya 5 şıklıdır.')),
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
      tr('Evet. Profil > Kurum bilgileri ekranında kurum türünü seçin (üniversite, Polis Akademisi/PMYO/POMEM, askerî okul, kurs…). Başlık, amir ve öğretmen unvanları ile grup adı (sınıf, bölük, takım, grup) buna göre gelir; hepsini değiştirebilirsiniz. Başka ülkelerde "Türkiye resmi yazı biçimi"ni kapatın.')),
  Faq(tr('Raporlar'), tr('Karneyi veliye nasıl gönderirim?'),
      tr('Sonuç listesinde öğrenciye dokunun ve "Karneyi veliye gönder"i seçin. Açılan paylaşım menüsünden WhatsApp, e-posta veya istediğiniz uygulamayı seçin; hazır bir mesaj da eklenir.')),
  Faq(tr('Raporlar'), tr('Dönem sonu notu nasıl hesaplanıyor?'),
      tr('Seçtiğiniz sınavların puanları 100 üzerinden alınır ve verdiğiniz ağırlıklarla ortalaması hesaplanır. Öğrencinin girmediği sınav ortalamaya katılmaz. Dönem notu, ortalamanın tam sayıya yuvarlanmış hâlidir.')),
  Faq(tr('Raporlar'), tr('Notları e-Okul\'a otomatik aktarabilir miyim?'),
      tr('e-Okul dışarıdan otomatik veri girişine izin vermez. "e-Okul listesi" numara sırasına göre hazırlandığı için notları elle girmek birkaç dakika sürer.')),
  Faq(tr('Soru bankası'), tr('Soru bankası internet gerektirir mi?'),
      tr('Hayır. Sorular, notlar, görseller ve kitapçıklar yalnızca bu cihazda saklanır; internet olmadan çalışır. Yalnızca isteğe bağlı "Nottan soru üret" özelliği internet kullanır.')),
  Faq(tr('Soru bankası'), tr('Ders notumdan otomatik soru üretebilir miyim?'),
      tr('Evet. Notu PDF, Word, fotoğraf ya da elle ekleyin; notu açıp "Bu nottan soru üret"e dokunun. Yapay zekâ çoktan seçmeli sorular, doğru cevaplar ve kısa çözümler önerir; kontrol edip beğendiklerinizi bankaya eklersiniz. İnternet gerekir. Ücretsiz sürümde {0} soruluk deneme hakkı, Netice Pro\'da ayda {1} soru vardır.', [20, 300])),
  Faq(tr('Soru bankası'), tr('Kitaptaki soruları yazmadan ekleyebilir miyim?'),
      tr('Evet. "PDF ya da fotoğraftan kes" ile sayfayı açıp soruları dikdörtgenle seçin; her biri görsel olarak bankaya girer. Doğru cevabı seçmeniz yeterli.')),
  Faq(tr('Soru bankası'), tr('Kitapçıklar arasında şıklar da karışıyor mu?'),
      tr('İsterseniz. "Şıkları karıştır" açıksa B ve sonraki kitapçıklarda şıkların yeri değişir; "Hepsi / hiçbiri" gibi son şıklar yerinde kalır. Okuma ve puanlama bunu kendiliğinden hesaba katar.')),
  Faq(tr('Soru bankası'), tr('Bankamı meslektaşımla paylaşabilir miyim?'),
      tr('Kütüphane menüsündeki "Banka paketini paylaş" ile .netbank dosyası oluşturun; meslektaşınız "Banka paketi aç" ile kendi bankasına ekler. Paylaştığınız içeriğin telif hakkı size ait olmalıdır.')),
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
      tr('Evet. Uygulamayı kurduğunuz andan itibaren 14 gün boyunca tüm Pro özellikleri ücretsizdir; kart bilgisi istenmez ve süre bitince ücret çekilmez. Kalan gün sayısını Ayarlar > Netice Pro bölümünde görebilirsiniz.')),
  Faq(tr('Netice Pro'), tr('Aboneliğimi nasıl iptal ederim?'),
      tr('Google Play > Profil > Ödemeler ve abonelikler > Abonelikler bölümünden Netice Pro\'yu seçip iptal edin. Abonelik dönem sonuna kadar geçerli kalır. Ayarlar > Netice Pro > "Aboneliği yönet" de sizi aynı sayfaya götürür.')),
  Faq(tr('Netice Pro'), tr('Telefonu değiştirdim, Pro\'m ne olacak?'),
      tr('Aynı Google hesabıyla girdiğiniz yeni telefonda Ayarlar > Netice Pro > "Satın alımları geri yükle"ye dokunun.')),
  Faq(tr('Genel'), tr('İnternet gerekiyor mu?'),
      tr('Hayır. Netice tamamen çevrimdışı çalışır ve tüm veriler telefonunuzda kalır. İnternet yalnızca isteğe bağlı Google Drive yedeği ve paylaşım için kullanılır.')),
];
