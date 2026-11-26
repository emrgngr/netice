import 'package:material_ui/material_ui.dart';

import '../bank/bank_models.dart';
import '../core/mastery.dart';
import '../core/pro.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'bank/bank_widgets.dart' show bank;
import 'bank/booklet_wizard_screen.dart';
import 'pro_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bir sınıfın kazanım ustalığı ve hatırlatma (aralıklı tekrar) önerileri.
class MasteryScreen extends StatelessWidget {
  final String className;
  const MasteryScreen({super.key, required this.className});

  static Future<void> open(BuildContext context, String className) async {
    if (!await requirePro(context, ProFeature.mastery) || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MasteryScreen(className: className)));
  }

  static const _colors = {
    MasteryStatus.mastered: NColors.emerald,
    MasteryStatus.developing: NColors.amber,
    MasteryStatus.notYet: NColors.coral,
  };

  /// Bankadan bu kazanımlara ait sorular (her kazanımdan en çok [perOutcome]).
  static List<BankQuestion> reviewQuestions(List<String> codes, {int perOutcome = 2}) {
    final out = <BankQuestion>[];
    for (final c in codes) {
      final key = c.trim().toLowerCase();
      final pool = bank.questions
          .where((q) =>
              q.complete &&
              q.type.optical &&
              (q.topicLabel.toLowerCase() == key || q.outcome.trim().toLowerCase() == key || q.topic.trim().toLowerCase() == key))
          .toList()
        ..sort((a, b) => a.updated.compareTo(b.updated));
      out.addAll(pool.take(perOutcome));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final outcomes = Mastery.of(store, className);
    final now = DateTime.now();
    final due = Mastery.dueForReview(outcomes, now);
    final t = Theme.of(context);
    final students = store.studentsOf(className)..sort((a, b) => a.fullName.compareTo(b.fullName));
    final counts = {for (final s in MasteryStatus.values) s: outcomes.where((o) => o.status == s).length};

    Future<void> makeReview() async {
      final qs = reviewQuestions([for (final o in due) o.code]);
      if (qs.isEmpty) {
        return toast(context, tr('Soru bankasında bu kazanımlara ait soru bulunamadı. Sorularınıza aynı konu ya da kazanım adını yazın.'));
      }
      await BookletWizardScreen.open(context, questionIds: [for (final q in qs) q.id]);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Ustalık takibi')),
          Text(className, style: t.textTheme.bodySmall),
        ]),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const IconBadge(Icons.military_tech_outlined, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('Bir kazanım en az iki ayrı sınavda %80 ve üstü başarıyla "öğrenildi" sayılır. Öğrenilen kazanım 3 haftadır sorulmadıysa ya da son sınavda düştüyse, unutulmadan kısa bir hatırlatma testi önerilir.'),
                        style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.75)),
                      ),
                    ),
                  ]),
                ),
              ),
              if (outcomes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('Bu sınıfın sınavlarında kazanım ya da konu girilmemiş. Sınavda "Kazanımları gir" ile soruları kazanımlara bağlayın.')),
                )
              else ...[
                const SizedBox(height: 12),
                Row(children: [
                  for (final s in MasteryStatus.values)
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(children: [
                            Text('${counts[s]}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _colors[s])),
                            Text(s.label, style: t.textTheme.bodySmall),
                          ]),
                        ),
                      ),
                    ),
                ]),
                if (due.isNotEmpty) ...[
                  SectionTitle(tr('Hatırlatma zamanı gelenler')),
                  Card(
                    color: NColors.amber.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final o in due)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Icon(o.slipping ? Icons.trending_down_rounded : Icons.schedule_rounded, size: 18, color: NColors.amber),
                              const SizedBox(width: 8),
                              Expanded(child: Text(o.code, style: const TextStyle(fontWeight: FontWeight.w700))),
                              Text(o.slipping
                                  ? tr('düşüş: {0}', [L10n.percent((o.lastRate * 100).round())])
                                  : tr('{0} gündür sorulmadı', [now.difference(o.lastAssessed).inDays])),
                            ]),
                          ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: makeReview,
                          icon: const Icon(Icons.replay_rounded),
                          label: Text(tr('Hatırlatma testi hazırla')),
                        ),
                      ]),
                    ),
                  ),
                ],
                SectionTitle(tr('Kazanımlar')),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final o in outcomes)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.circle, size: 12, color: _colors[o.status]),
                        title: Text(o.code, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(tr('{0} · {1} sınavda soruldu · son: {2} · öğrenen öğrenci: {3}/{4}', [
                          o.status.label,
                          o.attempts.length,
                          L10n.percent((o.lastRate * 100).round()),
                          o.masteredStudents,
                          o.students.length,
                        ])),
                        trailing: SizedBox(
                          width: 90,
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            for (final a in o.attempts.length > 6 ? o.attempts.sublist(o.attempts.length - 6) : o.attempts)
                              Container(
                                width: 9,
                                height: 6 + 22 * a.$2,
                                margin: const EdgeInsets.only(left: 3),
                                decoration: BoxDecoration(
                                  color: a.$2 >= Mastery.threshold ? NColors.emerald : (a.$2 >= 0.5 ? NColors.amber : NColors.coral),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                          ]),
                        ),
                      ),
                  ]),
                ),
                SectionTitle(tr('Öğrenciler')),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final s in students)
                      () {
                        final (m, n) = Mastery.studentSummary(outcomes, s.id);
                        return ListTile(
                          dense: true,
                          title: Text(s.fullName),
                          subtitle: n == 0 ? Text(tr('Henüz ölçülmedi')) : null,
                          trailing: n == 0
                              ? null
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  SizedBox(
                                    width: 90,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(value: m / n, minHeight: 7, color: NColors.emerald),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('$m / $n', style: const TextStyle(fontWeight: FontWeight.w700)),
                                ]),
                        );
                      }(),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
