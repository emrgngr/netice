// Classroom / Moodle aktarımı önizlemesi: flutter test tool/aktarim_preview_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/classroom.dart';
import 'package:netice/core/grade_export.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/grade_export_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

class _Fake extends ClassroomService {
  final List<LmsStudent> roster;
  _Fake(this.roster);
  @override
  Future<List<ClassroomCourse>> courses() async =>
      const [ClassroomCourse('c1', 'Matematik', '9-A'), ClassroomCourse('c2', 'Matematik', '9-B')];
  @override
  Future<List<LmsStudent>> students(String courseId) async => roster;
  @override
  Future<ClassroomSendResult> send({
    required AppStore store,
    required Exam exam,
    required ClassroomCourse course,
    required List<GradeRow> rows,
    required Map<String, String?> match,
    bool publish = false,
  }) async =>
      ClassroomSendResult(match.values.where((v) => v != null).length, match.values.where((v) => v == null).length, 'w1', null);
}

void main() {
  testWidgets('aktarım ekranları', (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('aktarim')));
    store
      ..googleEmail = 'ogretmen@okul.k12.tr'
      ..googleName = 'Ayşe Öğretmen';
    final exam = store.exams.firstWhere((e) => e.id == 'demo_exam');
    final rows = gradeRows(store.resultsOf(exam), store.studentById);
    // Classroom listesi: çoğu aynı adla, ikisi farklı yazılmış (elle seçilir).
    ClassroomService.instance = _Fake([
      for (final (i, g) in rows.indexed)
        LmsStudent('u$i', i == 3 ? '${g.student.firstName[0]}. ${g.student.lastName}' : (i == 7 ? g.student.firstName : g.student.fullName.toUpperCase()),
            ''),
    ]);
    Widget app(Widget home) => StoreScope(
        store: store, child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home));

    await shot(tester, app(Builder(builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(exam.name)),
          body: Center(child: FilledButton(onPressed: () => openGradeExport(ctx, exam), child: const Text('aç'))),
        ))), const Size(390, 760), 'aktarim_1_menu', then: () async {
      await tester.tap(find.text('aç'));
    });
    await shot(tester, app(ClassroomExportScreen(examId: exam.id)), const Size(390, 1400), 'aktarim_2_classroom');
    await shot(tester, app(ClassroomExportScreen(examId: exam.id)), const Size(390, 760), 'aktarim_3_gonderildi', then: () async {
      await tester.tap(find.byIcon(Icons.send_rounded));
    });
  });
}
