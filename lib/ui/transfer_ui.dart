import 'package:material_ui/material_ui.dart';

import '../core/insights.dart';
import '../core/mastery.dart';
import '../core/misconceptions.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../core/progress.dart';
import '../core/store.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'pro_screen.dart';
import 'report_preview_screen.dart';

/// Bir öğrencinin devir dosyası verisi.
TransferEntry transferEntryOf(AppStore store, Student s, List<MasteryOutcome> classMastery) {
  final h = historyOf(store, s);
  final mis = <String, int>{};
  for (final x in h) {
    final sheet = x.standing.result.sheet;
    for (final m in Misconceptions.ofSheet(x.exam, sheet)) {
      mis[m] = (mis[m] ?? 0) + 1;
    }
  }
  return TransferEntry(
    s,
    h,
    studentDevelopmentNote(h),
    outcomeSummary(h),
    {
      for (final o in classMastery)
        if ((o.students[s.id] ?? const []).isNotEmpty) o.code: Mastery.statusOf(o.students[s.id]!),
    },
    [for (final e in mis.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2)),
  );
}

/// Yıl sonu öğrenci devir dosyasını açar: [studentId] verilirse tek öğrenci,
/// yoksa sınıfın hepsi.
Future<void> openTransferFile(BuildContext context, String className, {String? studentId}) async {
  if (!await requirePro(context, ProFeature.transferFile) || !context.mounted) return;
  final store = StoreScope.of(context);
  final students = [
    for (final s in store.studentsOf(className))
      if (studentId == null || s.id == studentId) s,
  ]..sort((a, b) => a.fullName.compareTo(b.fullName));
  await ReportPreviewScreen.open(
    context,
    title: tr('Öğrenci devir dosyası'),
    fileName: studentId == null ? '${className}_devir_dosyasi.pdf' : '${students.firstOrNull?.fullName ?? ''}_devir_dosyasi.pdf',
    build: () {
      final mastery = Mastery.of(store, className);
      return buildTransferPdf(
        entries: [for (final s in students) transferEntryOf(store, s, mastery)],
        school: store.reportSchool,
        period: tr('{0} öğretim yılı', [SchoolInfo.academicYear(DateTime.now())]),
      );
    },
  );
}
