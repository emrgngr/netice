import 'dart:convert';
import 'dart:math' as math;

import '../l10n/l10n.dart';
import '../omr/template.dart';
import 'models.dart';
import 'store.dart';

/// Ortak sınav: bir öğretmen (ör. zümre başkanı) sınavı hazırlar ve dosya
/// olarak paylaşır. Diğer öğretmenler dosyayı kendi şubelerine ekler, kendi
/// kâğıtlarını okur ve sonuç dosyasını geri gönderir. Hazırlayan öğretmen
/// sonuçları içe aldığında tüm şubeler tek raporda birleşir.
///
/// Her şey dosyayla taşınır (WhatsApp, e-posta, USB…); internet hesabı ya da
/// sunucu gerekmez, veriler kurumdan dışarı çıkmaz.
class CommonExamFile {
  static const examKind = 'netice-ortak-sinav';
  static const resultsKind = 'netice-ortak-sonuc';
  static const extension = 'netice';
}

/// İçe alınan sonuç dosyasının özeti.
class CommonImportSummary {
  final String examName;
  final String className;
  final int students;
  final int sheets;
  const CommonImportSummary(this.examName, this.className, this.students, this.sheets);
}

String _newId(String prefix) {
  final r = math.Random();
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 20).toRadixString(36)}';
}

/// Sınavı ortak sınav yapar (gerekirse kimlik verir) ve güncel hâlini döndürür.
Exam makeCommon(AppStore store, Exam exam) {
  if (exam.isCommon) return exam;
  final e = exam.copyWith(commonId: _newId('ortak'));
  store.upsertExam(e);
  return e;
}

/// [exam]'ın [className] şubesindeki karşılığı. Başka şube istenirse sınav
/// ortak sınava çevrilir ve o şube için aynı anahtarla bir kopya açılır
/// (zaten varsa o kullanılır). Böylece her şubenin formu kendi sınavının
/// makine kodunu taşır ve okutulan kâğıt doğru şubeye kaydedilir.
Exam examForClass(AppStore store, Exam exam, String className) {
  if (exam.className == className) return exam;
  final base = makeCommon(store, exam);
  final existing = store.exams.where((e) => e.commonId == base.commonId && e.className == className).firstOrNull;
  if (existing != null) return existing;
  final e = base.copyWith(id: _newId('exam'), className: className);
  store.upsertExam(e);
  return e;
}

/// Diğer öğretmenlere gönderilecek ortak sınav dosyası (cevap anahtarı,
/// kitapçıklar, puanlama; öğrenci verisi yok).
String exportCommonExam(AppStore store, Exam exam) {
  final e = makeCommon(store, exam);
  final tpl = e.templateId == null ? null : store.templates.where((t) => t.id == e.templateId).firstOrNull;
  return const JsonEncoder.withIndent(' ').convert({
    'app': 'netice',
    'kind': CommonExamFile.examKind,
    'v': 1,
    'commonId': e.commonId,
    'from': store.school.teacher.trim(),
    'institution': store.reportSchool.name.trim(),
    'exam': e.toJson(),
    if (tpl != null) 'template': tpl.toJson(),
  });
}

Map<String, dynamic> _parse(String text, String kind) {
  try {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['app'] == 'netice' && j['kind'] == kind && j['commonId'] is String && j['exam'] is Map) return j;
  } catch (_) {}
  throw FormatException(kind == CommonExamFile.examKind
      ? tr('Bu dosya bir Netice ortak sınav dosyası değil.')
      : tr('Bu dosya bir Netice ortak sınav sonuç dosyası değil.'));
}

/// Dosyanın türü: ortak sınav, sonuç ya da tanınmayan (null).
String? commonFileKind(String text) {
  try {
    final j = jsonDecode(text);
    if (j is Map && j['app'] == 'netice') return j['kind'] as String?;
  } catch (_) {}
  return null;
}

/// Ortak sınav dosyasındaki sınavın adı (içe almadan önce göstermek için).
String commonExamName(String text) => '${(_parse(text, CommonExamFile.examKind)['exam'] as Map)['name']}';

/// Ortak sınavı [className] şubesi için ekler. Aynı şube için zaten varsa
/// mevcut sınavı döndürür (iki kez eklenmez).
Exam importCommonExam(AppStore store, String text, String className) {
  final j = _parse(text, CommonExamFile.examKind);
  final commonId = j['commonId'] as String;
  final existing =
      store.exams.where((e) => e.commonId == commonId && e.className == className).firstOrNull;
  if (existing != null) return existing;
  if (j['template'] is Map) {
    final t = FormTemplate.fromJson((j['template'] as Map).cast<String, dynamic>());
    if (!store.templates.any((x) => x.id == t.id)) store.saveTemplate(t);
  }
  final src = Exam.fromJson((j['exam'] as Map).cast<String, dynamic>());
  final e = src.copyWith(id: _newId('exam'), className: className, commonId: commonId);
  store.upsertExam(e);
  return e;
}

/// Bu şubenin sonuçlarını hazırlayan öğretmene gönderilecek dosya.
/// Kâğıt görüntüleri gönderilmez; yalnızca işaretler, puanlar ve öğrenci listesi.
String exportCommonResults(AppStore store, Exam exam) {
  final e = makeCommon(store, exam);
  final sheets = store.sheetsOf(e.id);
  final ids = {for (final s in sheets) s.studentId};
  final students = [for (final s in store.students) if (ids.contains(s.id)) s];
  return const JsonEncoder.withIndent(' ').convert({
    'app': 'netice',
    'kind': CommonExamFile.resultsKind,
    'v': 1,
    'commonId': e.commonId,
    'from': store.school.teacher.trim(),
    'className': e.className,
    'exam': e.toJson(),
    // Veli telefonu cihazdan çıkmaz.
    'students': [for (final s in students) s.copyWith(parentPhone: '').toJson()..remove('parentPhone')],
    'sheets': [
      for (final s in sheets)
        Sheet(
          examId: s.examId,
          studentId: s.studentId,
          answers: s.answers,
          booklet: s.booklet,
          openScores: s.openScores,
          readNumber: s.readNumber,
          readName: s.readName,
        ).toJson(),
    ],
  });
}

/// Bir şubenin sonuçlarını içe alır. O şubenin bu sınavdaki eski kâğıtları
/// yenileriyle değiştirilir; öğrenciler şube + numaraya göre eşleştirilir,
/// yoksa eklenir. Aynı dosyayı iki kez almak kopya oluşturmaz.
CommonImportSummary importCommonResults(AppStore store, String text) {
  final j = _parse(text, CommonExamFile.resultsKind);
  final commonId = j['commonId'] as String;
  final src = Exam.fromJson((j['exam'] as Map).cast<String, dynamic>());
  final className = '${j['className'] ?? src.className}';
  var exam = store.exams.where((e) => e.commonId == commonId && e.className == className).firstOrNull;
  if (exam == null) {
    exam = src.copyWith(id: _newId('exam'), className: className, commonId: commonId);
    store.exams.add(exam);
  }

  final incoming = [
    for (final s in (j['students'] as List? ?? const [])) Student.fromJson((s as Map).cast<String, dynamic>())
  ];
  final idMap = <String, String>{};
  var added = 0;
  for (final s in incoming) {
    final match = store.students
        .where((x) => x.className == s.className && s.number.isNotEmpty && x.number == s.number)
        .firstOrNull ??
        store.students.where((x) => x.id == s.id).firstOrNull;
    if (match != null) {
      idMap[s.id] = match.id;
    } else {
      final id = _newId('stu');
      store.students.add(Student(id: id, firstName: s.firstName, lastName: s.lastName, number: s.number, className: s.className));
      idMap[s.id] = id;
      added++;
    }
  }

  final examId = exam.id;
  final newSheets = [
    for (final raw in (j['sheets'] as List? ?? const []))
      () {
        final s = Sheet.fromJson((raw as Map).cast<String, dynamic>());
        return Sheet(
          examId: examId,
          studentId: s.studentId == null ? null : idMap[s.studentId] ?? s.studentId,
          answers: s.answers,
          booklet: s.booklet,
          openScores: s.openScores,
          readNumber: s.readNumber,
          readName: s.readName,
        );
      }(),
  ];
  store.sheets.removeWhere((s) => s.examId == examId);
  store.sheets.addAll(newSheets);
  store.commit();
  return CommonImportSummary(exam.name, className, added, newSheets.length);
}

/// Ortak sınavlar: kimlik → şubelerdeki kopyaları (şube adına göre sıralı).
Map<String, List<Exam>> commonGroups(AppStore store) {
  final g = <String, List<Exam>>{};
  for (final e in store.exams) {
    if (e.commonId != null) g.putIfAbsent(e.commonId!, () => []).add(e);
  }
  for (final v in g.values) {
    v.sort((a, b) => a.className.compareTo(b.className));
  }
  return g;
}
