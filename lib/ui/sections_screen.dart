// Çok dersli deneme sınavı: ders bölümlerini (ad, soru sayısı, katsayı) ve
// ağırlıklı puanın taban puanını düzenler. Kaydedince sonuçlar yeniden
// hesaplanır; kâğıtları yeniden okutmak gerekmez.
import 'package:material_ui/material_ui.dart';

import '../core/deneme.dart';
import '../core/models.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

class SectionsScreen extends StatefulWidget {
  final String examId;
  const SectionsScreen({super.key, required this.examId});

  static Future<void> open(BuildContext context, String examId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectionsScreen(examId: examId)));

  @override
  State<SectionsScreen> createState() => _SectionsScreenState();
}

class _Row {
  final TextEditingController name;
  final TextEditingController count;
  final TextEditingController weight;
  _Row(String n, int c, double w)
      : name = TextEditingController(text: n),
        count = TextEditingController(text: c > 0 ? '$c' : ''),
        weight = TextEditingController(text: _num(w));
  void dispose() {
    name.dispose();
    count.dispose();
    weight.dispose();
  }
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', L10n.decimal);
double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

class _SectionsScreenState extends State<SectionsScreen> {
  late Exam _exam;
  final List<_Row> _rows = [];
  late bool _weighted;
  late final TextEditingController _base;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _exam = StoreScope.of(context).examById(widget.examId)!;
    for (final s in _exam.sections) {
      _add(s.name, s.count, s.weight);
    }
    if (_rows.isEmpty) {
      final half = _exam.questionCount ~/ 2;
      _add('', half, 1);
      _add('', _exam.questionCount - half, 1);
    }
    _weighted = _exam.baseScore != null;
    _base = TextEditingController(text: _num(_exam.baseScore ?? 100))..addListener(() => setState(() {}));
    _loaded = true;
  }

  void _add(String n, int c, double w) {
    final r = _Row(n, c, w);
    for (final t in [r.name, r.count, r.weight]) {
      t.addListener(() => setState(() {}));
    }
    _rows.add(r);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _base.dispose();
    super.dispose();
  }

  int get _sum => _rows.fold(0, (a, r) => a + (int.tryParse(r.count.text.trim()) ?? 0));

  void _applyPreset(DenemePreset p) => setState(() {
        for (final r in _rows) {
          r.dispose();
        }
        _rows.clear();
        for (final part in p.parts) {
          _add(part.$1, part.$2, 1);
        }
      });

  List<ExamSection>? _build({bool quiet = false}) {
    final parts = <(String, int, double)>[];
    for (final r in _rows) {
      final c = int.tryParse(r.count.text.trim());
      final w = _weighted ? _parse(r.weight.text) : 0.0;
      if (c == null || c <= 0) {
        if (!quiet) toast(context, tr('"{0}" dersinin soru sayısı en az 1 olmalı.', [r.name.text.trim()]));
        return null;
      }
      if (w == null || w < 0) {
        if (!quiet) toast(context, tr('Katsayılar 0 ya da daha büyük bir sayı olmalı.'));
        return null;
      }
      parts.add((r.name.text.trim(), c, w));
    }
    final list = ExamSection.fromCounts(parts);
    final err = ExamSection.validate(list, _exam.questionCount);
    if (err != null) {
      if (!quiet) toast(context, err);
      return null;
    }
    return list;
  }

  void _save() {
    final store = StoreScope.of(context);
    if (_rows.length < 2) return toast(context, tr('Deneme sınavı için en az iki ders ekleyin.'));
    final list = _build();
    if (list == null) return;
    final base = _weighted ? _parse(_base.text) : null;
    if (_weighted && (base == null || base < 0)) return toast(context, tr('Taban puan geçerli bir sayı olmalı.'));
    final latest = store.examById(widget.examId) ?? _exam;
    store.upsertExam(latest.copyWith(sections: list, baseScore: base, clearBaseScore: !_weighted));
    toast(context, tr('Kaydedildi; sonuçlar ders ders yeniden hesaplandı.'));
    Navigator.pop(context);
  }

  void _clear() {
    final store = StoreScope.of(context);
    final latest = store.examById(widget.examId) ?? _exam;
    store.upsertExam(latest.copyWith(sections: const [], clearBaseScore: true));
    toast(context, tr('Ders bölümleri kaldırıldı.'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final sum = _sum;
    final ok = sum == _exam.questionCount;
    final presets = [for (final p in denemePresets()) if (p.total == _exam.questionCount) p];
    // Satırların soru aralıkları (1'den).
    var at = 1;
    final ranges = <String>[];
    for (final r in _rows) {
      final c = int.tryParse(r.count.text.trim()) ?? 0;
      ranges.add(c > 0 ? tr('Soru {0}–{1}', [at, at + c - 1]) : '');
      at += c;
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ders bölümleri')), actions: [
        if (_exam.sections.isNotEmpty)
          TextButton(onPressed: _clear, child: Text(tr('Kaldır'))),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(onPressed: _save, child: Text(tr('Kaydet ve yeniden hesapla'))),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(
              tr('Birden çok dersin tek kitapçıkta olduğu deneme sınavlarında her öğrencinin ders ders doğru, yanlış ve netini, toplam netini ve sırasını görürsünüz. Dersleri kitapçıktaki sırasıyla yazın.'),
              style: TextStyle(color: muted, height: 1.4),
            ),
            if (presets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in presets)
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(tr('{0} düzeni', [p.label])),
                    onPressed: () => _applyPreset(p),
                  ),
              ]),
            ],
            SectionTitle(tr('Dersler')),
            for (var i = 0; i < _rows.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _rows[i].name,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(labelText: tr('{0}. ders', [i + 1]), hintText: tr('Örn. Matematik')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _rows[i].count,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: tr('Soru')),
                        ),
                      ),
                      if (_weighted) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _rows[i].weight,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: tr('Katsayı')),
                          ),
                        ),
                      ],
                      IconButton(
                        tooltip: tr('Dersi kaldır'),
                        onPressed: _rows.length <= 1
                            ? null
                            : () => setState(() => _rows.removeAt(i).dispose()),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ]),
                    if (ranges[i].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(ranges[i], style: t.textTheme.bodySmall?.copyWith(color: muted)),
                      ),
                  ]),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _add('', (_exam.questionCount - sum).clamp(0, _exam.questionCount), 1)),
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Ders ekle')),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Toplam {0} / {1} soru', [sum, _exam.questionCount]),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: ok ? (t.brightness == Brightness.dark ? NColors.emerald : NColors.deepEmerald) : t.colorScheme.error,
              ),
            ),
            SectionTitle(tr('Ağırlıklı puan')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SwitchListTile(
                  value: _weighted,
                  onChanged: (v) => setState(() => _weighted = v),
                  title: Text(tr('Katsayılı puan hesapla'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('Puan = taban puan + her dersin neti × katsayısı. Sıralama bu puana göre yapılır.')),
                ),
                if (_weighted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: _base,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: tr('Taban puan')),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Resmî sınavlarda puan, adayların ortalamasına ve standart sapmasına göre hesaplanır. Buradaki puan bir tahmindir; katsayıları kendiniz belirleyin.'),
                        style: t.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
