import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/key_import.dart';
import '../core/models.dart';
import '../core/report.dart';
import '../main.dart';
import 'exam_screen.dart';
import 'key_import_ui.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Hızlı sınav oluşturma: soru sayısı, şık sayısı, kitapçıklar, her
/// kitapçığın cevap anahtarı (tuş takımı, klavye, belge ya da görselden)
/// ve sınavın yapılacağı sınıflar.
class NewExamScreen extends StatefulWidget {
  const NewExamScreen({super.key});

  @override
  State<NewExamScreen> createState() => _NewExamScreenState();
}

class _NewExamScreenState extends State<NewExamScreen> {
  final _name = TextEditingController();
  final _otherClass = TextEditingController();
  final _outcomes = TextEditingController();
  final _focus = FocusNode();
  int _count = 20;
  int _choices = 5;
  int _wrongsPerCorrect = 0;
  int _booklets = 1;

  /// Düzenlenen kitapçık (0 = A).
  int _bk = 0;
  final List<List<int?>> _keys = List.generate(Exam.maxBooklets, (_) => List<int?>.filled(100, null));
  final List<int> _cursors = List.filled(Exam.maxBooklets, 0);
  final Set<String> _classes = {};
  final List<String> _typed = []; // Bu ekranda yazılarak eklenen sınıflar.
  DateTime _date = DateTime.now();

  List<int?> get _key => _keys[_bk];
  int get _cursor => _cursors[_bk];
  set _cursor(int v) => _cursors[_bk] = v;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: tr('Sınav tarihi'),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: tr('Sınav saati'),
    );
    if (t != null) setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classes = StoreScope.of(context).classNames;
      if (classes.isNotEmpty && _classes.isEmpty) setState(() => _classes.add(classes.first));
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _otherClass.dispose();
    _outcomes.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(int choice) {
    setState(() {
      _key[_cursor] = choice;
      if (_cursor < _count - 1) _cursor++;
    });
  }

  int _filled(int b) => List.generate(_count, (i) => _keys[b][i]).where((k) => k != null).length;

  Future<void> _import() async {
    final src = await pickKeySource(context);
    if (src == null || !mounted) return;
    final r = await importKey(context, src, questions: _count, choices: _choices, booklets: _booklets);
    if (r == null || !mounted) return;
    setState(() {
      // Belgedeki soru sayısı daha fazlaysa soru sayısını büyütür.
      var maxQ = 0;
      for (final k in r.keys.values) {
        for (var i = k.length - 1; i >= 0; i--) {
          if (k[i] != null) {
            if (i + 1 > maxQ) maxQ = i + 1;
            break;
          }
        }
      }
      for (final q in r.topics.keys) {
        if (q > maxQ) maxQ = q;
      }
      if (src != KeySource.neticeForm && maxQ > _count) _count = maxQ.clamp(5, 100);
      if (r.bookletCount > _booklets) _booklets = r.bookletCount.clamp(1, Exam.maxBooklets);
      for (final e in r.keys.entries) {
        if (e.key >= _booklets) continue;
        for (var i = 0; i < e.value.length && i < 100; i++) {
          if (e.value[i] != null) _keys[e.key][i] = e.value[i];
        }
        final empty = List.generate(_count, (i) => _keys[e.key][i]).indexOf(null);
        _cursors[e.key] = empty < 0 ? _count - 1 : empty;
      }
      if (r.topics.isNotEmpty) _outcomes.text = topicsToRanges(r.topics, _count);
      _bk = r.keys.keys.isEmpty ? _bk : r.keys.keys.reduce((a, b) => a < b ? a : b).clamp(0, _booklets - 1);
    });
    final parts = [
      for (var b = 0; b < _booklets; b++)
        if (r.keys.containsKey(b)) tr('{0}: {1}/{2}', [Exam.bookletLetter(b), _filled(b), _count]),
    ];
    toast(
      context,
      [
        if (parts.isNotEmpty) tr('Okunan cevaplar: {0}.', [parts.join(', ')]),
        if (r.topics.isNotEmpty) tr('{0} sorunun konusu Kazanımlar bölümüne yerleştirildi.', [r.topics.length]),
        tr('Lütfen kontrol edin.'),
      ].join(' '),
    );
  }

  static List<String> _split(String text) =>
      [for (final c in text.split(RegExp(r'[,;\n]'))) if (c.trim().isNotEmpty) c.trim()];

  List<String> get _selectedClasses {
    final out = [..._classes];
    for (final c in _split(_otherClass.text)) {
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  /// Yazılan sınıfları ("9-A, 9-B") düğme olarak ekler ve seçer.
  void _addTyped() {
    final names = _split(_otherClass.text);
    if (names.isEmpty) return;
    setState(() {
      for (final c in names) {
        if (!_typed.contains(c)) _typed.add(c);
        _classes.add(c);
      }
      _otherClass.clear();
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return toast(context, tr('Sınava bir ad verin.'));
    for (var b = 0; b < _booklets; b++) {
      if (_filled(b) < _count) {
        setState(() => _bk = b);
        return toast(
          context,
          _booklets > 1
              ? tr('{0} kitapçığının cevap anahtarında boş soru var.', [Exam.bookletLetter(b)])
              : tr('Cevap anahtarında boş soru var.'),
        );
      }
    }
    final outcomes = parseOutcomeRanges(_outcomes.text, _count);
    final classes = _selectedClasses;
    if (classes.isEmpty) classes.add('');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final commonId = classes.length > 1 ? 'ortak_${stamp.toRadixString(36)}' : null;
    final store = StoreScope.of(context);
    final exams = <Exam>[
      for (var c = 0; c < classes.length; c++)
        Exam(
          id: classes.length == 1 ? 'e$stamp' : 'e${stamp}_$c',
          name: name,
          className: classes[c],
          date: _date,
          choiceCount: _choices,
          questions: [
            for (var i = 0; i < _count; i++) Question(no: i + 1, correct: {_keys[0][i]!}, outcomeCode: outcomes[i + 1])
          ],
          rule: ScoringRule(wrongsPerCorrect: _wrongsPerCorrect),
          // Her kitapçığın kendi anahtarı var; soru sıraları birebir tutulur.
          bookletOrders: [
            for (var b = 1; b < _booklets; b++) [for (var i = 0; i < _count; i++) i]
          ],
          bookletKeys: [
            for (var b = 1; b < _booklets; b++) [for (var i = 0; i < _count; i++) {_keys[b][i]!}]
          ],
          commonId: commonId,
          numberDigits: 10,
        ),
    ];
    for (final e in exams) {
      store.upsertExam(e);
    }
    if (exams.length > 1) {
      toast(context, tr('{0} sınıf için sınav oluşturuldu. Sonuçlar ortak raporda birleşir.', [exams.length]));
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ExamScreen(examId: exams.first.id)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final label = e.logicalKey.keyLabel.toUpperCase();
    if (label.length == 1) {
      final i = label.codeUnitAt(0) - 65;
      if (i >= 0 && i < _choices) {
        _set(i);
        return KeyEventResult.handled;
      }
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace && _cursor > 0) {
      setState(() => _key[--_cursor] = null);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft && _cursor > 0) {
      setState(() => _cursor--);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight && _cursor < _count - 1) {
      setState(() => _cursor++);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _classPicker(ThemeData t) {
    final all = [...StoreScope.of(context).classNames];
    for (final c in _typed) {
      if (!all.contains(c)) all.add(c);
    }
    final allSelected = all.isNotEmpty && all.every(_classes.contains);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Sınavın yapılacağı sınıflar'), style: t.textTheme.titleSmall),
      const SizedBox(height: 6),
      if (all.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (all.length > 1)
            FilterChip(
              label: Text(tr('Tüm sınıflar')),
              selected: allSelected,
              onSelected: (v) => setState(() => v ? _classes.addAll(all) : _classes.clear()),
            ),
          for (final c in all)
            FilterChip(
              label: Text(c),
              selected: _classes.contains(c),
              onSelected: (v) => setState(() => v ? _classes.add(c) : _classes.remove(c)),
            ),
        ]),
        const SizedBox(height: 6),
      ],
      TextField(
        controller: _otherClass,
        onChanged: (v) => v.contains(',') ? _addTyped() : setState(() {}),
        onSubmitted: (_) => _addTyped(),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: all.isEmpty ? tr('Sınıf / şube') : tr('Başka sınıf / şube ekle'),
          hintText: tr('ör. 9-A, 9-B, 9-C'),
          helperText: tr('Birden çok sınıf için virgülle ayırın.'),
          suffixIcon: IconButton(
            tooltip: tr('Ekle'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _addTyped,
          ),
        ),
      ),
      if (_selectedClasses.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            tr('Her sınıf için aynı sınav oluşturulur; sonuçlar ortak raporda birleşir.'),
            style: t.textTheme.bodySmall,
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final letterMax = letter(_choices - 1);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yeni sınav'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _save, child: Text(tr('Sınavı kaydet'))),
              ),
            ),
          ),
        ),
      ),
      body: Watermark(child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: tr('Sınav adı'), hintText: tr('ör. Fizik Quiz 3'))),
            const SizedBox(height: 12),
            _classPicker(t),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(dmy(_date)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(hm(_date)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Text(tr('Soru sayısı: {0}', [_count]), style: t.textTheme.titleSmall),
            NumberStepper(
              value: _count,
              min: 5,
              max: 100,
              semanticLabel: tr('Soru sayısı'),
              onChanged: (v) => setState(() {
                _count = v;
                for (var b = 0; b < Exam.maxBooklets; b++) {
                  if (_cursors[b] >= _count) _cursors[b] = _count - 1;
                }
              }),
            ),
            const SizedBox(height: 12),
            // Dar ekranlarda ve uzun çevirilerde taşmasın diye alt alta.
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [ButtonSegment(value: 4, label: Text(tr('4 şık'))), ButtonSegment(value: 5, label: Text(tr('5 şık')))],
                selected: {_choices},
                onSelectionChanged: (s) => setState(() {
                  _choices = s.first;
                  for (final k in _keys) {
                    for (var i = 0; i < k.length; i++) {
                      if ((k[i] ?? 0) >= _choices) k[i] = null;
                    }
                  }
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _wrongsPerCorrect,
                decoration: InputDecoration(labelText: tr('Yanlış götürme')),
                items: [
                  DropdownMenuItem(value: 0, child: Text(tr('Yok'))),
                  DropdownMenuItem(value: 3, child: Text(tr('3 yanlış 1 doğru'))),
                  DropdownMenuItem(value: 4, child: Text(tr('4 yanlış 1 doğru'))),
                ],
                onChanged: (v) => setState(() => _wrongsPerCorrect = v ?? 0),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('kitapcik_$_booklets'),
                isExpanded: true,
                initialValue: _booklets,
                decoration: InputDecoration(labelText: tr('Kitapçık türü')),
                items: [
                  for (var n = 1; n <= Exam.maxBooklets; n++)
                    DropdownMenuItem(
                      value: n,
                      child: Text(n == 1
                          ? tr('Tek kitapçık')
                          : tr('{0} kitapçık ({1})', [n, List.generate(n, Exam.bookletLetter).join(', ')])),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _booklets = v ?? 1;
                  if (_bk >= _booklets) _bk = 0;
                }),
              ),
            ]),
            SectionTitle(tr('Cevap anahtarı'),
                trailing: TextButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(tr('Görselden / belgeden oku')),
                )),
            if (_booklets > 1) ...[
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (var b = 0; b < _booklets; b++)
                  ChoiceChip(
                    selected: b == _bk,
                    avatar: _filled(b) == _count ? Icon(Icons.check_circle_rounded, size: 18, color: b == _bk ? NColors.onGreen : NColors.emerald) : null,
                    label: Text(tr('{0} kitapçığı · {1}/{2}', [Exam.bookletLetter(b), _filled(b), _count])),
                    onSelected: (_) => setState(() => _bk = b),
                  ),
              ]),
              const SizedBox(height: 6),
            ],
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                _booklets > 1
                    ? tr('Her kitapçığın cevaplarını ayrı girin: üstten kitapçığı seçip tuşlarla veya klavyeden A–{0} yazın. Cevap anahtarı belgesini (PDF, Word, Excel) ya da fotoğrafını yüklerseniz tüm kitapçıklar otomatik dolar.',
                        [letterMax])
                    : tr('Tuşlarla veya klavyeden A–{0} yazın. Cevap anahtarı belgesini (PDF, Word, Excel) ya da fotoğrafını yüklerseniz cevaplar otomatik dolar.',
                        [letterMax]),
                style: t.textTheme.bodySmall,
              ),
            ),
            Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (var i = 0; i < _count; i++)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _cursor = i),
                        child: Container(
                          width: 54,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: i == _cursor ? NColors.emerald : t.colorScheme.outlineVariant,
                                width: i == _cursor ? 2 : 1),
                          ),
                          child: Column(children: [
                            Text('${i + 1}', style: t.textTheme.labelSmall),
                            Text(_key[i] == null ? '·' : letter(_key[i]!),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              for (var c = 0; c < _choices; c++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      height: 64,
                      child: OutlinedButton(
                        onPressed: () => _set(c),
                        child: Text(letter(c), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
            ]),
            SectionTitle(tr('Kazanımlar / konular (isteğe bağlı)')),
            TextField(
              controller: _outcomes,
              minLines: 2,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: tr('1-5 Hareket\n6-10 Kuvvet'),
                helperText: tr('Her satıra soru aralığı ve konu adı yazın. Yüklediğiniz belgede konu dağılımı varsa buraya kendiliğinden yerleşir. Raporda konu bazlı başarı gösterilir.'),
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      )),
    );
  }
}
