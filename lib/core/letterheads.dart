import 'models.dart';
import '../l10n/l10n.dart';

/// Türkiye'deki kurumlar için hazır resmi yazı başlığı örnekleri. Resmî
/// Yazışmalarda Uygulanacak Usul ve Esaslar Hakkında Yönetmelik (RG
/// 10.06.2020, 31151) md. 10: 1. satır "T.C.", 2. satır idarenin adı büyük
/// harfle, alt satırlar birimler ilk harfleri büyük. Taşra teşkilatında 2.
/// satır Valilik / Kaymakamlık; bağlı idarelerde 2. satır bağlı olunan idare.
/// Kurum adı ve birimler örnektir, kullanıcı değiştirir.
class HeaderPreset {
  final String label;

  /// Valilik / Kaymakamlık altından mı?
  final bool local;

  /// Valilik / Kaymakamlık altındaki müdürlük (il/ilçe ön eki otomatik).
  final String localUnit;

  /// Üst kurum (2. satır, local değilse).
  final String parent;
  final List<String> units;
  final String name;

  const HeaderPreset(this.label,
      {this.local = false, this.localUnit = SchoolInfo.defaultLocalUnit, this.parent = '', this.units = const [], this.name = ''});

  static List<HeaderPreset> of(InstitutionType t) => switch (t) {
        InstitutionType.school => [
            HeaderPreset(tr('MEB okulu (Valilik / Kaymakamlık > Millî Eğitim > Okul)'), local: true, name: 'Atatürk Anadolu Lisesi'),
            HeaderPreset(tr('Özel okul (Millî Eğitim Müdürlüğüne bağlı)'), local: true, name: 'Özel Bilgi Koleji'),
          ],
        InstitutionType.police => [
            HeaderPreset(tr('Polis Meslek Eğitim Merkezi (POMEM)'),
                parent: 'Polis Akademisi Başkanlığı', name: 'Ankara Polis Meslek Eğitim Merkezi Müdürlüğü'),
            HeaderPreset(tr('Polis Meslek Yüksekokulu (PMYO)'),
                parent: 'Polis Akademisi Başkanlığı', name: 'Ankara Polis Meslek Yüksekokulu Müdürlüğü'),
            HeaderPreset(tr('Polis Akademisi fakülte / enstitü'),
                parent: 'Polis Akademisi Başkanlığı', name: 'Güvenlik Bilimleri Fakültesi Dekanlığı'),
            HeaderPreset(tr('Emniyet Genel Müdürlüğü birimi'),
                parent: 'Emniyet Genel Müdürlüğü', name: 'Personel Dairesi Başkanlığı'),
            HeaderPreset(tr('İl Emniyet Müdürlüğü (Valilik altında)'),
                local: true, localUnit: 'Emniyet Müdürlüğü', name: 'Eğitim Şube Müdürlüğü'),
          ],
        InstitutionType.military => [
            HeaderPreset(tr('Harp okulu (Millî Savunma Üniversitesi)'),
                parent: 'Millî Savunma Üniversitesi Rektörlüğü', name: 'Kara Harp Okulu Dekanlığı'),
            HeaderPreset(tr('Astsubay meslek yüksekokulu (MSÜ)'),
                parent: 'Millî Savunma Üniversitesi Rektörlüğü', name: 'Kara Astsubay Meslek Yüksekokulu Müdürlüğü'),
            HeaderPreset(tr('Kuvvet komutanlığı eğitim birliği (MSB)'),
                parent: 'Millî Savunma Bakanlığı', units: const ['Kara Kuvvetleri Komutanlığı'], name: 'Eğitim ve Doktrin Komutanlığı'),
            HeaderPreset(tr('Jandarma ve Sahil Güvenlik Akademisi'),
                parent: 'Jandarma ve Sahil Güvenlik Akademisi Başkanlığı', name: 'Jandarma Astsubay Meslek Yüksekokulu Müdürlüğü'),
          ],
        InstitutionType.university => [
            HeaderPreset(tr('Fakülte'), parent: 'Ankara Üniversitesi Rektörlüğü', name: 'Eğitim Bilimleri Fakültesi Dekanlığı'),
            HeaderPreset(tr('Fakülte bölümü'),
                parent: 'Ankara Üniversitesi Rektörlüğü',
                units: const ['Mühendislik Fakültesi Dekanlığı'],
                name: 'Bilgisayar Mühendisliği Bölüm Başkanlığı'),
            HeaderPreset(tr('Meslek yüksekokulu'),
                parent: 'Ankara Üniversitesi Rektörlüğü', name: 'Sağlık Hizmetleri Meslek Yüksekokulu Müdürlüğü'),
          ],
        InstitutionType.course => [
            HeaderPreset(tr('Halk eğitimi merkezi'), local: true, name: 'Halk Eğitimi Merkezi Müdürlüğü'),
            HeaderPreset(tr('Özel kurs (Millî Eğitim Müdürlüğüne bağlı)'), local: true, name: 'Özel Bilgi Kursu Müdürlüğü'),
            HeaderPreset(tr('Bağımsız kurs (başlıkta yalnız kurum adı)'), parent: '', name: 'Bilgi Eğitim Merkezi'),
          ],
        InstitutionType.other => [
            HeaderPreset(tr('Bakanlık birimi'),
                parent: 'Millî Eğitim Bakanlığı', name: 'Öğretmen Yetiştirme ve Geliştirme Genel Müdürlüğü'),
            HeaderPreset(tr('Belediye'),
                parent: 'Ankara Büyükşehir Belediyesi Başkanlığı', name: 'İnsan Kaynakları ve Eğitim Dairesi Başkanlığı'),
            HeaderPreset(tr('Valilik altındaki il müdürlüğü'),
                local: true, localUnit: 'Sağlık Müdürlüğü', name: 'Eğitim Birimi'),
          ],
      };

  /// Valilik / Kaymakamlık altındaki müdürlük için seçenekler.
  static const localUnits = [
    'Millî Eğitim Müdürlüğü',
    'Emniyet Müdürlüğü',
    'Jandarma Komutanlığı',
    'Sağlık Müdürlüğü',
    'Gençlik ve Spor Müdürlüğü',
    'Aile ve Sosyal Hizmetler Müdürlüğü',
    'Afet ve Acil Durum Müdürlüğü',
  ];
}
