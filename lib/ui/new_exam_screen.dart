import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/report.dart';
import '../main.dart';
import 'exam_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Hızlı sınav oluşturma: soru sayısı, şık sayısı, cevap anahtarı tuş takımı.
/// Klavyeden "ABCDE…" yazmak da çalışır.
class NewExamScreen extends StatefulWidget {
  const NewExamScreen({super.key});

  @override
  State<NewExamScreen> createState() => _NewExamScreenState();
}

class _NewExamScreenState extends State<NewExamScreen> {
  final _name = TextEditingController();
  final _class = TextEditingController();
  final _outcomes = TextEditingController();
  final _focus = FocusNode();
  int _count = 20;
  int _choices = 5;
  int _wrongsPerCorrect = 0;
  final List<int?> _key = List.filled(100, null);
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classes = StoreScope.of(context).classNames;
      if (classes.isNotEmpty && _class.text.isEmpty) _class.text = classes.first;
    });
  }

  void _set(int choice) {
    setState(() {
      _key[_cursor] = choice;
      if (_cursor < _count - 1) _cursor++;
    });
  }

  bool get _complete => List.generate(_count, (i) => _key[i]).every((k) => k != null);

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return toast(context, 'Sınava bir ad verin.');
    if (!_complete) return toast(context, 'Cevap anahtarında boş soru var.');
    final outcomes = parseOutcomeRanges(_outcomes.text, _count);
    final exam = Exam(
      id: 'e${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      className: _class.text.trim(),
      date: DateTime.now(),
      choiceCount: _choices,
      questions: [
        for (var i = 0; i < _count; i++) Question(no: i + 1, correct: {_key[i]!}, outcomeCode: outcomes[i + 1])
      ],
      rule: ScoringRule(wrongsPerCorrect: _wrongsPerCorrect),
    );
    StoreScope.of(context).upsertExam(exam);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ExamScreen(examId: exam.id)));
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni sınav')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _save, child: const Text('Sınavı kaydet')),
              ),
            ),
          ),
        ),
      ),
      body: Watermark(child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Sınav adı', hintText: 'ör. Fizik Quiz 3')),
            const SizedBox(height: 12),
            TextField(controller: _class, decoration: const InputDecoration(labelText: 'Sınıf / şube', hintText: 'ör. 9-A')),
            const SizedBox(height: 20),
            Text('Soru sayısı: $_count', style: t.textTheme.titleSmall),
            Slider(
              value: _count.toDouble(),
              min: 5,
              max: 100,
              divisions: 95,
              label: '$_count',
              onChanged: (v) => setState(() {
                _count = v.round();
                if (_cursor >= _count) _cursor = _count - 1;
              }),
            ),
            Row(children: [
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 4, label: Text('4 şık')), ButtonSegment(value: 5, label: Text('5 şık'))],
                  selected: {_choices},
                  onSelectionChanged: (s) => setState(() {
                    _choices = s.first;
                    for (var i = 0; i < _key.length; i++) {
                      if ((_key[i] ?? 0) >= _choices) _key[i] = null;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _wrongsPerCorrect,
                  decoration: const InputDecoration(labelText: 'Yanlış götürme'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Yok')),
                    DropdownMenuItem(value: 3, child: Text('3 yanlış 1 doğru')),
                    DropdownMenuItem(value: 4, child: Text('4 yanlış 1 doğru')),
                  ],
                  onChanged: (v) => setState(() => _wrongsPerCorrect = v ?? 0),
                ),
              ),
            ]),
            SectionTitle('Cevap anahtarı', trailing: Text('Klavyeden A–${letter(_choices - 1)} de yazabilirsiniz', style: t.textTheme.bodySmall)),
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
            const SectionTitle('Kazanımlar / konular (isteğe bağlı)'),
            TextField(
              controller: _outcomes,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '1-5 Hareket\n6-10 Kuvvet',
                helperText: 'Her satıra soru aralığı ve konu adı yazın. Raporda konu bazlı başarı gösterilir.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      )),
    );
  }
}
