import 'package:material_ui/material_ui.dart';

import '../core/grade_scale.dart';
import '../core/report.dart';
import '../core/store.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Not sistemi: hazır bir ülke sistemi seçilir ya da düzeyler ve yüzde
/// sınırları elle yazılır. Raporlar, karneler ve düzey dağılımı bunu kullanır.
class GradeScaleScreen extends StatefulWidget {
  const GradeScaleScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GradeScaleScreen()));

  @override
  State<GradeScaleScreen> createState() => _GradeScaleScreenState();
}

class _Row {
  final TextEditingController label;
  final TextEditingController min;
  _Row(String l, double m) : label = TextEditingController(text: l), min = TextEditingController(text: _num(m));
  void dispose() {
    label.dispose();
    min.dispose();
  }
}

String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

class _GradeScaleScreenState extends State<GradeScaleScreen> {
  /// null = uygulama dilinin sistemi; 'custom' = elle; diğerleri hazır sistem.
  String? _id;
  final List<_Row> _rows = [];
  String? _error;

  AppStore get _store => context.findAncestorWidgetOfExactType<StoreScope>()!.notifier!;

  @override
  void initState() {
    super.initState();
    final s = _store.gradeScale;
    _id = s?.id;
    _load(s == null ? [for (final l in Level.languageDefault) GradeBand(l.name, l.minPct)] : s.bands);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _load(List<GradeBand> bands) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..addAll([for (final b in bands) _Row(b.label, b.minPct)]);
    _error = null;
  }

  void _pick(String? id) {
    setState(() {
      _id = id;
      if (id == null) {
        _load([for (final l in Level.languageDefault) GradeBand(l.name, l.minPct)]);
      } else if (id != 'custom') {
        _load(GradeScale.presets.firstWhere((p) => p.id == id).bands);
      }
    });
  }

  /// Düzeyde bir şey değişince sistem "özel" olur.
  void _edited() {
    if (_id != 'custom') setState(() => _id = 'custom');
  }

  List<GradeBand> get _bands => [
        for (var i = 0; i < _rows.length; i++)
          GradeBand(
            _rows[i].label.text.trim(),
            i == _rows.length - 1 ? 0 : (double.tryParse(_rows[i].min.text.replaceAll(',', '.').trim()) ?? -1),
          ),
      ];

  void _save() {
    if (_id == null) {
      _store.setGradeScale(null);
      toast(context, tr('Not sistemi kaydedildi.'));
      Navigator.pop(context);
      return;
    }
    final bands = _bands;
    final err = GradeScale.validate(bands);
    if (err != null) {
      setState(() => _error = switch (err) {
            'label' => tr('Her düzeye bir ad yazın.'),
            'few' => tr('En az {0} düzey olmalı.', [GradeScale.minBands]),
            _ => tr('Sınırlar yukarıdan aşağıya küçülmeli ve 0 ile 100 arasında olmalı.'),
          });
      return;
    }
    final preset = GradeScale.presets.where((p) => p.id == _id).firstOrNull;
    _store.setGradeScale(GradeScale(id: _id!, name: preset?.name ?? tr('Özel not sistemi'), bands: bands));
    toast(context, tr('Not sistemi kaydedildi.'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Not sistemi'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(tr('Kaydet')),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Text(
              tr('Öğrencinin puanı, tam puanın yüzdesine göre bu düzeylere yerleşir. Raporlar, karneler ve düzey dağılımı bu sistemi kullanır.'),
              style: TextStyle(color: muted),
            ),
            SectionTitle(tr('Hazır sistemler')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(label: Text(tr('Uygulama dilinin sistemi')), selected: _id == null, onSelected: (_) => _pick(null)),
                  for (final p in GradeScale.presets) ChoiceChip(label: Text(p.name), selected: _id == p.id, onSelected: (_) => _pick(p.id)),
                  ChoiceChip(
                    avatar: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(tr('Kendim yazacağım')),
                    selected: _id == 'custom',
                    onSelected: (_) => _pick('custom'),
                  ),
                ]),
              ),
            ),
            SectionTitle(tr('Düzeyler')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(tr('Düzey / not'), style: TextStyle(fontWeight: FontWeight.w700, color: muted))),
                    SizedBox(width: 96, child: Text(tr('En az %'), style: TextStyle(fontWeight: FontWeight.w700, color: muted))),
                    const SizedBox(width: 40),
                  ]),
                  const SizedBox(height: 6),
                  for (var i = 0; i < _rows.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Container(
                          width: 10,
                          height: 40,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: _color(i, _rows.length), borderRadius: BorderRadius.circular(4)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _rows[i].label,
                            enabled: _id != null,
                            onChanged: (_) => _edited(),
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 88,
                          child: i == _rows.length - 1
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Text(tr('geri kalan'), style: TextStyle(color: muted)),
                                )
                              : TextField(
                                  controller: _rows[i].min,
                                  enabled: _id != null,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => _edited(),
                                  decoration: const InputDecoration(isDense: true, prefixText: '% '),
                                ),
                        ),
                        SizedBox(
                          width: 40,
                          child: _id != null && _rows.length > GradeScale.minBands
                              ? IconButton(
                                  tooltip: tr('Sil'),
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => setState(() {
                                    _rows.removeAt(i).dispose();
                                    _id = 'custom';
                                  }),
                                )
                              : null,
                        ),
                      ]),
                    ),
                  if (_id != null && _rows.length < GradeScale.maxBands)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          // Sondan bir önceki yere eklenir; en alttaki "kaldı" düzeyi yerinde kalır.
                          _rows.insert(_rows.length - 1, _Row('', 0));
                          _id = 'custom';
                        }),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(tr('Düzey ekle')),
                      ),
                    ),
                  if (_id == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(tr('Değiştirmek için bir hazır sistem ya da "Kendim yazacağım" seçin.'), style: TextStyle(color: muted, fontSize: 13)),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(_error!, style: const TextStyle(color: NColors.coral, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Örnek: "% 85" yazılan düzey, tam puanın %85 ve üzerini alanlara verilir. 20 veya 10 üzerinden puan için Sınav ayarlarında "Tam puan" değerini değiştirin.'),
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ]),
        ),
      ),
    );
  }

  static const _palette = [NColors.emerald, Color(0xFF34D399), NColors.amber, Color(0xFFF59E0B), NColors.coral];
  Color _color(int i, int n) => _palette[n <= 1 ? 0 : (i * (_palette.length - 1) / (n - 1)).round()];
}
