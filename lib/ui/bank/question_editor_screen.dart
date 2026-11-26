import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../bank/bank_models.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';
import 'image_tools.dart';

/// Soru ekleme / düzenleme.
class QuestionEditorScreen extends StatefulWidget {
  final BankQuestion? question;
  const QuestionEditorScreen({super.key, this.question});

  static Future<void> open(BuildContext context, [BankQuestion? q]) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuestionEditorScreen(question: q)));

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  late BankQuestion _q = widget.question ?? bank.newQuestion();
  late final bool _isNew = widget.question == null;

  late final _text = TextEditingController(text: _q.text);
  late final _answer = TextEditingController(text: _q.answerText);
  late final _solution = TextEditingController(text: _q.solution);
  late final _subject = TextEditingController(text: _q.subject);
  late final _grade = TextEditingController(text: _q.grade);
  late final _topic = TextEditingController(text: _q.topic);
  late final _outcome = TextEditingController(text: _q.outcome);
  late final _tags = TextEditingController(text: _q.tags.join(', '));
  late final _source = TextEditingController(text: _q.source);
  late final _points = TextEditingController(text: _q.points <= 0 ? '' : fmt2(_q.points).replaceAll(RegExp(r'[.,]00$'), ''));
  late final List<TextEditingController> _choices = [
    for (var i = 0; i < (_q.choices.isNotEmpty ? _q.choices.length : _q.choiceCount); i++)
      TextEditingController(text: i < _q.choices.length ? _q.choices[i] : ''),
  ];
  late final List<TextEditingController> _mis = [
    for (var i = 0; i < 5; i++) TextEditingController(text: i < _q.misconceptions.length ? _q.misconceptions[i] : ''),
  ];
  late bool _showMis = _q.misconceptions.any((m) => m.trim().isNotEmpty);
  late final List<TextEditingController> _items = [for (final t in _q.items) TextEditingController(text: t)];
  late List<int> _keys = [for (var i = 0; i < _q.items.length; i++) i < _q.itemKeys.length ? _q.itemKeys[i] : -1];
  bool _dirty = false;

  @override
  void dispose() {
    for (final c in [_text, _answer, _solution, _subject, _grade, _topic, _outcome, _tags, _source, _points, ..._choices, ..._items, ..._mis]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(BankQuestion q) => setState(() {
        _q = q;
        _dirty = true;
      });

  BankQuestion _collect() {
    final texts = [for (final c in _choices) c.text.trim()];
    final hasText = texts.any((t) => t.isNotEmpty);
    final ty = _q.type;
    final withChoices = ty == QuestionType.multiple || ty == QuestionType.matching || ty == QuestionType.wordBank;
    // Boş maddeler atılır; cevapları da onlarla birlikte.
    final items = <String>[], keys = <int>[];
    if (ty.hasItems || ty == QuestionType.multiple) {
      for (var i = 0; i < _items.length; i++) {
        final t = _items[i].text.trim();
        if (t.isEmpty) continue;
        items.add(t);
        keys.add(i < _keys.length ? _keys[i] : -1);
      }
    }
    return _q.copyWith(
      text: _text.text.trim(),
      choices: withChoices && hasText ? texts : const [],
      choiceCount: switch (ty) {
        QuestionType.multiple || QuestionType.matching || QuestionType.wordBank => _choices.length,
        QuestionType.ordering => _q.choiceCount.clamp(2, 5),
        _ => 2,
      },
      items: items,
      itemKeys: ty.grouped ? keys : const [],
      misconceptions: ty == QuestionType.multiple
          ? (() {
              final m = [for (var i = 0; i < _choices.length; i++) _q.correct.contains(i) ? '' : _mis[i].text.trim()];
              return m.any((t) => t.isNotEmpty) ? m : const <String>[];
            })()
          : const <String>[],
      answerText: _answer.text.trim(),
      solution: _solution.text.trim(),
      subject: _subject.text.trim(),
      grade: _grade.text.trim(),
      topic: _topic.text.trim(),
      outcome: _outcome.text.trim(),
      tags: [for (final t in _tags.text.split(RegExp(r'[,;]'))) if (t.trim().isNotEmpty) t.trim()],
      source: _source.text.trim(),
      points: double.tryParse(_points.text.trim().replaceAll(',', '.')) ?? 0,
    );
  }

  Future<void> _save({bool another = false}) async {
    final q = _collect();
    if (q.type.grouped) {
      if (q.items.length < 2) return toast(context, tr('En az iki madde yazın.'));
      if (q.type != QuestionType.trueFalseTable && q.choices.where((c) => c.isNotEmpty).length < 2) {
        return toast(context, tr('En az iki seçenek yazın.'));
      }
      if (!q.complete) return toast(context, tr('Her maddenin doğru cevabını seçin.'));
    } else if (q.type == QuestionType.ordering) {
      if (q.items.length < 3) return toast(context, tr('Sıralama için en az üç adım yazın.'));
    } else {
      if (q.text.isEmpty && q.imageId == null) return toast(context, tr('Soru metnini yazın ya da bir görsel ekleyin.'));
      if (q.type.optical && q.correct.isEmpty) return toast(context, tr('Doğru cevabı işaretleyin.'));
    }
    bank.upsertQuestion(q);
    _dirty = false;
    if (!mounted) return;
    if (another) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const QuestionEditorScreen()));
      toast(context, tr('Soru kaydedildi.'));
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _pickImage({bool solution = false}) async {
    final b = await pickBankImage(context);
    if (b == null) return;
    final id = await bank.saveImage(b);
    _set(solution ? _q.copyWith(solutionImageId: id) : _q.copyWith(imageId: id));
  }

  void _setType(QuestionType t) {
    var q = _q.copyWith(type: t);
    if (t == QuestionType.trueFalse) q = q.copyWith(correct: q.correct.where((c) => c < 2).toSet());
    if (t == QuestionType.ordering && q.choiceCount > 4) q = q.copyWith(choiceCount: 4);
    // Madde listeli türlerde birkaç boş satırla başlanır.
    final want = switch (t) {
      QuestionType.ordering => 4,
      QuestionType.matching || QuestionType.wordBank || QuestionType.trueFalseTable => 4,
      _ => 0,
    };
    while (_items.length < want) {
      _items.add(TextEditingController());
    }
    if (t == QuestionType.trueFalseTable) _keys = [for (final k in _keys) k == 1 ? 1 : 0];
    _syncKeys();
    _set(q);
  }

  void _syncKeys() {
    while (_keys.length < _items.length) {
      _keys.add(_q.type == QuestionType.trueFalseTable ? 0 : -1);
    }
    if (_keys.length > _items.length) _keys = _keys.sublist(0, _items.length);
  }

  void _addItem() {
    if (_items.length >= 10) return;
    setState(() {
      _items.add(TextEditingController());
      _syncKeys();
      _dirty = true;
    });
  }

  void _removeItem(int i) {
    setState(() {
      _items.removeAt(i).dispose();
      if (i < _keys.length) _keys.removeAt(i);
      _dirty = true;
    });
  }

  void _setKey(int i, int k) {
    _syncKeys();
    setState(() {
      _keys[i] = k;
      _dirty = true;
    });
  }

  void _toggleCorrect(int i) {
    final c = {..._q.correct};
    if (c.contains(i)) {
      c.remove(i);
    } else {
      // Tek doğru cevap olağandır; birden çok doğru için uzun basılır.
      c
        ..clear()
        ..add(i);
    }
    _set(_q.copyWith(correct: c));
  }

  void _toggleExtraCorrect(int i) {
    final c = {..._q.correct};
    c.contains(i) ? c.remove(i) : c.add(i);
    _set(_q.copyWith(correct: c));
    toast(context, tr('Birden çok doğru cevap: {0}', [c.map(letter).join(', ')]));
  }

  void _addChoice() {
    if (_choices.length >= 5) return;
    setState(() {
      _choices.add(TextEditingController());
      _dirty = true;
    });
  }

  void _removeChoice() {
    if (_choices.length <= 2) return;
    setState(() {
      _choices.removeLast().dispose();
      _q = _q.copyWith(correct: _q.correct.where((c) => c < _choices.length).toSet());
      _dirty = true;
    });
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Değişiklikler kaydedilsin mi?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(tr('Kaydetme'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Kaydet'))),
        ],
      ),
    );
    if (r == 'save') {
      await _save();
      return false;
    }
    return r == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final main = <Widget>[
      _card(
        icon: Icons.category_outlined,
        title: tr('Soru türü'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final ty in QuestionType.values)
              ChoiceChip(
                avatar: Icon(typeIcon(ty), size: 18),
                label: Text(ty.label),
                selected: _q.type == ty,
                onSelected: (_) => _setType(ty),
              ),
          ]),
          const SizedBox(height: 10),
          Text(_q.type.hint, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65))),
        ]),
      ),
      _card(
        icon: Icons.help_outline_rounded,
        title: tr('Soru'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _dirty = true,
            decoration: InputDecoration(
              hintText: switch (_q.type) {
                QuestionType.fill => tr('Boşluğu ____ ile gösterin. Ör: Türkiye\'nin başkenti ____ şehridir.'),
                QuestionType.matching => tr('Yönerge (boşsa: Maddeleri uygun seçenekle eşleştiriniz.)'),
                QuestionType.trueFalseTable => tr('Yönerge (boşsa: İfadeler doğru mu, yanlış mı? İşaretleyiniz.)'),
                QuestionType.wordBank => tr('Yönerge (boşsa: Boşlukları kutudaki sözcüklerle doldurunuz.)'),
                QuestionType.ordering => tr('Soru kökü. Ör: Bir bitkinin büyüme adımlarının doğru sıralaması hangisidir?'),
                _ => tr('Soru kökünü yazın (görsel eklediyseniz boş bırakabilirsiniz)'),
              },
            ),
          ),
          const SizedBox(height: 12),
          _imageRow(_q.imageId, onPick: () => _pickImage(), onRemove: () => _set(_q.copyWith(clearImage: true))),
        ]),
      ),
      if (_q.type == QuestionType.matching || _q.type == QuestionType.wordBank) _choicesCard(t, wordBank: _q.type == QuestionType.wordBank),
      if (_q.type.hasItems || _q.type == QuestionType.multiple) _itemsCard(t),
      if (!_q.type.hasItems) _answerCard(t),
    ];
    final side = <Widget>[
      _card(
        icon: Icons.signal_cellular_alt_rounded,
        title: tr('Zorluk'),
        child: SegmentedButton<Difficulty>(
          showSelectedIcon: false,
          segments: [
            for (final d in Difficulty.values)
              ButtonSegment(value: d, label: Text(d.label), icon: Icon(Icons.circle, size: 10, color: difficultyColor(d))),
          ],
          selected: {_q.difficulty},
          onSelectionChanged: (s) => _set(_q.copyWith(difficulty: s.first)),
        ),
      ),
      _card(
        icon: Icons.psychology_alt_outlined,
        title: tr('Düşünme düzeyi'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in CognitiveLevel.levels)
              ChoiceChip(
                label: Text(l.label),
                selected: _q.cognitive == l,
                onSelected: (on) => _set(_q.copyWith(cognitive: on ? l : CognitiveLevel.none)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(
            _q.cognitive == CognitiveLevel.none
                ? tr('İsteğe bağlı. Belirtke tablosu, sınavın ezber mi yorum mu ağırlıklı olduğunu bununla gösterir.')
                : _q.cognitive.hint,
            style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
        ]),
      ),
      _card(
        icon: Icons.account_tree_outlined,
        title: tr('Ders ve konu'),
        child: Column(children: [
          SuggestField(controller: _subject, label: tr('Ders'), icon: Icons.menu_book_outlined, options: () => bank.subjects, onChanged: (_) => _dirty = true),
          const SizedBox(height: 10),
          SuggestField(controller: _grade, label: tr('Sınıf / düzey'), icon: Icons.stairs_outlined, options: () => bank.grades, onChanged: (_) => _dirty = true),
          const SizedBox(height: 10),
          SuggestField(controller: _topic, label: tr('Konu / ünite'), icon: Icons.topic_outlined, options: () => bank.topicsOf(_subject.text.trim()), onChanged: (_) => _dirty = true),
          const SizedBox(height: 10),
          SuggestField(controller: _outcome, label: tr('Kazanım (isteğe bağlı)'), icon: Icons.flag_outlined, options: () => bank.outcomesOf(_subject.text.trim()), onChanged: (_) => _dirty = true),
        ]),
      ),
      _card(
        icon: Icons.sell_outlined,
        title: tr('Diğer bilgiler'),
        child: Column(children: [
          TextField(
            controller: _tags,
            onChanged: (_) => _dirty = true,
            decoration: InputDecoration(labelText: tr('Etiketler'), hintText: tr('virgülle ayırın: deneme, LGS, tekrar'), prefixIcon: const Icon(Icons.tag_rounded)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _source,
            onChanged: (_) => _dirty = true,
            decoration: InputDecoration(labelText: tr('Kaynak (isteğe bağlı)'), prefixIcon: const Icon(Icons.bookmark_border_rounded)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _points,
            onChanged: (_) => _dirty = true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: tr('Puan ağırlığı (isteğe bağlı)'),
              helperText: tr('Boşsa kitapçıkta puanlar eşit dağıtılır'),
              prefixIcon: const Icon(Icons.scoreboard_outlined),
            ),
          ),
        ]),
      ),
      _card(
        icon: Icons.lightbulb_outline_rounded,
        title: tr('Çözüm (isteğe bağlı)'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _solution,
            minLines: 2,
            maxLines: 10,
            onChanged: (_) => _dirty = true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: tr('Çözümlü kitapçıkta sorunun altına basılır')),
          ),
          const SizedBox(height: 10),
          _imageRow(_q.solutionImageId,
              onPick: () => _pickImage(solution: true), onRemove: () => _set(_q.copyWith(clearSolutionImage: true))),
        ]),
      ),
    ];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        if (await _confirmLeave() && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? tr('Yeni soru') : tr('Soruyu düzenle')),
          actions: [
            if (!_isNew)
              IconButton(
                tooltip: tr('Favori'),
                icon: Icon(_q.favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: _q.favorite ? NColors.amber : null),
                onPressed: () => _set(_q.copyWith(favorite: !_q.favorite)),
              ),
            if (_isNew)
              TextButton(onPressed: () => _save(another: true), child: Text(tr('Kaydet ve yeni'))),
            Padding(
              padding: const EdgeInsets.only(right: 10, left: 4),
              child: FilledButton(onPressed: _save, child: Text(tr('Kaydet'))),
            ),
          ],
        ),
        body: SafeArea(
          child: wide
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: ListView(padding: const EdgeInsets.all(16), children: main)),
                      Expanded(flex: 2, child: ListView(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), children: side)),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 32), children: [...main, ...side]),
        ),
      ),
    );
  }

  Widget _choicesCard(ThemeData t, {required bool wordBank}) => _card(
        icon: wordBank ? Icons.inventory_2_outlined : Icons.list_alt_rounded,
        title: wordBank ? tr('Sözcük havuzu') : tr('Seçenekler (sağ sütun)'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: tr('Şık sil'), onPressed: _choices.length > 2 ? _removeChoice : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('${_choices.length}', style: t.textTheme.titleMedium?.copyWith(fontFeatures: tabular)),
          IconButton(tooltip: tr('Şık ekle'), onPressed: _choices.length < 5 ? _addChoice : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('En çok 5 seçenek (optik formda A–E). Seçenek sayısı maddelerden fazla olabilir.'),
              style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 10),
          for (var i = 0; i < _choices.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 28, child: Text(letter(i), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Expanded(
                  child: TextField(
                    controller: _choices[i],
                    onChanged: (_) => setState(() => _dirty = true),
                    decoration: InputDecoration(isDense: true, hintText: wordBank ? tr('Sözcük') : tr('{0} seçeneği', [letter(i)])),
                  ),
                ),
              ]),
            ),
        ]),
      );

  Widget _itemsCard(ThemeData t) {
    final ty = _q.type;
    _syncKeys();
    final (icon, title, help) = switch (ty) {
      QuestionType.matching => (Icons.compare_arrows_rounded, tr('Maddeler (sol sütun)'), tr('Her maddenin karşısında eşleştiği seçeneği seçin.')),
      QuestionType.trueFalseTable => (Icons.fact_check_rounded, tr('İfadeler'), tr('Her ifade için Doğru ya da Yanlış seçin.')),
      QuestionType.wordBank =>
        (Icons.space_bar_rounded, tr('Cümleler'), tr('Boşluğu ____ ile gösterin ve gelecek sözcüğü seçin.')),
      QuestionType.ordering => (Icons.format_list_numbered_rounded, tr('Adımlar (doğru sırayla)'),
          tr('Adımları doğru sırayla yazın. Kitapçıkta karışık basılır, şıklar otomatik üretilir.')),
      _ => (Icons.format_list_numbered_rounded, tr('Öncüller (isteğe bağlı)'), tr('I, II, III diye basılır. Ör: "Yalnız I", "I ve III" gibi şıklarla kullanılır.')),
    };
    final options = [for (var i = 0; i < _choices.length; i++) i];
    return _card(
      icon: icon,
      title: title,
      trailing: IconButton(tooltip: tr('Madde ekle'), onPressed: _items.length < 10 ? _addItem : null, icon: const Icon(Icons.add_circle_outline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(help, style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 10),
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(
                width: 34,
                child: Text(ty == QuestionType.multiple ? itemLabel(i) : '${i + 1}.',
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Expanded(
                child: TextField(
                  controller: _items[i],
                  onChanged: (_) => _dirty = true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(isDense: true, hintText: tr('{0}. madde', [i + 1])),
                ),
              ),
              if (ty == QuestionType.matching || ty == QuestionType.wordBank) ...[
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: options.contains(_keys[i]) ? _keys[i] : null,
                  hint: Text(tr('Cevap')),
                  items: [for (final k in options) DropdownMenuItem(value: k, child: Text(letter(k)))],
                  onChanged: (k) => k == null ? null : _setKey(i, k),
                ),
              ],
              if (ty == QuestionType.trueFalseTable) ...[
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [ButtonSegment(value: 0, label: Text(tr('D'))), ButtonSegment(value: 1, label: Text(tr('Y')))],
                  selected: {_keys[i] == 1 ? 1 : 0},
                  onSelectionChanged: (s) => _setKey(i, s.first),
                ),
              ],
              IconButton(tooltip: tr('Sil'), onPressed: () => _removeItem(i), icon: const Icon(Icons.close_rounded, size: 20)),
            ]),
          ),
        if (ty == QuestionType.ordering) ...[
          const SizedBox(height: 6),
          Text(tr('Kitapçıktaki şık sayısı'), style: t.textTheme.labelLarge),
          NumberStepper(
            value: _q.choiceCount.clamp(2, 5),
            min: 2,
            max: 5,
            semanticLabel: tr('Şık'),
            onChanged: (v) => _set(_q.copyWith(choiceCount: v)),
          ),
        ],
      ]),
    );
  }

  Widget _answerCard(ThemeData t) {
    switch (_q.type) {
      case QuestionType.multiple:
        return _card(
          icon: Icons.checklist_rounded,
          title: tr('Şıklar'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: tr('Şık sil'), onPressed: _choices.length > 2 ? _removeChoice : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('${_choices.length}', style: t.textTheme.titleMedium?.copyWith(fontFeatures: tabular)),
            IconButton(tooltip: tr('Şık ekle'), onPressed: _choices.length < 5 ? _addChoice : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Doğru şıkkın harfine dokunun. Şıklar görseldeyse metin kutularını boş bırakın.'),
                style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            for (var i = 0; i < _choices.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  _LetterButton(i, on: _q.correct.contains(i), onTap: () => _toggleCorrect(i), onLong: () => _toggleExtraCorrect(i)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _choices[i],
                      onChanged: (_) => _dirty = true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(isDense: true, hintText: tr('{0} şıkkı', [letter(i)])),
                    ),
                  ),
                ]),
              ),
              if (_showMis && !_q.correct.contains(i))
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 50, bottom: 10),
                  child: TextField(
                    controller: _mis[i],
                    onChanged: (_) => _dirty = true,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.psychology_outlined, size: 18, color: NColors.amber),
                      hintText: tr('{0} şıkkını seçen hangi yanılgıda? Ör: Paydaları topluyor', [letter(i)]),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showMis,
              onChanged: (v) => setState(() => _showMis = v),
              title: Text(tr('Kavram yanılgılarını yaz')),
              subtitle: Text(tr('Her yanlış şıkkın hangi yanılgıyı yakaladığını yazın; raporlar "kaç öğrenci bu yanılgıda" diye gösterir.')),
            ),
          ]),
        );
      case QuestionType.trueFalse:
        return _card(
          icon: Icons.rule_rounded,
          title: tr('Doğru cevap'),
          child: Row(children: [
            for (final (i, label) in [(0, tr('Doğru')), (1, tr('Yanlış'))]) ...[
              Expanded(
                child: _BigToggle(
                  label: label,
                  icon: i == 0 ? Icons.check_circle_outline : Icons.cancel_outlined,
                  on: _q.correct.contains(i),
                  color: i == 0 ? NColors.emerald : NColors.coral,
                  onTap: () => _set(_q.copyWith(correct: {i})),
                ),
              ),
              if (i == 0) const SizedBox(width: 10),
            ],
          ]),
        );
      case QuestionType.fill:
        return _card(
          icon: Icons.short_text_rounded,
          title: tr('Cevap'),
          child: TextField(
            controller: _answer,
            onChanged: (_) => _dirty = true,
            decoration: InputDecoration(hintText: tr('Boşluğa gelecek cevap (cevap anahtarında görünür)')),
          ),
        );
      case QuestionType.open:
        return _card(
          icon: Icons.edit_note_rounded,
          title: tr('Cevap ve yazma alanı'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _answer,
              minLines: 2,
              maxLines: 8,
              onChanged: (_) => _dirty = true,
              decoration: InputDecoration(hintText: tr('Örnek cevap / puanlama ölçütü (cevap anahtarında görünür)')),
            ),
            const SizedBox(height: 14),
            Text(tr('Öğrencinin yazacağı satır sayısı'), style: t.textTheme.labelLarge),
            NumberStepper(
              value: _q.answerLines,
              min: 0,
              max: 30,
              semanticLabel: tr('Satır'),
              onChanged: (v) => _set(_q.copyWith(answerLines: v)),
            ),
          ]),
        );
      case QuestionType.matching || QuestionType.trueFalseTable || QuestionType.wordBank || QuestionType.ordering:
        return const SizedBox.shrink();
    }
  }

  Widget _imageRow(String? id, {required VoidCallback onPick, required VoidCallback onRemove}) {
    if (id == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(onPressed: onPick, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(tr('Görsel ekle'))),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: BankImage(id)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(onPressed: onPick, icon: const Icon(Icons.swap_horiz_rounded), label: Text(tr('Değiştir'))),
          TextButton.icon(
            onPressed: onRemove,
            style: TextButton.styleFrom(foregroundColor: NColors.coral),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(tr('Kaldır')),
          ),
        ]),
      ]),
    );
  }

  Widget _card({required IconData icon, required String title, required Widget child, Widget? trailing}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBadge(icon, size: 30),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

class _LetterButton extends StatelessWidget {
  final int i;
  final bool on;
  final VoidCallback onTap;
  final VoidCallback onLong;
  const _LetterButton(this.i, {required this.on, required this.onTap, required this.onLong});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tr('Doğru cevap olarak işaretle'),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLong,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? NColors.emerald : Colors.transparent,
              border: Border.all(color: on ? NColors.emerald : Theme.of(context).colorScheme.outline, width: 2),
            ),
            child: on
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                : Text(letter(i), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

class _BigToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  const _BigToggle({required this.label, required this.icon, required this.on, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? color : Theme.of(context).colorScheme.outlineVariant, width: on ? 2 : 1),
          ),
          child: Column(children: [
            Icon(icon, color: on ? color : null, size: 28),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: on ? color : null)),
          ]),
        ),
      );
}
