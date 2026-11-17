import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

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
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 56, color: NColors.emerald),
          SizedBox(height: 8),
          Text('Kontrol bekleyen işaret yok.'),
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
    StoreScope.of(context).replaceSheet(widget.sheet, widget.sheet.copyWith(studentId: studentId));
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
      final candidates = store.studentsOf(exam.className).where((s) => !taken.contains(s.id)).toList();
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text('Bu kâğıttaki öğrenci numarası okunamadı ya da listede yok.', style: t.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Kâğıt kimin? (${widget.remaining} kâğıt kontrol bekliyor)', style: t.textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final s in candidates)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(title: Text(s.fullName), subtitle: Text(s.number), onTap: () => _assignStudent(s.id)),
          ),
        if (candidates.isEmpty) const Text('Listede kâğıdı okunmamış öğrenci kalmadı. Öğrenci listesini kontrol edin.'),
      ]);
    }

    final qIndex = sheet.answers.indexWhere((a) => a.needsReview);
    final a = sheet.answers[qIndex];
    final reason = a.state == MarkState.multiple
        ? 'İki ya da daha fazla şık dolu görünüyor.'
        : 'İşaret silik ya da yarım silinmiş görünüyor.';

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
            Text('${student.fullName} · ${qIndex + 1}. soru',
                style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(reason, style: const TextStyle(color: NColors.amber)),
            Text('${widget.remaining} kâğıt kontrol bekliyor', style: t.textTheme.bodySmall),
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
            Text('Okunan: ${answerText(a)}. Doğru karar hangisi?', textAlign: TextAlign.center),
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
              Expanded(child: OutlinedButton(onPressed: () => _decide(qIndex, {}), child: const Text('Boş say'))),
              const SizedBox(width: 10),
              if (a.marked.length > 1)
                Expanded(child: OutlinedButton(onPressed: () => _decide(qIndex, a.marked), child: const Text('Geçersiz (çift)'))),
            ]),
            const SizedBox(height: 12),
            Text('Kısayol: A–${letter(exam.choiceCount - 1)} tuşları, boş için boşluk.',
                textAlign: TextAlign.center, style: t.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
