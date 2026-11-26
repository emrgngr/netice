import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../l10n/l10n.dart';
import 'theme.dart';
import 'widgets.dart';

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll('.', L10n.decimal);

/// Ölçüt (rubrik) düzenleyici: ölçüt adı, puanı ve dört düzeyin açıklaması.
/// Kaydedilince ölçüt listesini döndürür (boş liste: ölçütler kaldırıldı).
class RubricEditor extends StatefulWidget {
  final String title;
  final List<RubricCriterion> initial;
  final double suggestedTotal;
  const RubricEditor({super.key, required this.title, required this.initial, this.suggestedTotal = 10});

  static Future<List<RubricCriterion>?> open(BuildContext context,
          {required String title, required List<RubricCriterion> initial, double suggestedTotal = 10}) =>
      Navigator.of(context).push<List<RubricCriterion>>(MaterialPageRoute(
          fullscreenDialog: true, builder: (_) => RubricEditor(title: title, initial: initial, suggestedTotal: suggestedTotal)));

  @override
  State<RubricEditor> createState() => _RubricEditorState();
}

class _Row {
  final TextEditingController name, points;
  final List<TextEditingController> levels;
  _Row(RubricCriterion c)
      : name = TextEditingController(text: c.name),
        points = TextEditingController(text: _num(c.maxPoints)),
        levels = [for (var i = 0; i < RubricCriterion.levelCount; i++) TextEditingController(text: c.descriptor(i))];

  void dispose() {
    for (final c in [name, points, ...levels]) {
      c.dispose();
    }
  }
}

class _RubricEditorState extends State<RubricEditor> {
  late final List<_Row> _rows = [for (final c in widget.initial) _Row(c)];

  /// Hazır şablonlar: yaygın kullanılan yazılı anlatım ve problem çözme ölçütleri.
  static List<(String, List<String>)> get _presets => [
        (tr('Problem çözme'), [tr('Problemi anlama'), tr('Çözüm yolu'), tr('İşlem doğruluğu'), tr('Sonucu açıklama')]),
        (tr('Yazılı anlatım'), [tr('İçerik ve fikirler'), tr('Düzen ve akış'), tr('Dil ve anlatım'), tr('Yazım ve noktalama')]),
        (tr('Deney / proje'), [tr('Hipotez ve plan'), tr('Uygulama'), tr('Veri ve yorum'), tr('Sunum')]),
      ];

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  double get _total => _rows.fold(0.0, (a, r) => a + (double.tryParse(r.points.text.trim().replaceAll(',', '.')) ?? 0));

  void _preset(List<String> names) {
    final each = (widget.suggestedTotal / names.length * 100).round() / 100;
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll([for (final n in names) _Row(RubricCriterion(name: n, maxPoints: each))]);
    });
  }

  void _save() {
    final out = <RubricCriterion>[];
    for (final r in _rows) {
      final p = double.tryParse(r.points.text.trim().replaceAll(',', '.'));
      if (r.name.text.trim().isEmpty) return toast(context, tr('Her ölçüte bir ad verin.'));
      if (p == null || p <= 0) return toast(context, tr('"{0}" ölçütünün puanı geçerli değil.', [r.name.text.trim()]));
      out.add(RubricCriterion(name: r.name.text.trim(), maxPoints: p, descriptors: [for (final l in r.levels) l.text.trim()]));
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Ölçütler · {0}', [widget.title])),
        actions: [
          if (widget.initial.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(context, const <RubricCriterion>[]), child: Text(tr('Ölçütleri kaldır'))),
          Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: _save, child: Text(tr('Kaydet')))),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
              Text(
                tr('Her ölçüt dört düzeyde puanlanır: Başlangıç (%25), Gelişmekte (%50), Yeterli (%75), Örnek (%100). Düzey açıklamaları isteğe bağlıdır; yazarsanız karnede öğrenciye geri bildirim olarak görünür.'),
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (name, list) in _presets) ActionChip(avatar: const Icon(Icons.auto_awesome_outlined, size: 18), label: Text(name), onPressed: () => _preset(list)),
              ]),
              const SizedBox(height: 12),
              for (var i = 0; i < _rows.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _rows[i].name,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(labelText: tr('{0}. ölçüt', [i + 1]), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _rows[i].points,
                            onChanged: (_) => setState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: tr('Puan'), isDense: true),
                          ),
                        ),
                        IconButton(
                          tooltip: tr('Kaldır'),
                          onPressed: () => setState(() => _rows.removeAt(i).dispose()),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      for (var l = 0; l < RubricCriterion.levelCount; l++)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 8),
                          child: TextField(
                            controller: _rows[i].levels[l],
                            style: const TextStyle(fontSize: 13.5),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: SizedBox(
                                width: 104,
                                child: Center(
                                  child: Text(RubricCriterion.levelLabel(l),
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _levelColor(l))),
                                ),
                              ),
                              hintText: tr('Bu düzeyde öğrenci ne yapar? (isteğe bağlı)'),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              Row(children: [
                TextButton.icon(
                  onPressed: () => setState(() => _rows.add(_Row(const RubricCriterion(name: '', maxPoints: 2.5)))),
                  icon: const Icon(Icons.add),
                  label: Text(tr('Ölçüt ekle')),
                ),
                const Spacer(),
                Text(tr('Toplam: {0} puan', [_num(_total)]), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

Color _levelColor(int l) => switch (l) {
      0 => NColors.coral,
      1 => NColors.amber,
      2 => const Color(0xFF34D399),
      _ => NColors.emerald,
    };

/// Bir öğrencinin ölçütlü klasik sorusunu puanlama sayfası. Seçilen
/// düzeyleri döndürür (vazgeçilirse null).
Future<List<int>?> scoreWithRubric(BuildContext context, OpenQuestion q, List<int> current, {String? student}) {
  var levels = [for (var i = 0; i < q.rubric.length; i++) i < current.length ? current[i] : -1];
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final total = [for (var i = 0; i < q.rubric.length; i++) q.rubric[i].pointsAt(levels[i])].fold(0.0, (a, b) => a + b);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => SafeArea(
            child: Column(children: [
              Expanded(
                child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), children: [
                  Text(student == null ? q.label : '$student · ${q.label}',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  for (var i = 0; i < q.rubric.length; i++) ...[
                    Text('${q.rubric[i].name}  ·  ${_num(q.rubric[i].pointsAt(levels[i]))} / ${_num(q.rubric[i].maxPoints)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var l = 0; l < RubricCriterion.levelCount; l++)
                        Tooltip(
                          message: q.rubric[i].descriptor(l),
                          child: ChoiceChip(
                            label: Text(RubricCriterion.levelLabel(l)),
                            selected: levels[i] == l,
                            selectedColor: _levelColor(l).withValues(alpha: 0.25),
                            onSelected: (on) => set(() => levels[i] = on ? l : -1),
                          ),
                        ),
                    ]),
                    if (levels[i] >= 0 && q.rubric[i].descriptor(levels[i]).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(q.rubric[i].descriptor(levels[i]), style: Theme.of(ctx).textTheme.bodySmall),
                      ),
                    const SizedBox(height: 14),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(children: [
                  Text(tr('Toplam: {0} / {1}', [_num(total), _num(q.maxPoints)]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(ctx, levels), child: Text(tr('Kaydet'))),
                ]),
              ),
            ]),
          ),
        );
      },
    ),
  );
}
