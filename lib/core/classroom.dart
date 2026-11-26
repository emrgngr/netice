// Google Classroom'a not gönderme.
//
// Netice, öğretmenin seçtiği derste "Netice: <sınav adı>" adlı bir ödev
// açar (ya da daha önce açtığını kullanır) ve her öğrencinin notunu bu
// ödeve yazar. Classroom, yalnızca kendi açtığı ödevlerin notunu bir
// uygulamanın değiştirmesine izin verir; bu yüzden var olan bir ödeve
// değil, Netice'nin açtığı ödeve yazılır.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'google_auth.dart';
import 'grade_export.dart';
import 'models.dart';
import 'store.dart';

class ClassroomCourse {
  final String id;
  final String name;
  final String section;
  const ClassroomCourse(this.id, this.name, this.section);

  String get label => section.isEmpty ? name : '$name · $section';
}

class ClassroomException implements Exception {
  final String message;
  const ClassroomException(this.message);
  @override
  String toString() => message;
}

class ClassroomSendResult {
  final int sent;
  final int skipped;
  final String courseWorkId;
  final String? link;
  const ClassroomSendResult(this.sent, this.skipped, this.courseWorkId, this.link);
}

class ClassroomService {
  ClassroomService();

  /// Testlerde ve önizlemelerde sahte bir hizmetle değiştirilebilir.
  static ClassroomService instance = ClassroomService();

  static const _host = 'classroom.googleapis.com';

  Future<Map<String, String>> _h() => GoogleAuth.instance.headers(GoogleScopes.classroom, interactive: true);

  Never _fail(http.Response r) {
    String? msg;
    try {
      msg = (jsonDecode(r.body)['error'] as Map?)?['message'] as String?;
    } catch (_) {}
    if (r.statusCode == 403 && ((msg ?? '').contains('has not been used') || (msg ?? '').contains('disabled'))) {
      throw ClassroomException(tr('Google Classroom bağlantısı henüz açılmadı. Lütfen daha sonra yeniden deneyin.'));
    }
    if (r.statusCode == 403) {
      throw ClassroomException(tr('Classroom bu işleme izin vermedi. Okul hesabınızda yönetici, uygulamaların Classroom\'a erişimini kapatmış olabilir.'));
    }
    throw ClassroomException(tr('Classroom yanıt vermedi ({0}). {1}', [r.statusCode, msg ?? '']).trim());
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> h, [Map<String, String>? q]) async {
    final r = await http.get(Uri.https(_host, path, q), headers: h);
    if (r.statusCode != 200) _fail(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Öğretmenin etkin dersleri.
  Future<List<ClassroomCourse>> courses() async {
    final h = await _h();
    final out = <ClassroomCourse>[];
    String? page;
    do {
      final j = await _get('/v1/courses', h, {
        'teacherId': 'me',
        'courseStates': 'ACTIVE',
        'pageSize': '100',
        'pageToken': ?page,
      });
      for (final c in (j['courses'] as List? ?? const [])) {
        final m = c as Map<String, dynamic>;
        out.add(ClassroomCourse(m['id'] as String, m['name'] as String? ?? '', m['section'] as String? ?? ''));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return out;
  }

  /// Dersteki öğrenciler.
  Future<List<LmsStudent>> students(String courseId) async {
    final h = await _h();
    final out = <LmsStudent>[];
    String? page;
    do {
      final j = await _get('/v1/courses/$courseId/students', h, {
        'pageSize': '100',
        'pageToken': ?page,
      });
      for (final s in (j['students'] as List? ?? const [])) {
        final m = s as Map<String, dynamic>;
        final p = m['profile'] as Map<String, dynamic>? ?? const {};
        out.add(LmsStudent(m['userId'] as String, (p['name'] as Map?)?['fullName'] as String? ?? '',
            p['emailAddress'] as String? ?? ''));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Notları gönderir. [match]: Netice öğrencisi → Classroom öğrencisi.
  /// [publish] true ise notlar öğrencilere geri verilir (öğrenci görür);
  /// değilse taslak/atanmış not olarak öğretmende kalır.
  Future<ClassroomSendResult> send({
    required AppStore store,
    required Exam exam,
    required ClassroomCourse course,
    required List<GradeRow> rows,
    required Map<String, String?> match,
    bool publish = false,
  }) async {
    final h = await _h();
    final json = {...h, 'Content-Type': 'application/json; charset=utf-8'};
    final maxPoints = exam.rule.maxScore;

    // Daha önce bu derste açılan ödev varsa onu kullan.
    final link = store.classroomLinks[exam.id];
    String? cwId = link != null && link['course'] == course.id ? link['courseWork'] : null;
    String? alternate = link?['link'];
    if (cwId != null) {
      final r = await http.get(Uri.https(_host, '/v1/courses/${course.id}/courseWork/$cwId'), headers: h);
      if (r.statusCode == 404) cwId = null; // Classroom'da silinmiş
    }
    if (cwId == null) {
      final r = await http.post(Uri.https(_host, '/v1/courses/${course.id}/courseWork'),
          headers: json,
          body: jsonEncode({
            'title': 'Netice: ${exam.name}',
            'description': tr('{0} tarihli optik sınavın sonuçları Netice ile okundu.', [L10n.date(exam.date)]),
            'workType': 'ASSIGNMENT',
            'state': 'PUBLISHED',
            'maxPoints': maxPoints,
            'submissionModificationMode': 'MODIFIABLE_UNTIL_TURNED_IN',
          }));
      if (r.statusCode != 200) _fail(r);
      final cw = jsonDecode(r.body) as Map<String, dynamic>;
      cwId = cw['id'] as String;
      alternate = cw['alternateLink'] as String?;
      store.setClassroomLink(exam.id, {
        'course': course.id,
        'courseWork': cwId,
        'courseName': course.label,
        'link': ?alternate,
      });
    }

    // Öğrenci → teslim kimliği.
    final subs = <String, String>{};
    String? page;
    do {
      final j = await _get('/v1/courses/${course.id}/courseWork/$cwId/studentSubmissions', h, {
        'pageSize': '100',
        'pageToken': ?page,
      });
      for (final s in (j['studentSubmissions'] as List? ?? const [])) {
        final m = s as Map<String, dynamic>;
        subs[m['userId'] as String] = m['id'] as String;
      }
      page = j['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);

    var sent = 0, skipped = 0;
    for (final g in rows) {
      final uid = match[g.student.id];
      final sid = uid == null ? null : subs[uid];
      if (sid == null) {
        skipped++;
        continue;
      }
      final grade = double.parse(gradeText(g.score.clamp(0, maxPoints).toDouble()));
      final base = '/v1/courses/${course.id}/courseWork/$cwId/studentSubmissions/$sid';
      final r = await http.patch(Uri.https(_host, base, {'updateMask': 'draftGrade,assignedGrade'}),
          headers: json, body: jsonEncode({'draftGrade': grade, 'assignedGrade': grade}));
      if (r.statusCode != 200) _fail(r);
      if (publish) {
        final rr = await http.post(Uri.https(_host, '$base:return'), headers: json, body: '{}');
        // Zaten geri verilmişse Classroom hata döndürebilir; not yazıldı sayılır.
        if (rr.statusCode != 200 && rr.statusCode != 400) _fail(rr);
      }
      sent++;
    }
    return ClassroomSendResult(sent, skipped, cwId, alternate);
  }
}

/// Bağlantı hatalarını öğretmenin anlayacağı dile çevirir.
String friendlyNetError(Object e) {
  final s = '$e';
  if (e is SocketException || s.contains('SocketException') || s.contains('Failed host')) {
    return tr('internet bağlantısı yok.');
  }
  if (s.contains('canceled') || s.contains('cancel')) return tr('giriş iptal edildi.');
  return s.length > 220 ? '${s.substring(0, 220)}…' : s;
}
