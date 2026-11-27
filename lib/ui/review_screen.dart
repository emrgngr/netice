import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Kontrol kuyruğu: belirsiz işaretler ve eşleşmeyen öğrenciler.
/// Sistem emin olmadığı hiçbir şeyi sessizce karara bağlamaz.
/// Masaüstünde A–E tuşlarıyla karar, boşluk ile "boş".
class ReviewList extends StatelessWidget {
  final Exam exam;
  const ReviewList({super.key, required this.exam});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final pending = store.sheetsOf(exam.id).where((s) => s.needsReview).toList();
    if (pending.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 56, color: NColors.emerald),
          SizedBox(height: 8),
          Text(tr('Kontrol bekleyen işaret yok.')),
        ]),
      );
    }
    final sheet = pending.first;
    return _ReviewCard(key: ValueKey(store.sheets.indexOf(sheet)), exam: exam, sheet: sheet, remaining: pending.length);
  }
}

class _ReviewCard extends StatefulWidget {
  final Exam exam;
  final Sheet sheet;
  final int remaining;
  const _ReviewCard({super.key, required this.exam, required this.sheet, required this.remaining});

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _decide(int qIndex, Set<int> marked) {
    final answers = [...widget.sheet.answers];
    answers[qIndex] = Answer(
      marked.isEmpty ? MarkState.blank : (marked.length > 1 ? MarkState.multiple : MarkState.filled),
      marked,
      confirmed: true,
    );
    StoreScope.of(context).replaceSheet(widget.sheet, widget.sheet.copyWith(answers: answers));
    HapticFeedback.selectionClick();
  }

  void _assignStudent(String studentId) {
    StoreScope.of(context).assignSheet(widget.sheet, studentId);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final exam = widget.exam;
    final sheet = widget.sheet;
    final student = store.studentById[sheet.studentId];

    if (student == null) {
      final taken = store.sheetsOf(exam.id).map((s) => s.studentId).toSet();
      final suggested = store.suggestStudents(sheet);
      final candidates = store
          .studentsOf(exam.className)
          .where((s) => !taken.contains(s.id) && !suggested.contains(s))
          .toList();
      final read = sheet.readNumber;
      final owner = store.conflictOwner(sheet);
      Widget tile(Student s, {bool best = false}) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: best ? NColors.emerald.withValues(alpha: 0.10) : null,
            shape: best
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: NColors.emerald.withValues(alpha: 0.5)),
                  )
                : null,
            child: ListTile(
              leading: best ? const Icon(Icons.auto_fix_high_rounded, color: NColors.emerald) : null,
              title: Text(s.fullName, style: TextStyle(fontWeight: best ? FontWeight.w700 : null)),
              subtitle: read == null ? Text(s.number) : _NumberDiff(read: read, number: s.number),
              trailing: best ? Text(tr('Bu öğrenci'), style: TextStyle(color: NColors.emerald, fontWeight: FontWeight.w700)) : null,
              onTap: () => _assignStudent(s.id),
            ),
          );
      final readName = sheet.readName;
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text(
            read == null
                ? tr('Bu kâğıttaki öğrenci numarası okunamadı.')
                : tr('Kâğıtta okunan numara: {0}', [read.replaceAll('?', '•')]),
            style: t.textTheme.titleMedium),
        if (readName != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('Kâğıtta okunan ad: {0}', [readName.replaceAll('?', '•')]), style: t.textTheme.titleMedium),
          ),
        const SizedBox(height: 4),
        Text(
            read != null && read.contains('?')
                ? tr('• ile gösterilen rakamlar okunamadı. Kâğıt kimin? ({0} kâğıt kontrol bekliyor)', [widget.remaining])
                : tr('Bu numara listede yok. Kâğıt kimin? ({0} kâğıt kontrol bekliyor)', [widget.remaining]),
            style: t.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (owner != null) ...[
          Card(
            color: NColors.amber.withValues(alpha: 0.12),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.swap_horiz_rounded, color: NColors.amber),
              title: Text(tr('{0} ({1}) için zaten bir kâğıt okunmuştu', [owner.fullName, owner.number]),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Cevaplar çok farklı. Bu kâğıt gerçekten onunsa öncekinin yerine geçirin; numarayı yanlış işaretleyen başka bir öğrenciyse aşağıdan seçin.')),
              isThreeLine: true,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _assignStudent(owner.id),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text(tr('{0} · öncekinin yerine geçsin', [owner.fullName])),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (suggested.isNotEmpty) ...[
          Text(tr('Önerilen'), style: t.textTheme.labelLarge?.copyWith(color: NColors.emerald, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final (i, s) in suggested.indexed) tile(s, best: i == 0),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Diğer öğrenciler'), style: t.textTheme.labelLarge),
            const SizedBox(height: 6),
          ],
        ],
        for (final s in candidates) tile(s),
        if (candidates.isEmpty && suggested.isEmpty)
          Text(tr('Listede kâğıdı okunmamış öğrenci kalmadı. Öğrenci listesini kontrol edin.')),
      ]);
    }

    final qIndex = sheet.answers.indexWhere((a) => a.needsReview);
    final a = sheet.answers[qIndex];
    final reason = a.state == MarkState.multiple
        ? tr('İki ya da daha fazla şık dolu görünüyor.')
        : tr('İşaret silik ya da yarım silinmiş görünüyor.');

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.space) {
          _decide(qIndex, {});
          return KeyEventResult.handled;
        }
        final l = e.logicalKey.keyLabel.toUpperCase();
        if (l.length == 1) {
          final i = l.codeUnitAt(0) - 65;
          if (i >= 0 && i < exam.choiceCount) {
            _decide(qIndex, {i});
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('${student.fullName} · ${tr('{0}. soru', [qIndex + 1])}',
                style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(reason, style: const TextStyle(color: NColors.amber)),
            Text(tr('{0} kâğıt kontrol bekliyor', [widget.remaining]), style: t.textTheme.bodySmall),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var c = 0; c < exam.choiceCount; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: t.colorScheme.outline),
                            color: a.marked.contains(c) ? NColors.amber.withValues(alpha: 0.35) : null,
                          ),
                          child: Text(letter(c), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text(tr('Okunan: {0}. Doğru karar hangisi?', [answerText(a)]), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(children: [
              for (var c = 0; c < exam.choiceCount; c++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      height: 60,
                      child: FilledButton(
                        style: a.marked.contains(c) ? null : FilledButton.styleFrom(backgroundColor: t.colorScheme.surfaceContainerHighest, foregroundColor: t.colorScheme.onSurface),
                        onPressed: () => _decide(qIndex, {c}),
                        child: Text(letter(c), style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _decide(qIndex, {}), child: Text(tr('Boş say')))),
              const SizedBox(width: 10),
              if (a.marked.length > 1)
                Expanded(child: OutlinedButton(onPressed: () => _decide(qIndex, a.marked), child: Text(tr('Geçersiz (çift)')))),
            ]),
            const SizedBox(height: 12),
            Text(tr('Kısayol: A–{0} tuşları, boş için boşluk.', [letter(exam.choiceCount - 1)]),
                textAlign: TextAlign.center, style: t.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// Eşleşmeyen kâğıt için kısa etiket (okunan numarayla).
String unmatchedLabel(Sheet s) {
  final r = s.readNumber;
  final base = r == null ? tr('Öğrenci eşleşmedi') : tr('Öğrenci eşleşmedi · no {0}', [r.replaceAll('?', '•')]);
  return s.readName == null ? base : '$base · ${s.readName!.replaceAll('?', '•')}';
}

/// Öğrenci numarasını, okunan numarayla farklı rakamları vurgulayarak gösterir.
class _NumberDiff extends StatelessWidget {
  final String read;
  final String number;
  const _NumberDiff({required this.read, required this.number});

  @override
  Widget build(BuildContext context) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || digits.length > read.length) return Text(number);
    final tail = read.substring(read.length - digits.length);
    final base = DefaultTextStyle.of(context).style.copyWith(fontFeatures: tabular);
    return Text.rich(TextSpan(children: [
      for (var i = 0; i < digits.length; i++)
        TextSpan(
          text: digits[i],
          style: tail[i] == '?' || tail[i] == digits[i]
              ? base
              : base.copyWith(color: NColors.coral, fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
        ),
    ]));
  }
}
