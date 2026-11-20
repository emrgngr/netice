import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/letterheads.dart';
import 'package:netice/core/models.dart';

/// Resmî Yazışmalarda Uygulanacak Usul ve Esaslar Hakkında Yönetmelik md. 10
/// örneklerine göre başlık satırları.
void main() {
  test('il merkezindeki okul: Valilik > İl Millî Eğitim > Okul', () {
    const s = SchoolInfo(province: 'Ankara', district: 'Merkez', name: 'atatürk anadolu lisesi', turkishFormat: true);
    expect(s.letterhead, ['T.C.', 'ANKARA VALİLİĞİ', 'İl Millî Eğitim Müdürlüğü', 'Atatürk Anadolu Lisesi Müdürlüğü']);
  });

  test('ilçedeki okul: Kaymakamlık > İlçe Millî Eğitim > Okul; büyük harfle yazılan ad düzeltilir', () {
    const s = SchoolInfo(province: 'Ordu', district: 'Fatsa', name: 'DUMLUPINAR İLKOKULU', turkishFormat: true);
    expect(s.letterhead, ['T.C.', 'FATSA KAYMAKAMLIĞI', 'İlçe Millî Eğitim Müdürlüğü', 'Dumlupınar İlkokulu Müdürlüğü']);
  });

  test('müdürlük satırı kapatılabilir, ara birim eklenebilir', () {
    const s = SchoolInfo(district: 'Çankaya', name: 'Ali Lisesi Müdürlüğü', localUnit: '', turkishFormat: true);
    expect(s.letterhead, ['T.C.', 'ÇANKAYA KAYMAKAMLIĞI', 'Ali Lisesi Müdürlüğü']);
  });

  test('il emniyet müdürlüğü (yönetmelik örneği)', () {
    const s = SchoolInfo(
        type: InstitutionType.police,
        province: 'Erzurum',
        localHeader: true,
        localUnit: 'Emniyet Müdürlüğü',
        name: 'Eğitim Şube Müdürlüğü',
        turkishFormat: true);
    expect(s.letterhead, ['T.C.', 'ERZURUM VALİLİĞİ', 'İl Emniyet Müdürlüğü', 'Eğitim Şube Müdürlüğü']);
  });

  test('üniversite: Rektörlük > Fakülte > Bölüm', () {
    const s = SchoolInfo(
        type: InstitutionType.university,
        parent: 'Hacettepe Üniversitesi Rektörlüğü',
        units: ['Edebiyat Fakültesi Dekanlığı'],
        name: 'Tarih Bölüm Başkanlığı',
        turkishFormat: true);
    expect(s.letterhead,
        ['T.C.', 'HACETTEPE ÜNİVERSİTESİ REKTÖRLÜĞÜ', 'Edebiyat Fakültesi Dekanlığı', 'Tarih Bölüm Başkanlığı']);
  });

  test('POMEM ve harp okulu; kısaltmalar korunur', () {
    const p = SchoolInfo(
        type: InstitutionType.police,
        parent: 'Polis Akademisi Başkanlığı',
        name: 'Ankara POMEM Müdürlüğü',
        turkishFormat: true);
    expect(p.letterhead, ['T.C.', 'POLİS AKADEMİSİ BAŞKANLIĞI', 'Ankara POMEM Müdürlüğü']);
    const m = SchoolInfo(
        type: InstitutionType.military,
        parent: 'Millî Savunma Üniversitesi Rektörlüğü',
        name: 'kara harp okulu dekanlığı',
        turkishFormat: true);
    expect(m.letterhead, ['T.C.', 'MİLLÎ SAVUNMA ÜNİVERSİTESİ REKTÖRLÜĞÜ', 'Kara Harp Okulu Dekanlığı']);
  });

  test('bağlaçlar küçük kalır', () {
    expect(SchoolInfo.titleCase('JANDARMA VE SAHİL GÜVENLİK AKADEMİSİ'), 'Jandarma ve Sahil Güvenlik Akademisi');
    expect(SchoolInfo.titleCase('İnsan Kaynakları ve Eğitim Dairesi Başkanlığı'),
        'İnsan Kaynakları ve Eğitim Dairesi Başkanlığı');
  });

  test('diğer ülkeler: T.C. yok, yer bilgisi altta', () {
    const s = SchoolInfo(
        name: 'Goethe Gymnasium', parent: 'Land Berlin', district: 'Berlin', country: 'Deutschland', turkishFormat: false);
    expect(s.letterhead.first, 'LAND BERLIN');
    expect(s.letterhead, isNot(contains('T.C.')));
    expect(s.letterhead.last, contains('DEUTSCHLAND'));
  });

  test('tüm hazır örnekler T.C. ile başlayan en az üç satır verir', () {
    for (final t in InstitutionType.values) {
      for (final h in HeaderPreset.of(t)) {
        final s = SchoolInfo(
            type: t,
            province: 'Ankara',
            district: 'Çankaya',
            localHeader: h.local,
            localUnit: h.localUnit,
            parent: h.parent,
            units: h.units,
            name: h.name,
            turkishFormat: true);
        expect(s.letterhead.first, 'T.C.');
        expect(s.letterhead.length, greaterThanOrEqualTo(h.parent.isEmpty && !h.local ? 2 : 3), reason: h.label);
      }
    }
  });

  test('kaydedilip açılınca başlık ayarları korunur', () {
    const s = SchoolInfo(name: 'X', localHeader: false, localUnit: '', units: ['A', 'B']);
    final j = SchoolInfo.fromJson(s.toJson());
    expect(j.localHeader, false);
    expect(j.localUnit, '');
    expect(j.units, ['A', 'B']);
  });
}
