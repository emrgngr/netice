import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/scoring.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Klasik (açık uçlu) soru puanlarının girişi. Her değişiklik anında kaydedilir.
class OpenScoresScreen extends StatefulWidget {
  final String examId;
  const OpenScoresScreen({super.key, required this.examId});

  @override
  State<OpenScoresScreen> createState() => _OpenScoresScreenState();
}

class _OpenScoresScreenState extends State<OpenScoresScreen> {
  final _ctrl = <String, List<TextEditingController>>{};
  final _sheets = <String, Sheet>{};

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', L10n.decimal);

  String _key(Sheet s, int i) => '${s.studentId ?? 'x'}#$i';

  void _changed(Exam exam, String key, int q, String text) {
    final store = StoreScope.of(context);
    final old = _sheets[key]!;
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    final scores = [
      for (var i = 0; i < exam.openQuestions.length; i++) i < old.openScores.length ? old.openScores[i] : null
    ];
    scores[q] = text.trim().isEmpty ? null : v?.clamp(0, exam.openQuestions[q].maxPoints).toDouble();
    final updated = old.copyWith(openScores: scores);
    store.replaceSheet(old, updated);
    _sheets[key] = updated;
    setState(() {});
  }

  @override
  void dispose() {
    for (final l in _ctrl.values) {
      for (final c in l) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = store.examById(widget.examId)!;
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final byId = store.studentById;
    final sheets = store.sheetsOf(exam.id)
      ..sort((a, b) => (int.tryParse(byId[a.studentId]?.number ?? '') ?? 1 << 30)
          .compareTo(int.tryParse(byId[b.studentId]?.number ?? '') ?? 1 << 30));
    final entries = [for (var i = 0; i < sheets.length; i++) (_key(sheets[i], i), sheets[i])];
    for (final (key, sheet) in entries) {
      _sheets.putIfAbsent(key, () => sheet);
      _ctrl.putIfAbsent(
        key,
        () => [
          for (var q = 0; q < exam.openQuestions.length; q++)
            TextEditingController(
                text: q < sheet.openScores.length && sheet.openScores[q] != null ? _num(sheet.openScores[q]!) : '')
        ],
      );
    }
    final done = entries.where((e) => !Scorer.score(exam, _sheets[e.$1]!).openMissing).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Klasik puan girişi')),
          Text(tr('{0} · {1} / {2} öğrenci tamam', [exam.name, done, entries.length]),
              style: t.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
      body: Watermark(
        child: entries.isEmpty
            ? Center(child: Text(tr('Önce kâğıtları okutun; klasik puanlar okunan kâğıtlara eklenir.')))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                Text(
                  tr('Her sorunun puanını yazın, kendiliğinden kaydedilir. Test kısmı {0}, klasik kısım {1} puan.', [_num(exam.testMax), _num(exam.openMax)]),
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                for (final (key, _) in entries)
                  () {
                    final sheet = _sheets[key]!;
                    final r = Scorer.score(exam, sheet);
                    final st = byId[sheet.studentId];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(st?.fullName ?? tr('Eşleşmeyen kâğıt'),
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('${st?.number ?? ''} · test ${_num(r.testScore)}',
                                    style: TextStyle(color: muted, fontSize: 12)),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(_num(r.score),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                      fontFeatures: tabular,
                                      color: r.openMissing ? muted : NColors.emerald)),
                              Text(r.openMissing ? tr('eksik') : tr('toplam'), style: TextStyle(color: muted, fontSize: 11)),
                            ]),
                          ]),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (var q = 0; q < exam.openQuestions.length; q++)
                              SizedBox(
                                width: 92,
                                child: TextField(
                                  controller: _ctrl[key]![q],
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textInputAction: TextInputAction.next,
                                  onChanged: (v) => _changed(exam, key, q, v),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: exam.openQuestions[q].label,
                                    suffixText: '/${_num(exam.openQuestions[q].maxPoints)}',
                                    errorText: () {
                                      final v = double.tryParse(_ctrl[key]![q].text.trim().replaceAll(',', '.'));
                                      if (_ctrl[key]![q].text.trim().isEmpty) return null;
                                      if (v == null) return tr('sayı');
                                      if (v > exam.openQuestions[q].maxPoints) return tr('en çok {0}', [_num(exam.openQuestions[q].maxPoints)]);
                                      return null;
                                    }(),
                                  ),
                                ),
                              ),
                          ]),
                        ]),
                      ),
                    );
                  }(),
              ]),
      ),
    );
  }
}
