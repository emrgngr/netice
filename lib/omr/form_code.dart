import 'form_layout.dart';

/// Formun sol kenarındaki makine kodu: kâğıdın hangi sınava, hangi öğrenciye
/// ve hangi kitapçığa ait olduğunu taşır. Okuma motoru bu şeridi aynı
/// köşe kareleriyle bulur; QR okuyucuya ya da internete gerek yoktur.
///
/// Şerit 44 küçük kareden oluşur (dolu = 1):
///   0       başlangıç (her zaman 1)
///   1..16   sınav kodu (16 bit)
///   17..36  öğrenci numarası (20 bit; tamamı 1 = boş form)
///   37      kitapçığın en düşük biti (A, C, E, G = 0; B, D, F, H = 1)
///   38..42  sağlama (5 bit)
///   43      bitiş (her zaman 1)
///
/// Kitapçığın üst iki biti (C ve sonrası) sınav kodunun en üst iki bitine
/// XOR'lanır. Okurken sınav kodu bilinen sınavlarla karşılaştırılırken bu
/// iki bit ayrıca çözülür ([resolve]). A ve B'de bu bitler 0 olduğundan
/// eski basılmış formlar aynen okunur; sağlama hiç değişmez.
class FormCode {
  /// Sınav kodu. [decode] ile çözülen kodda kitapçığın üst bitlerini de
  /// taşıyabilir; gerçek sınav ve kitapçık için [resolve] kullanılır.
  final int examCode;
  final int? studentNumber;

  /// Kitapçık (0 = A, 1 = B, 2 = C…). [decode] ile çözülen kodda yalnızca
  /// en düşük bit bilinir; tamamı [resolve] ile bulunur.
  final int booklet;

  const FormCode({required this.examCode, this.studentNumber, this.booklet = 0});

  static const cells = 44;
  static const cellSize = 3.0;
  static const _noStudent = 0xFFFFF;

  /// Kare [i]'nin merkezi (mm).
  static Pt cell(int i) => Pt(15, 27 + i * 5.5);

  /// Sınav kimliğinden 16 bitlik kısa kod (FNV-1a).
  static int examCodeOf(String examId) {
    var h = 0x811c9dc5;
    for (final c in examId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return (h ^ (h >> 16)) & 0xFFFF;
  }

  /// CRC-5 (x⁵ + x² + 1): tek ve çift bit hatalarını yakalar.
  static int _check(List<bool> b) {
    var crc = 0x1F;
    for (var i = 1; i <= 37; i++) {
      final top = ((crc >> 4) & 1) ^ (b[i] ? 1 : 0);
      crc = (crc << 1) & 0x1F;
      if (top == 1) crc ^= 0x05;
    }
    return crc;
  }

  List<bool> encode() {
    final n = studentNumber;
    final sn = n == null || n < 0 || n >= _noStudent ? _noStudent : n;
    final b = List<bool>.filled(cells, false);
    b[0] = true;
    final k = booklet.clamp(0, 7);
    final field = (examCode ^ ((k >> 1) << 14)) & 0xFFFF;
    for (var i = 0; i < 16; i++) {
      b[1 + i] = (field >> (15 - i)) & 1 == 1;
    }
    for (var i = 0; i < 20; i++) {
      b[17 + i] = (sn >> (19 - i)) & 1 == 1;
    }
    b[37] = k & 1 == 1;
    final c = _check(b);
    for (var i = 0; i < 5; i++) {
      b[38 + i] = (c >> (4 - i)) & 1 == 1;
    }
    b[43] = true;
    return b;
  }

  /// Okunan bitlerden kodu çözer; şerit yoksa ya da hatalıysa null.
  static FormCode? decode(List<bool> b) {
    if (b.length != cells || !b[0] || !b[43]) return null;
    var c = 0;
    for (var i = 0; i < 5; i++) {
      c = (c << 1) | (b[38 + i] ? 1 : 0);
    }
    if (c != _check(b)) return null;
    // Tamamen dolu ya da boş şerit kod değildir (karalama, gölge).
    final ones = b.where((x) => x).length;
    if (ones > 40) return null;
    var exam = 0, sn = 0;
    for (var i = 0; i < 16; i++) {
      exam = (exam << 1) | (b[1 + i] ? 1 : 0);
    }
    for (var i = 0; i < 20; i++) {
      sn = (sn << 1) | (b[17 + i] ? 1 : 0);
    }
    return FormCode(
      examCode: exam,
      studentNumber: sn == _noStudent ? null : sn,
      booklet: b[37] ? 1 : 0,
    );
  }

  /// Okunan kod [expectedExamCode] sınavına aitse, sınav kodu ve kitapçığı
  /// tam olarak çözülmüş kodu döndürür; başka sınavınsa null.
  FormCode? resolve(int expectedExamCode) {
    final d = (examCode ^ expectedExamCode) & 0xFFFF;
    if (d & 0x3FFF != 0) return null;
    return FormCode(
      examCode: expectedExamCode,
      studentNumber: studentNumber,
      booklet: (d >> 14) * 2 + (booklet & 1),
    );
  }

  @override
  String toString() => 'FormCode(exam: $examCode, student: $studentNumber, booklet: $booklet)';
}
