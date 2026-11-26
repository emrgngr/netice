// Notları öğrenme yönetim sistemlerine aktarma: Moodle (CSV dosyası) ve
// Google Classroom (öğrenci eşleştirme). Ağ işi classroom.dart'tadır; bu
// dosya yalnızca hesap yapar, böylece testlerle denetlenebilir.

import 'package:csv/csv.dart';

import '../l10n/l10n.dart';
import 'models.dart';
import 'scoring.dart';

/// Aktarılacak tek öğrencinin notu.
class GradeRow {
  final Student student;
  final Result result;
  const GradeRow(this.student, this.result);

  double get score => result.score;
}

/// Sınavın, bir öğrenciyle eşleşmiş sonuçları (okul numarasına göre sıralı).
List<GradeRow> gradeRows(List<Result> results, Map<String, Student> students) {
  final out = <GradeRow>[];
  for (final r in results) {
    final s = students[r.sheet.studentId];
    if (s != null) out.add(GradeRow(s, r));
  }
  out.sort((a, b) {
    final x = int.tryParse(a.student.number), y = int.tryParse(b.student.number);
    if (x != null && y != null && x != y) return x.compareTo(y);
    return a.student.fullName.compareTo(b.student.fullName);
  });
  return out;
}

/// Puanı LMS'lerin beklediği biçimde yazar: ondalık nokta, en çok 2 basamak.
String gradeText(double v) {
  final r = (v * 100).round() / 100;
  return r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

/// Kısa geri bildirim: "D 15 · Y 3 · B 2 · Net 14".
String gradeFeedback(Result r) =>
    '${tr('D')} ${r.correct} · ${tr('Y')} ${r.wrong} · ${tr('B')} ${r.blank} · ${tr('Net')} ${gradeText(r.net)}';

/// Moodle "Notlar > İçe aktar > CSV dosyası" için not dosyası.
///
/// Moodle sütun adlarını kendisi eşleştirmez; öğretmen içe aktarırken
/// "Eşleştir: Kimlik numarası → useridnumber" ya da "E-posta adresi →
/// useremail" seçer. Bu yüzden İngilizce standart başlıklar kullanılır ve
/// her iki kimlik de dosyada bulunur. Ayırıcı virgül, ondalık nokta, UTF-8.
String moodleCsv(Exam exam, List<GradeRow> rows) {
  final column = exam.name.trim().isEmpty ? 'Netice' : exam.name.trim();
  final data = <List<String>>[
    ['ID number', 'Email address', 'First name', 'Last name', column, '$column (feedback)'],
    for (final g in rows)
      [
        g.student.number,
        g.student.email,
        g.student.firstName,
        g.student.lastName,
        gradeText(g.score),
        gradeFeedback(g.result),
      ],
  ];
  return Csv(fieldDelimiter: ',', lineDelimiter: '\n').encode(data);
}

/// Google Classroom'daki bir öğrenci.
class LmsStudent {
  final String id;
  final String name;
  final String email;
  const LmsStudent(this.id, this.name, this.email);
}

/// Adları karşılaştırmak için sadeleştirir: küçük harf, Türkçe ve aksanlı
/// harfler sade hâlde, noktalama yok, kelimeler sıralı (ad/soyad sırası
/// fark etmesin).
String nameKey(String s) {
  const from = 'çğıöşüâîûéèêëáàäãåíìïóòõúùñ';
  const to = 'cgiosuaiueeeeaaaaaiiiooouun';
  final buf = StringBuffer();
  for (final r in s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  final words = buf.toString().split(RegExp(r'[^a-z0-9Ѐ-ӿ؀-ۿ぀-ヿ㐀-鿿가-힯]+'))
    ..removeWhere((w) => w.isEmpty)
    ..sort();
  return words.join(' ');
}

/// Netice öğrencilerini Classroom öğrencileriyle eşleştirir: önce e-posta,
/// sonra ad soyad. Belirsiz ya da bulunamayanlar null kalır (öğretmen elle
/// seçer). Aynı Classroom öğrencisi iki kez kullanılmaz.
Map<String, String?> matchStudents(List<Student> ours, List<LmsStudent> theirs) {
  final out = <String, String?>{};
  final used = <String>{};
  final byMail = <String, List<LmsStudent>>{};
  final byName = <String, List<LmsStudent>>{};
  for (final t in theirs) {
    if (t.email.isNotEmpty) byMail.putIfAbsent(t.email.toLowerCase().trim(), () => []).add(t);
    byName.putIfAbsent(nameKey(t.name), () => []).add(t);
  }
  // E-posta eşleşmeleri önce; böylece ad benzerliği onları kapmaz.
  for (final s in ours) {
    final m = byMail[s.email.toLowerCase().trim()];
    if (s.email.isNotEmpty && m != null && m.length == 1 && used.add(m.first.id)) out[s.id] = m.first.id;
  }
  for (final s in ours) {
    if (out.containsKey(s.id)) continue;
    final m = byName[nameKey('${s.firstName} ${s.lastName}')]?.where((t) => !used.contains(t.id)).toList();
    if (m != null && m.length == 1) {
      used.add(m.first.id);
      out[s.id] = m.first.id;
    } else {
      out[s.id] = null;
    }
  }
  return out;
}
