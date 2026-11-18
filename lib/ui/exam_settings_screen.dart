import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../main.dart';
import 'key_from_photo.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sınav ayarları: ad, tarih, puanlama, geçme puanı ve soru bazında
/// cevap anahtarı / puan / kazanım / iptal. Kaydedince tüm kâğıtlar
/// yeniden okutmaya gerek kalmadan yeniden puanlanır.
class ExamSettingsScreen extends StatefulWidget {
  final String examId;
  const ExamSettingsScreen({super.key, required this.examId});

  @override
  State<ExamSettingsScreen> createState() => _ExamSettingsScreenState();
}

class _ExamSettingsScreenState extends State<ExamSettingsScreen> {
  late Exam _exam;
  late final TextEditingController _name;
  late final TextEditingController _class;
  late final TextEditingController _pass;
  late final TextEditingController _max;
  late List<Question> _qs;
  late List<TextEditingController> _points;
  late List<TextEditingController> _codes;
  late int _wpc;
  late DateTime _date;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _exam = StoreScope.of(context).examById(widget.examId)!;
    _name = TextEditingController(text: _exam.name);
    _class = TextEditingController(text: _exam.className);
    _pass = TextEditingController(text: _num(_exam.rule.pass));
    _max = TextEditingController(text: _num(_exam.rule.maxScore));
    _qs = [..._exam.questions];
    _points = [for (final q in _qs) TextEditingController(text: _num(q.points))];
    _codes = [for (final q in _qs) TextEditingController(text: q.outcomeCode ?? '')];
    _wpc = _exam.rule.wrongsPerCorrect;
    _date = _exam.date;
    _loaded = true;
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  void _toggle(int i, int c) => setState(() {
        final set = {..._qs[i].correct};
        set.contains(c) ? set.remove(c) : set.add(c);
        if (set.isNotEmpty) _qs[i] = _qs[i].copyWith(correct: set);
      });

  Future<void> _fromPhoto() async {
    final key = await readKeyFromPhoto(context, questions: _qs.length, choices: _exam.choiceCount);
    if (key == null) return;
    setState(() {
      for (var i = 0; i < _qs.length; i++) {
        if (key[i].isNotEmpty) _qs[i] = _qs[i].copyWith(correct: key[i]);
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100), helpText: 'Sınav tarihi');
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date), helpText: 'Sınav saati');
    if (t != null) setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
  }

  void _save() {
    final max = _parse(_max.text);
    final pass = _parse(_pass.text);
    if (_name.text.trim().isEmpty) return toast(context, 'Sınava bir ad verin.');
    if (max == null || max <= 0) return toast(context, 'Tam puan geçerli bir sayı olmalı.');
    if (pass == null || pass < 0 || pass > max) return toast(context, 'Geçme puanı 0 ile tam puan arasında olmalı.');
    final qs = <Question>[];
    for (var i = 0; i < _qs.length; i++) {
      final p = _parse(_points[i].text);
      if (p == null || p <= 0) return toast(context, '${i + 1}. sorunun puanı geçerli değil.');
      final code = _codes[i].text.trim();
      qs.add(Question(
          no: _qs[i].no,
          correct: _qs[i].correct,
          points: p,
          cancelled: _qs[i].cancelled,
          outcomeCode: code.isEmpty ? null : code));
    }
    StoreScope.of(context).upsertExam(_exam.copyWith(
      name: _name.text.trim(),
      className: _class.text.trim(),
      date: _date,
      questions: qs,
      rule: ScoringRule(wrongsPerCorrect: _wpc, maxScore: max, passScore: pass),
    ));
    toast(context, 'Kaydedildi; tüm puanlar yeniden hesaplandı.');
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sınav silinsin mi?'),
        content: Text('"${_exam.name}" ve okunan tüm kâğıtları kalıcı olarak silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NColors.coral, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    StoreScope.of(context).deleteExam(_exam.id);
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(title: const Text('Sınav ayarları'), actions: [
        IconButton(tooltip: 'Sınavı sil', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(onPressed: _save, child: const Text('Kaydet ve yeniden puanla')),
        ),
      ),
      body: Watermark(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Sınav adı')),
              const SizedBox(height: 12),
              TextField(controller: _class, decoration: const InputDecoration(labelText: 'Sınıf / şube')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _pickDate, icon: const Icon(Icons.calendar_today_rounded, size: 18), label: Text(dmy(_date)))),
                const SizedBox(width: 12),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(hm(_date)))),
              ]),
              const SectionTitle('Puanlama'),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Tam puan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pass,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Geçme puanı'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _wpc,
                decoration: const InputDecoration(labelText: 'Yanlış götürme'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Yok')),
                  DropdownMenuItem(value: 3, child: Text('3 yanlış 1 doğru')),
                  DropdownMenuItem(value: 4, child: Text('4 yanlış 1 doğru')),
                ],
                onChanged: (v) => setState(() => _wpc = v ?? 0),
              ),
              SectionTitle('Sorular',
                  trailing: TextButton.icon(
                    onPressed: _fromPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Anahtarı fotoğraftan oku'),
                  )),
              Text('Doğru şıkka dokunun; birden çok şık seçerseniz hepsi doğru sayılır. '
                  'Puan ağırlıklı sorular içindir.',
                  style: t.textTheme.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: 10),
              for (var i = 0; i < _qs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          SizedBox(
                            width: 38,
                            child: Text('${i + 1}.',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: tabular,
                                    decoration: _qs[i].cancelled ? TextDecoration.lineThrough : null)),
                          ),
                          Expanded(
                            child: Wrap(spacing: 6, runSpacing: 6, children: [
                              for (var c = 0; c < _exam.choiceCount; c++)
                                ChoiceChip(
                                  label: Text(letter(c), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  showCheckmark: false,
                                  selected: _qs[i].correct.contains(c),
                                  selectedColor: NColors.emerald.withValues(alpha: 0.35),
                                  onSelected: _qs[i].cancelled ? null : (_) => _toggle(i, c),
                                ),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          SizedBox(
                            width: 76,
                            child: TextField(
                              controller: _points[i],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Puan', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _codes[i],
                              decoration: const InputDecoration(labelText: 'Kazanım / konu', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            Switch(
                              value: _qs[i].cancelled,
                              activeThumbColor: NColors.coral,
                              onChanged: (v) => setState(() => _qs[i] = _qs[i].copyWith(cancelled: v)),
                            ),
                            Text('İptal', style: t.textTheme.labelSmall),
                          ]),
                        ]),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
