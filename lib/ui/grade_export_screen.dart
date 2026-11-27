import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/classroom.dart';
import '../core/cloud.dart';
import '../core/google_auth.dart';
import '../core/grade_export.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'pro_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sınav ekranındaki "Classroom / Moodle'a aktar" menüsü.
Future<void> openGradeExport(BuildContext context, Exam exam) async {
  final store = StoreScope.of(context);
  final rows = gradeRows(store.resultsOf(exam), store.studentById);
  if (rows.isEmpty) return toast(context, tr('Aktarmak için önce kâğıt okutun ve öğrencilerle eşleştirin.'));
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(tr('Notları aktar'), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(tr('{0} öğrencinin notu', [rows.length])),
        ),
        ListTile(
          leading: const IconBadge(Icons.co_present_outlined, color: NColors.emerald),
          title: Text(tr('Google Classroom')),
          subtitle: Text(store.classroomLinks[exam.id] != null
              ? tr('Daha önce gönderildi: {0}', [store.classroomLinks[exam.id]!['courseName'] ?? ''])
              : tr('Derse "Netice" ödevi olarak notlar yazılır')),
          onTap: () => Navigator.pop(ctx, 'classroom'),
        ),
        ListTile(
          leading: const IconBadge(Icons.school_outlined, color: Color(0xFFF98012)),
          title: Text(tr('Moodle')),
          subtitle: Text(tr('Not defterine içe aktarılacak dosya (CSV)')),
          onTap: () => Navigator.pop(ctx, 'moodle'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (!await requirePro(context, ProFeature.gradeExport) || !context.mounted) return;
  if (choice == 'moodle') return _moodle(context, exam, rows);
  if (!CloudConfig.platformSupported || !CloudConfig.configured) {
    return toast(context, tr('Google Classroom\'a gönderme bu cihazda henüz yok. Telefon uygulamasından gönderebilir ya da Moodle dosyası kullanabilirsiniz.'));
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClassroomExportScreen(examId: exam.id)));
}

String _safe(String s) => s.replaceAll(RegExp(r'[^\w\-ğüşıöçĞÜŞİÖÇ ]'), '').trim().replaceAll(' ', '_');

Future<void> _moodle(BuildContext context, Exam exam, List<GradeRow> rows) async {
  final csv = moodleCsv(exam, rows);
  final saved = await FilePicker.saveFile(
    fileName: '${_safe(exam.name)}_moodle.csv',
    bytes: Uint8List.fromList(utf8.encode(csv)),
    mimeType: 'text/csv',
  );
  if (saved == null || !context.mounted) return;
  final noMail = rows.where((r) => r.student.email.isEmpty).length;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Moodle\'a nasıl yüklenir?')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, s) in [
            tr('Moodle\'da dersinizi açın: Notlar > İçe aktar > CSV dosyası.'),
            tr('Bu dosyayı seçin, "Yükle"ye basın.'),
            tr('"Eşleştir" bölümünde "ID number"ı "Kimlik numarası"na eşleyin (okul numarası). Okulunuz e-posta kullanıyorsa "Email address"i "E-posta adresi"ne eşleyin.'),
            tr('"{0}" sütununu "Yeni not öğesi"ne ya da var olan bir sınav sütununa eşleyin ve "Notları yükle"ye basın.', [exam.name]),
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                    radius: 11,
                    backgroundColor: NColors.emerald,
                    child: Text('${i + 1}', style: const TextStyle(color: NColors.onGreen, fontSize: 12, fontWeight: FontWeight.w800))),
                const SizedBox(width: 10),
                Expanded(child: Text(s, style: const TextStyle(height: 1.35))),
              ]),
            ),
          if (noMail > 0)
            Text(tr('{0} öğrencinin e-postası kayıtlı değil; bunlar okul numarasıyla eşleşir.', [noMail]),
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Tamam')))],
    ),
  );
}

/// Notları Google Classroom'daki bir derse gönderir: ders seçimi, öğrenci
/// eşleştirme ve gönderme tek ekranda.
class ClassroomExportScreen extends StatefulWidget {
  final String examId;
  const ClassroomExportScreen({super.key, required this.examId});
  @override
  State<ClassroomExportScreen> createState() => _ClassroomExportScreenState();
}

class _ClassroomExportScreenState extends State<ClassroomExportScreen> {
  /// "Gönderme" seçimi (eşleşmemiş = null'dan ayrı görünür).
  static const _skip = '-';
  final _svc = ClassroomService.instance;
  List<ClassroomCourse>? _courses;
  ClassroomCourse? _course;
  List<LmsStudent>? _theirs;
  Map<String, String?> _match = {};
  bool _publish = false;
  bool _busy = false;
  String? _error;
  ClassroomSendResult? _done;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyNetError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _guard(() async {
        final store = StoreScope.of(context);
        if (store.googleEmail == null) {
          // Yalnızca Classroom için giriş: Drive yedeği kendiliğinden açılmasın.
          await CloudService.instance.signIn(store, scopes: GoogleScopes.classroom);
          store.setCloudAuto(false);
        }
        final list = await _svc.courses();
        if (!mounted) return;
        final exam = store.examById(widget.examId)!;
        final linked = store.classroomLinks[exam.id]?['course'];
        ClassroomCourse? pick = list.where((c) => c.id == linked).firstOrNull;
        if (pick == null) {
          final k = nameKey(exam.className);
          final same = list.where((c) => k.isNotEmpty && (nameKey(c.name).contains(k) || nameKey(c.section).contains(k))).toList();
          if (same.length == 1) pick = same.first;
        }
        setState(() => _courses = list);
        if (pick != null) await _choose(pick);
      });

  Future<void> _choose(ClassroomCourse c) async {
    setState(() {
      _course = c;
      _theirs = null;
      _done = null;
    });
    await _guard(() async {
      final list = await _svc.students(c.id);
      if (!mounted) return;
      final store = StoreScope.of(context);
      final exam = store.examById(widget.examId)!;
      final rows = gradeRows(store.resultsOf(exam), store.studentById);
      setState(() {
        _theirs = list;
        _match = matchStudents([for (final r in rows) r.student], list);
      });
    });
  }

  Future<void> _send(List<GradeRow> rows) => _guard(() async {
        final store = StoreScope.of(context);
        final r = await _svc.send(
          store: store,
          exam: store.examById(widget.examId)!,
          course: _course!,
          rows: rows,
          match: _match,
          publish: _publish,
        );
        if (mounted) setState(() => _done = r);
      });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = store.examById(widget.examId);
    if (exam == null) return const Scaffold();
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final rows = gradeRows(store.resultsOf(exam), store.studentById);
    final matched = rows.where((r) => _match[r.student.id] != null && _match[r.student.id] != _skip).length;
    final used = {for (final v in _match.values) if (v != null && v != _skip) v};

    Widget body;
    if (_done != null) {
      body = ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 24),
        const Center(child: IconBadge(Icons.check_rounded, color: NColors.emerald, size: 72)),
        const SizedBox(height: 18),
        Text(tr('{0} öğrencinin notu Classroom\'a yazıldı.', [_done!.sent]),
            textAlign: TextAlign.center, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          [
            tr('Ders: {0} · Ödev: "Netice: {1}"', [_course!.label, exam.name]),
            if (_done!.skipped > 0) tr('{0} öğrenci eşleşmediği için atlandı.', [_done!.skipped]),
            _publish ? tr('Notlar öğrencilere geri verildi; öğrenciler görebilir.') : tr('Notlar yalnız sizde görünür. Classroom\'da "Geri ver" deyince öğrenciler görür.'),
          ].join('\n'),
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        if (_done!.link != null)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(_done!.link!), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(tr('Classroom\'da aç')),
          ),
        const SizedBox(height: 10),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Tamam'))),
      ]);
    } else if (_courses == null) {
      body = _status(_error, onRetry: _start, muted: muted, message: tr('Classroom dersleriniz alınıyor…'));
    } else if (_courses!.isEmpty) {
      body = _status(tr('Bu Google hesabında öğretmeni olduğunuz etkin bir Classroom dersi yok. Classroom\'u okul hesabınızla kullanıyorsanız Ayarlar\'dan o hesapla giriş yapın.'),
          onRetry: _start, muted: muted);
    } else {
      body = ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        Text(tr('Ders'), style: t.textTheme.labelLarge?.copyWith(color: muted)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _course?.id,
          isExpanded: true,
          hint: Text(tr('Ders seçin')),
          items: [for (final c in _courses!) DropdownMenuItem(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis))],
          onChanged: _busy ? null : (id) => _choose(_courses!.firstWhere((c) => c.id == id)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: NColors.coral)),
        ],
        if (_course != null && _theirs == null && _busy)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (_theirs != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(tr('Öğrenciler ({0}/{1} eşleşti)', [matched, rows.length]),
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(tr('Not / {0}', [gradeText(exam.rule.maxScore)]), style: TextStyle(color: muted)),
          ]),
          const SizedBox(height: 4),
          Text(tr('Adı tutanlar kendiliğinden eşleşti. Eşleşmeyenleri listeden seçin.'),
              style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 8),
          for (final g in rows)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.student.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      DropdownButton<String?>(
                        value: _match[g.student.id],
                        isExpanded: true,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        hint: Text(tr('Eşleşmedi, seçin'), style: const TextStyle(color: NColors.coral, fontSize: 13)),
                        items: [
                          DropdownMenuItem<String?>(value: _skip, child: Text(tr('Gönderme'), style: TextStyle(color: muted, fontSize: 13))),
                          for (final s in _theirs!)
                            if (!used.contains(s.id) || _match[g.student.id] == s.id)
                              DropdownMenuItem<String?>(
                                value: s.id,
                                child: Text(s.email.isEmpty ? s.name : '${s.name} · ${s.email}',
                                    overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13)),
                              ),
                        ],
                        onChanged: (v) => setState(() => _match[g.student.id] = v),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(gradeText(g.score), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _publish,
            onChanged: (v) => setState(() => _publish = v),
            title: Text(tr('Notları öğrencilere hemen göster')),
            subtitle: Text(tr('Kapalıysa notlar Classroom\'da yalnız sizde görünür; istediğiniz zaman geri verirsiniz.')),
          ),
        ],
      ]);
    }

    final canSend = _done == null && _theirs != null && matched > 0 && !_busy;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Google Classroom\'a gönder'))),
      body: body,
      bottomNavigationBar: _done != null || _theirs == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: canSend ? () => _send(rows) : null,
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                  label: Text(tr('{0} notu gönder', [matched])),
                ),
              ),
            ),
    );
  }

  Widget _status(String? error, {required VoidCallback onRetry, required Color muted, String? message}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message ?? '', style: TextStyle(color: muted)),
            ] else ...[
              const IconBadge(Icons.co_present_outlined, color: NColors.amber, size: 56),
              const SizedBox(height: 16),
              Text(error, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _busy ? null : onRetry, child: Text(tr('Yeniden dene'))),
            ],
          ]),
        ),
      );
}
