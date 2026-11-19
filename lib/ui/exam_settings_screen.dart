import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../main.dart';
import 'key_from_photo.dart';
import 'theme.dart';
import 'widgets.dart';
import 'template_screen.dart';
import '../l10n/l10n.dart';

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
  late bool _booklet;
  String? _template;
  late List<(TextEditingController, TextEditingController)> _open;
  late final TextEditingController _order;
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
    _booklet = _exam.hasBooklets;
    _template = _exam.templateId;
    _open = [
      for (final q in _exam.openQuestions)
        (TextEditingController(text: q.label), TextEditingController(text: _num(q.maxPoints)))
    ];
    _order = TextEditingController(
        text: _exam.bookletOrder == null ? '' : _exam.bookletOrder!.map((v) => v + 1).join(', '))
      ..addListener(() => setState(() {}));
    _date = _exam.date;
    _loaded = true;
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', L10n.decimal);
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
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100), helpText: tr('Sınav tarihi'));
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date), helpText: tr('Sınav saati'));
    if (t != null) setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
  }

  void _save() {
    final max = _parse(_max.text);
    final pass = _parse(_pass.text);
    if (_name.text.trim().isEmpty) return toast(context, tr('Sınava bir ad verin.'));
    if (max == null || max <= 0) return toast(context, tr('Tam puan geçerli bir sayı olmalı.'));
    if (pass == null || pass < 0 || pass > max) return toast(context, tr('Geçme puanı 0 ile tam puan arasında olmalı.'));
    final qs = <Question>[];
    for (var i = 0; i < _qs.length; i++) {
      final p = _parse(_points[i].text);
      if (p == null || p <= 0) return toast(context, tr('{0}. sorunun puanı geçerli değil.', [i + 1]));
      final code = _codes[i].text.trim();
      qs.add(Question(
          no: _qs[i].no,
          correct: _qs[i].correct,
          points: p,
          cancelled: _qs[i].cancelled,
          outcomeCode: code.isEmpty ? null : code));
    }
    final open = <OpenQuestion>[];
    for (var i = 0; i < _open.length; i++) {
      final m = _parse(_open[i].$2.text);
      if (m == null || m <= 0) return toast(context, tr('{0}. klasik sorunun puanı geçerli değil.', [i + 1]));
      final label = _open[i].$1.text.trim();
      open.add(OpenQuestion(label: label.isEmpty ? tr('Klasik {0}', [i + 1]) : label, maxPoints: m));
    }
    final openSum = open.fold(0.0, (a, q) => a + q.maxPoints);
    if (openSum >= max) {
      return toast(context, tr('Klasik soruların toplamı ({0}) tam puandan küçük olmalı; kalanı test kısmıdır.', [_num(openSum)]));
    }
    final tpl = StoreScope.of(context).templateById(_template);
    if (tpl != null && _booklet) {
      return toast(context, tr('Başka firma formlarında A/B kitapçık okunamaz; kitapçık seçeneğini kapatın.'));
    }
    if (tpl != null && tpl.questionCount < _qs.length) {
      return toast(context, tr('"{0}" şablonunda {1} soru var; sınavda {2} soru var. Şablona blok ekleyin.', [tpl.name, tpl.questionCount, _qs.length]));
    }
    List<int>? order;
    if (_booklet) {
      order = Exam.parseBookletOrder(_order.text, _qs.length);
      if (order == null) {
        return toast(context, tr('B kitapçığı sırası 1–{0} arasındaki her numarayı bir kez içermeli.', [_qs.length]));
      }
    }
    StoreScope.of(context).upsertExam(_exam.copyWith(
      bookletOrder: order,
      clearBooklet: !_booklet,
      openQuestions: open,
      templateId: tpl?.id,
      clearTemplate: tpl == null,
      name: _name.text.trim(),
      className: _class.text.trim(),
      date: _date,
      questions: qs,
      rule: ScoringRule(wrongsPerCorrect: _wpc, maxScore: max, passScore: pass),
    ));
    toast(context, tr('Kaydedildi; tüm puanlar yeniden hesaplandı.'));
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sınav silinsin mi?')),
        content: Text(tr('"{0}" ve okunan tüm kâğıtları kalıcı olarak silinecek.', [_exam.name])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NColors.coral, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Sil')),
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
      appBar: AppBar(title: Text(tr('Sınav ayarları')), actions: [
        IconButton(tooltip: tr('Sınavı sil'), onPressed: _delete, icon: const Icon(Icons.delete_outline)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(onPressed: _save, child: Text(tr('Kaydet ve yeniden puanla'))),
        ),
      ),
      body: Watermark(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('Sınav adı'))),
              const SizedBox(height: 12),
              TextField(controller: _class, decoration: InputDecoration(labelText: tr('Sınıf / şube'))),
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
              SectionTitle(tr('Puanlama')),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Tam puan')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pass,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Geçme puanı')),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _wpc,
                decoration: InputDecoration(labelText: tr('Yanlış götürme')),
                items: [
                  DropdownMenuItem(value: 0, child: Text(tr('Yok'))),
                  DropdownMenuItem(value: 3, child: Text(tr('3 yanlış 1 doğru'))),
                  DropdownMenuItem(value: 4, child: Text(tr('4 yanlış 1 doğru'))),
                ],
                onChanged: (v) => setState(() => _wpc = v ?? 0),
              ),
              SectionTitle(tr('Form türü')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: StoreScope.of(context).templateById(_template)?.id,
                      decoration: InputDecoration(labelText: tr('Öğrencilerin dolduracağı form')),
                      items: [
                        DropdownMenuItem(value: null, child: Text(tr('Netice formu (önerilen)'), overflow: TextOverflow.ellipsis)),
                        for (final tp in StoreScope.of(context).templates)
                          DropdownMenuItem(value: tp.id, child: Text(tp.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _template = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Yayınevi ya da başka firmanın formunu kullanıyorsanız önce o form için şablon oluşturun.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen()));
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.grid_on_rounded),
                        label: Text(tr('Başka firma formları')),
                      ),
                    ),
                  ]),
                ),
              ),
              SectionTitle(tr('Kitapçık türü')),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SwitchListTile(
                    value: _booklet,
                    onChanged: (v) => setState(() => _booklet = v),
                    title: Text(tr('A ve B kitapçığı var'), style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('Kopya önlemek için soruların yeri değişik ikinci kitapçık. Formda kitapçık dairesi çıkar, kâğıtlar kendiliğinden doğru anahtarla puanlanır.')),
                  ),
                  if (_booklet)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        TextField(
                          controller: _order,
                          keyboardType: TextInputType.text,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: tr('B kitapçığındaki soruların A\'daki numaraları'),
                            hintText: tr('Örn. 3, 1, 4, 2, …  (B\'nin 1. sorusu A\'nın 3. sorusu)'),
                            errorText: _order.text.trim().isEmpty ||
                                    Exam.parseBookletOrder(_order.text, _qs.length) != null
                                ? null
                                : tr('1–{0} arası her numara bir kez yazılmalı', [_qs.length]),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: Text(
                              () {
                                final o = Exam.parseBookletOrder(_order.text, _qs.length);
                                if (o == null) return tr('B anahtarı sıra girilince burada görünür.');
                                return tr('B anahtarı: {0}', [[
                                  for (final i in o)
                                    _qs[i].correct.isEmpty ? '–' : _qs[i].correct.map((c) => String.fromCharCode(65 + c)).join('/')
                                ].join(' ')]);
                              }(),
                              style: t.textTheme.bodySmall?.copyWith(color: muted),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() =>
                                _order.text = ([for (var i = 1; i <= _qs.length; i++) i]..shuffle()).join(', ')),
                            icon: const Icon(Icons.shuffle_rounded, size: 18),
                            label: Text(tr('Karışık sıra öner')),
                          ),
                        ]),
                      ]),
                    ),
                ]),
              ),
              SectionTitle(tr('Klasik (yazılı) sorular')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      _open.isEmpty
                          ? tr('Sınavda açık uçlu sorular da varsa ekleyin. Puanlarını kâğıtları okuttuktan sonra "Klasik puan gir" ekranından girersiniz.')
                          : () {
                              final sum = _open.fold(0.0, (a, o) => a + (_parse(o.$2.text) ?? 0));
                              final max = _parse(_max.text) ?? 0;
                              return tr('Klasik toplam {0} puan · test kısmı {1} puan üzerinden hesaplanır · tam puan {2}', [_num(sum), _num((max - sum).clamp(0, max).toDouble()), _num(max)]);
                            }(),
                      style: t.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    for (var i = 0; i < _open.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _open[i].$1,
                              decoration: InputDecoration(labelText: tr('Soru adı'), hintText: tr('Klasik {0}', [i + 1])),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _open[i].$2,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(labelText: tr('Puan')),
                            ),
                          ),
                          IconButton(
                            tooltip: tr('Kaldır'),
                            onPressed: () => setState(() => _open.removeAt(i)),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _open.add((
                              TextEditingController(text: tr('Klasik {0}', [_open.length + 1])),
                              TextEditingController(text: '10'),
                            ))),
                        icon: const Icon(Icons.add),
                        label: Text(tr('Klasik soru ekle')),
                      ),
                    ),
                  ]),
                ),
              ),
              SectionTitle(tr('Sorular'),
                  trailing: TextButton.icon(
                    onPressed: _fromPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(tr('Anahtarı fotoğraftan oku')),
                  )),
              Text(tr('Doğru şıkka dokunun; birden çok şık seçerseniz hepsi doğru sayılır. Puan ağırlıklı sorular içindir.'),
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
                              decoration: InputDecoration(labelText: tr('Puan'), isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _codes[i],
                              decoration: InputDecoration(labelText: tr('Kazanım / konu'), isDense: true),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            Switch(
                              value: _qs[i].cancelled,
                              activeThumbColor: NColors.coral,
                              onChanged: (v) => setState(() => _qs[i] = _qs[i].copyWith(cancelled: v)),
                            ),
                            Text(tr('İptal'), style: t.textTheme.labelSmall),
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
