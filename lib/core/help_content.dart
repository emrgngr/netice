/// Uygulama içi kullanma kılavuzu ve sık sorulan sorular.
library;

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

const guideSections = <GuideSection>[
  GuideSection('Başlarken', 'start', [
    GuideTopic('Okul bilgilerini girin', [
      'Ana ekrandaki dişli simgesine (Ayarlar) dokunun.',
      '"Okul bilgileri"ni açın; il, ilçe, okul adı, ders, öğretmen ve müdür adını yazın.',
      '"Resmi yazı başlığı" açıksa tüm PDF raporların başında T.C. / Kaymakamlık / Müdürlük başlığı ve sonunda imza alanı çıkar.',
    ]),
    GuideTopic('Öğrencileri ekleyin', [
      'Alttaki "Sınıflar" sekmesine geçin.',
      'Tek tek eklemek için "+" düğmesini, toplu eklemek için "Excel aktar"ı kullanın.',
      'Excel dosyasında "Okul No, Adı, Soyadı, Sınıf" sütunları olması yeterlidir. e-Okul\'dan aldığınız liste de doğrudan okunur.',
    ], tip: 'Okul numarası doğru girilirse kâğıtlar öğrenciyle kendiliğinden eşleşir.'),
    GuideTopic('Örnek verileri silin', [
      'Uygulama ilk açılışta örnek bir sınıf ve sınav gösterir.',
      'Kendi verilerinizle çalışmaya başlamadan önce Ayarlar > "Örnek verileri sil" ile temizleyin.',
    ]),
  ]),
  GuideSection('Sınav hazırlama', 'exam', [
    GuideTopic('Yeni sınav oluşturun', [
      'Ana ekranda "Yeni sınav"a dokunun.',
      'Sınav adı, sınıf, tarih, soru sayısı ve şık sayısını seçin.',
      'Cevap anahtarını şıklara dokunarak girin ya da "Fotoğraftan oku" ile doldurulmuş anahtar formunu okutun.',
    ]),
    GuideTopic('Puanlama ayarları', [
      'Sınav ekranında sağ üstteki ayar simgesine dokunun.',
      'Tam puan, geçme puanı ve "kaç yanlış bir doğruyu götürür" ayarlanabilir.',
      'Bir soruyu iptal edebilir, birden çok doğru cevap verebilir, sorulara farklı puan ve kazanım kodu yazabilirsiniz.',
    ]),
    GuideTopic('Klasik (açık uçlu) sorular', [
      'Sınav ayarlarında "Klasik sorular" kartından soru ekleyin ve her birinin puanını yazın.',
      'Test kısmı kalan puana göre hesaplanır. Örnek: 100 puanlık sınavda 2 klasik soru 20\'şer puansa test 60 puan üzerinden değerlendirilir.',
      'Kâğıtları okuttuktan sonra sınav ekranındaki "Klasik puan gir" ile her öğrencinin puanını yazın.',
    ]),
    GuideTopic('A/B kitapçık', [
      'Sınav ayarlarında "Kitapçık türü"nü açın ve B kitapçığındaki soru sırasını girin (veya "Karışık sıra öner").',
      'B kitapçığı alan öğrenci formunda B\'yi işaretler; uygulama cevapları kendiliğinden A sırasına çevirir.',
    ]),
  ]),
  GuideSection('Form yazdırma', 'print', [
    GuideTopic('Optik formu yazdırın', [
      'Sınav ekranında "Form yazdır"a dokunun.',
      '"İsimli öğrenci formları" her öğrenci için adı ve numarası basılı bir sayfa üretir; "Boş öğrenci formu" ile istediğiniz kadar boş kâğıt alırsınız.',
      'A4 kâğıda, ölçeklendirme yapmadan (gerçek boyut / %100) yazdırın.',
    ], tip: 'Formun sol kenarındaki kareler makine kodudur (barkod). Sınavı ve öğrenciyi tanıtır; üzerine yazmayın.'),
    GuideTopic('Cevap anahtarı formu', [
      '"Cevap anahtarı" seçeneği doğru cevapları işaretlenmiş bir form ve okunaklı bir liste verir.',
      '"Boş cevap anahtarı formu"nu elle doldurup Sınav ayarlarındaki "Anahtarı fotoğraftan oku" ile uygulamaya aktarabilirsiniz.',
    ]),
  ]),
  GuideSection('Kâğıt okutma', 'scan', [
    GuideTopic('Kamerayla seri okuma', [
      'Sınav ekranında "Okut"a dokunun.',
      'Kâğıdı düz bir zemine koyun; dört köşedeki siyah kareler ekranda görünsün.',
      'Kâğıt tanınınca uygulama kendiliğinden çeker, sesli/titreşimli onay verir ve bir sonraki kâğıdı bekler. Kâğıtları sırayla değiştirmeniz yeterli.',
    ], tip: 'Gölge düşürmemeye çalışın; gün ışığı veya tavan ışığı en iyisidir.'),
    GuideTopic('Fotoğraf veya PDF\'ten okuma', [
      'Bilgisayarda "PDF / tarama yükle" ile tarayıcıdan aldığınız çok sayfalı PDF\'i veya fotoğrafları seçin.',
      'Her sayfa ayrı bir kâğıt olarak okunur.',
    ]),
    GuideTopic('Kontrol ve düzeltme', [
      'Okunan bir kâğıda dokunun; işaretlenen şıklar görünür.',
      'Belirsiz (iki şık işaretli veya çok silik) sorular sarı uyarıyla gösterilir; dokunarak düzeltebilirsiniz.',
      'Eşleşmeyen kâğıtta öğrenciyi listeden seçin.',
    ]),
  ]),
  GuideSection('Sonuçlar ve raporlar', 'report', [
    GuideTopic('Sınav raporu', [
      'Sınav ekranındaki "Analiz" bölümünde ortalama, başarı dağılımı, soru analizi ve kazanım başarısı görünür.',
      '"Sınav raporu" tüm bunları resmi formatta, yazdırılabilir şekilde verir.',
    ]),
    GuideTopic('Öğrenci karnesi ve veliye gönderme', [
      'Sonuç listesinde bir öğrenciye dokunun.',
      '"Karneyi önizle" ile PDF karnesini görün, "Karneyi veliye gönder" ile WhatsApp, e-posta veya başka bir uygulamayla paylaşın.',
      'Tüm sınıfın karnelerini tek PDF olarak almak için sınav ekranındaki "Öğrenci karnesi"ni kullanın.',
    ]),
    GuideTopic('Excel ve e-Okul', [
      '"Excel" tüm sonuçları, soru ve kazanım ayrıntılarıyla Excel\'in açabildiği bir dosyaya kaydeder.',
      '"e-Okul listesi" okul numarasına göre sıralı, tam sayıya yuvarlanmış puanları verir; e-Okul\'a not girerken yanınızda açık tutun.',
    ]),
    GuideTopic('Dönem raporu', [
      'Ana ekrandaki "Dönem raporu"nu açın; sınıfı ve dönemi seçin.',
      'Dahil edilecek sınavları işaretleyin ve gerekirse ağırlık verin (1×, 2×, 3×).',
      '"Not çizelgesi" dönem sonu notlarını, "Kazanım karneleri" her öğrencinin dönem boyunca kazanım başarısını verir.',
    ]),
    GuideTopic('Şube karşılaştırması', [
      'Aynı sınavı birden çok şubede yaptıysanız ana ekrandaki "Şube karşılaştırması" şubeleri yan yana gösterir.',
    ]),
  ]),
  GuideSection('Verileriniz', 'data', [
    GuideTopic('Yedekleme', [
      'Netice çevrimdışı çalışır; verilerinizi yalnızca bu telefonda (veya bilgisayarda) saklar, internete göndermez.',
      'Uygulama her gün kendiliğinden bir yedek alır (son 14 gün).',
      'Telefon değiştirirken veya bilgisayara geçerken Ayarlar > "Yedeği dosyaya kaydet" ile yedek alın, yeni cihazda "Yedekten geri yükle" ile açın.',
    ], tip: 'Uygulamayı silmeden önce mutlaka yedeği dosyaya kaydedin; aksi hâlde veriler silinir.'),
  ]),
];

const faqs = <Faq>[
  Faq('Okutma', 'Kâğıt okunmuyor, ne yapmalıyım?',
      'Dört köşedeki siyah karelerin görüntüde tam göründüğünden emin olun. Kâğıdı düz bir zemine koyun, gölge ve parlamayı önleyin, telefonu kâğıda paralel tutun. Kâğıt buruşuksa düzeltin.'),
  Faq('Okutma', 'Kurşun kalem mi, tükenmez kalem mi kullanılmalı?',
      'Koyu yumuşak kurşun kalem (2B) en iyi sonucu verir. Tükenmez ve keçeli kalem de okunur. Daireyi taşırmadan tamamen doldurmak yeterlidir.'),
  Faq('Okutma', 'Öğrenci yanlış şıkkı silip başkasını işaretlemiş. Ne olur?',
      'İyi silinen işaretler boş sayılır. Silgi izi koyu kalırsa uygulama o soruyu "belirsiz" diye sarıyla gösterir; kâğıda dokunup düzeltebilirsiniz.'),
  Faq('Okutma', 'Kâğıt yanlış öğrenciyle eşleşti.',
      'Kâğıda dokunun ve doğru öğrenciyi listeden seçin. Eşleşme okul numarasına göre yapılır; öğrencinin numarayı doğru kodladığından ve listedeki numaranın doğru olduğundan emin olun.'),
  Faq('Okutma', 'Formlar barkodlu mu?',
      'Evet. Formun sol kenarındaki kare dizisi makine kodudur. Hangi sınava ve hangi öğrenciye ait olduğunu taşır; başka sınavın kâğıdı okutulursa uygulama bunu fark edip doğru sınava kaydeder.'),
  Faq('Okutma', 'Bir kâğıdı iki kez okuttum.',
      'Aynı öğrenciye ait ikinci okuma eskisinin yerine geçer; çift kayıt oluşmaz.'),
  Faq('Formlar', 'Formu fotokopiyle çoğaltabilir miyim?',
      'Evet. Fotokopinin küçültülmemiş (%100) ve köşe karelerinin net olması yeterlidir. İsimli formlar yerine boş öğrenci formunu çoğaltıp öğrencilerin numaralarını kodlamasını isteyebilirsiniz.'),
  Faq('Formlar', 'Kaç soruya kadar form hazırlanabilir?',
      'Bir sınavda 5 ile 100 arasında soru olabilir; sorular 4 veya 5 şıklıdır.'),
  Faq('Puanlama', 'Yanlışlar doğruyu götürüyor mu?',
      'Varsayılan olarak hayır. Sınav ayarlarında "3 yanlış 1 doğruyu götürür" gibi bir kural seçebilirsiniz.'),
  Faq('Puanlama', 'Hatalı bir soruyu iptal edersem ne olur?',
      'İptal edilen soru kimsenin puanına katılmaz; puanlar kalan sorulara göre yeniden hesaplanır. Okutulmuş kâğıtları yeniden okutmanız gerekmez.'),
  Faq('Puanlama', 'Cevap anahtarında hata yaptım, kâğıtları yeniden mi okutmalıyım?',
      'Hayır. Anahtarı düzeltin; tüm sonuçlar anında yeniden hesaplanır.'),
  Faq('Puanlama', 'Klasik soru puanları nasıl eklenir?',
      'Sınav ayarlarında klasik soruları tanımlayın, kâğıtları okutun, ardından "Klasik puan gir" ekranından her öğrencinin puanını yazın. Eksik puan kalırsa sonuç ekranında uyarı görünür.'),
  Faq('Raporlar', 'Raporlarda okul adım görünmüyor.',
      'Ayarlar > Okul bilgileri ekranından okul adını ve diğer bilgileri girin. "Resmi yazı başlığı" açıksa tüm PDF\'lerde resmi başlık çıkar.'),
  Faq('Raporlar', 'Karneyi veliye nasıl gönderirim?',
      'Sonuç listesinde öğrenciye dokunun ve "Karneyi veliye gönder"i seçin. Açılan paylaşım menüsünden WhatsApp, e-posta veya istediğiniz uygulamayı seçin; hazır bir mesaj da eklenir.'),
  Faq('Raporlar', 'Dönem sonu notu nasıl hesaplanıyor?',
      'Seçtiğiniz sınavların puanları 100 üzerinden alınır ve verdiğiniz ağırlıklarla ortalaması hesaplanır. Öğrencinin girmediği sınav ortalamaya katılmaz. Dönem notu, ortalamanın tam sayıya yuvarlanmış hâlidir.'),
  Faq('Raporlar', 'Notları e-Okul\'a otomatik aktarabilir miyim?',
      'e-Okul dışarıdan otomatik veri girişine izin vermez. "e-Okul listesi" numara sırasına göre hazırlandığı için notları elle girmek birkaç dakika sürer.'),
  Faq('Veriler', 'Verilerim nerede saklanıyor?',
      'Yalnızca bu cihazda, uygulamanın kendi klasöründe. Hiçbir veri internete gönderilmez; bu nedenle KVKK açısından da güvenlidir. Yalnızca isteğe bağlı Google Drive yedeğini açarsanız yedek, kendi Google hesabınıza kaydedilir.'),
  Faq('Veriler', 'Telefonu değiştirirsem verilerim ne olur?',
      'Eski telefonda Ayarlar > "Yedeği dosyaya kaydet" ile yedek alın, dosyayı yeni cihaza aktarın ve "Yedekten geri yükle"yi seçin.'),
  Faq('Veriler', 'Telefon ve bilgisayar birbirini görüyor mu?',
      'Hayır, her cihazın verisi ayrıdır. Bir cihazdaki yedeği diğerine geri yükleyerek verileri taşıyabilirsiniz.'),
  Faq('Veriler', 'Yanlışlıkla bir şeyi sildim.',
      'Ayarlar > Yedekleme bölümündeki otomatik yedekler listesinden, silmeden önceki günün yedeğini "Geri yükle" ile açabilirsiniz.'),
  Faq('Genel', 'İnternet gerekiyor mu?',
      'Hayır. Netice tamamen çevrimdışı çalışır ve tüm veriler telefonunuzda kalır. İnternet yalnızca isteğe bağlı Google Drive yedeği ve paylaşım için kullanılır.'),
];
