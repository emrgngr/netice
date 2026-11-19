import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../core/import_export.dart';
import '../core/legal.dart';
import '../core/term.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'report_preview_screen.dart';
import 'illustrations.dart';
import 'pro_screen.dart';
import '../core/pro.dart';
import 'theme.dart';
import 'widgets.dart';

/// Dönem raporu: bir sınıfın dönemdeki sınavlarından dönem sonu notu
/// (ağırlıklı ortalama) ve öğrenci başına dönem kazanım karnesi.
class TermScreen extends StatefulWidget {
  const TermScreen({super.key});

  @override
  State<TermScreen> createState() => _TermScreenState();
}

class _TermScreenState extends State<TermScreen> {
  String? _class;
  late Term _term;
  final Set<String> _off = {};
  final Map<String, double> _weights = {};
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final store = StoreScope.of(context);
    _term = Term.current(DateTime.now());
    // Varsayılan: en son sınavın sınıfı; o dönemde sınav yoksa tüm yıl.
    final withResults = store.exams.where((e) => store.sheetsOf(e.id).isNotEmpty).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (withResults.isNotEmpty) {
      _class = withResults.first.className;
      if (!_term.contains(withResults.first.date)) _term = Term.around(DateTime.now()).last;
    }
  }

  String _safe(String s) => s.replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ -]'), '').replaceAll(' ', '_');

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final classes = {
      for (final e in store.exams)
        if (store.sheetsOf(e.id).isNotEmpty) e.className,
    }.toList()..sort();
    final terms = Term.around(DateTime.now());
    final candidates =
        store.exams
            .where((e) => e.className == _class && _term.contains(e.date) && store.sheetsOf(e.id).isNotEmpty)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final chosen = candidates.where((e) => !_off.contains(e.id)).toList();
    final report = _class == null || chosen.isEmpty
        ? null
        : TermReport.build(store, _class!, _term, chosen, weights: _weights);
    final totalW = chosen.fold<double>(0, (a, e) => a + (_weights[e.id] ?? 1));
    final base = '${_safe(_class ?? '')}_${_safe(_term.label.split(' (').first)}';

    Future<void> gradesPdf() async {
      if (report == null) return toast(context, 'Önce en az bir sınav seçin.');
      await ReportPreviewScreen.open(
        context,
        title: 'Dönem not çizelgesi',
        fileName: '${base}_not_cizelgesi.pdf',
        build: () => buildTermGradesPdf(report, school: store.reportSchool),
      );
    }

    Future<void> cardsPdf([String? studentId]) async {
      if (report == null) return toast(context, 'Önce en az bir sınav seçin.');
      if (!await requirePro(context, ProFeature.studentCards) || !context.mounted) return;
      final students = [
        for (final r in report.rows)
          if (r.average != null) (r.student.id, r.student.fullName),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StudentCardsPreview(
            title: 'Dönem kazanım karnesi',
            baseFileName: '${base}_kazanim_karnesi',
            students: students,
            initialStudentId: studentId,
            build: (id) => buildTermCardsPdf(report, school: store.reportSchool, onlyStudentId: id),
          ),
        ),
      );
    }

    Future<void> excel() async {
      if (report == null) return toast(context, 'Önce en az bir sınav seçin.');
      await FilePicker.saveFile(
        fileName: '${base}_donem_notlari.csv',
        bytes: Uint8List.fromList(utf8.encode(termCsv(report))),
        mimeType: 'text/csv',
      );
    }

    Future<void> share(TermRow r) async {
      if (!await requirePro(context, ProFeature.parentShare) || !context.mounted) return;
      try {
        final bytes = await buildTermCardsPdf(report!, school: store.reportSchool, onlyStudentId: r.student.id);
        await Printing.sharePdf(
          bytes: bytes,
          filename: '${_safe(r.student.fullName)}_donem_karnesi.pdf',
          subject: '${r.student.fullName} – ${_term.label} kazanım karnesi',
          body:
              'Sayın Velimiz,\n\n${r.student.fullName} adlı öğrencimizin ${_term.label} kazanım karnesi ektedir.\n'
              'Dönem ortalaması: ${r.grade} · Sınıf ortalaması: ${fmt1(report.classAverage)}\n\nSaygılarımızla,\n'
              '${store.school.teacher.trim().isEmpty ? 'Ders öğretmeni' : store.school.teacher.trim()}'
              '$downloadSignature',
        );
      } catch (e) {
        if (context.mounted) toast(context, 'Karne paylaşılamadı: $e');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dönem raporu'),
        actions: [IconButton(tooltip: 'Excel', onPressed: excel, icon: const Icon(Icons.table_view_outlined))],
      ),
      body: Watermark(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              'Sınıfı ve dönemi seçin; o dönemdeki sınavlardan dönem sonu notu ve her öğrenci için kazanım karnesi hazırlanır.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 14),
            if (classes.isEmpty)
              const Card(
                child: EmptyState(
                  kind: IllustrationKind.term,
                  title: 'Henüz sonucu olan sınav yok',
                  message: 'Kâğıt okuttuğunuz sınavlar burada dönem sonu notuna ve kazanım karnesine dönüşür.',
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _class,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sınıf / şube',
                        prefixIcon: Icon(Icons.groups_2_outlined),
                      ),
                      items: [for (final c in classes) DropdownMenuItem(value: c, child: Text(c))],
                      onChanged: (v) => setState(() {
                        _class = v;
                        _off.clear();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < terms.length; i++)
                    ButtonSegment(value: i, label: Text(terms[i].label.split(' (').first)),
                ],
                selected: {terms.indexWhere((x) => x.label == _term.label)},
                onSelectionChanged: (s) => setState(() {
                  _term = terms[s.first];
                  _off.clear();
                }),
              ),
              SectionTitle('Sınavlar ve ağırlıkları (${chosen.length}/${candidates.length})'),
              if (candidates.isEmpty)
                Card(
                  child: ListTile(
                    leading: const IconBadge(Icons.event_busy_outlined, color: NColors.amber),
                    title: const Text('Bu dönemde sınav yok'),
                    subtitle: Text(
                      '${_class ?? ''} için ${_term.label} içinde sonucu olan sınav bulunamadı. "Tüm yıl"ı deneyin.',
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final e in candidates)
                        CheckboxListTile(
                          value: !_off.contains(e.id),
                          onChanged: (v) => setState(() => v == true ? _off.remove(e.id) : _off.add(e.id)),
                          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${dmy(e.date)} · ${store.sheetsOf(e.id).length} kâğıt'
                            '${_off.contains(e.id) || totalW == 0 ? '' : ' · notun %${((_weights[e.id] ?? 1) / totalW * 100).round()}\'i'}',
                          ),
                          secondary: DropdownButton<double>(
                            value: _weights[e.id] ?? 1,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('1×')),
                              DropdownMenuItem(value: 2, child: Text('2×')),
                              DropdownMenuItem(value: 3, child: Text('3×')),
                            ],
                            onChanged: (v) => setState(() => _weights[e.id] = v ?? 1),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                    ],
                  ),
                ),
              if (report != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 118,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Ortalama',
                          value: fmt1(report.classAverage),
                          icon: Icons.insights_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatCard(
                          label: 'Notu olan',
                          value: '${report.rows.where((r) => r.average != null).length}/${report.rows.length}',
                          icon: Icons.how_to_reg_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: gradesPdf,
                      icon: const Icon(Icons.grading_rounded),
                      label: const Text('Not çizelgesi (PDF)'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => cardsPdf(),
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('Kazanım karneleri'),
                    ),
                    OutlinedButton.icon(
                      onPressed: excel,
                      icon: const Icon(Icons.table_view_outlined),
                      label: const Text('Excel\'e aktar'),
                    ),
                  ],
                ),
                const SectionTitle('Dönem notları'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final r in report.rows)
                        ListTile(
                          dense: true,
                          title: Text(r.student.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'No ${r.student.number} · '
                            '${[for (final s in r.scores) s == null ? 'G' : s.round().toString()].join(' · ')}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                r.grade == null ? 'G' : '${r.grade}',
                                style: t.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: tabular,
                                  color: r.grade == null ? muted : (r.grade! < 50 ? NColors.coral : null),
                                ),
                              ),
                              if (r.average != null)
                                IconButton(
                                  tooltip: 'Karneyi veliye gönder',
                                  icon: const Icon(Icons.send_outlined, size: 20),
                                  onPressed: () => share(r),
                                ),
                            ],
                          ),
                          onTap: r.average == null ? null : () => cardsPdf(r.student.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'G: sınava girmedi. Girilmeyen sınav öğrencinin ortalamasına katılmaz; ağırlıklar diğer sınavlara dağıtılır.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
