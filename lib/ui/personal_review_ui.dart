import 'package:material_ui/material_ui.dart';

import '../bank/bank_store.dart';
import '../bank/personal_review.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import '../reports/review_pdf.dart';
import 'pro_screen.dart';
import 'report_preview_screen.dart';
import 'widgets.dart';

String _safe(String s) => s.replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ -]'), '').replaceAll(' ', '_');

/// "Kişiye özel tekrar testi": ayarları sorar, PDF önizlemesini açar.
Future<void> openPersonalReview(BuildContext context, Exam exam, {String? onlyStudentId}) async {
  final store = StoreScope.of(context);
  final results = store.resultsOf(exam);
  if (results.isEmpty) return toast(context, tr('Tekrar testi için önce kâğıt okutun.'));
  final bank = BankStore.instance;
  if (PersonalReview.coverableTopics(exam, bank) == 0) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.assignment_ind_outlined),
        title: Text(tr('Benzer soru bulunamadı')),
        content: Text(tr('Tekrar testi, sınavdaki soruların konusuna (kazanımına) uyan soruları soru bankanızdan seçer. Sınav ayarlarında sorulara kazanım yazın ya da sınavı Kütüphane\'den kitapçıkla oluşturun; bankada aynı konudan sorular olsun.')),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Tamam')))],
      ),
    );
    return;
  }
  if (!await requirePro(context, ProFeature.personalReview) || !context.mounted) return;

  var per = 10;
  var optical = false;
  var key = true;
  var seed = 1;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final reviews = PersonalReview.build(exam, results, store.studentById, bank,
          o: ReviewOptions(perStudent: per, opticalOnly: optical, seed: seed), only: onlyStudentId == null ? null : {onlyStudentId});
      final total = reviews.fold(0, (a, r) => a + r.questions.length);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Kişiye özel tekrar testi'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Her öğrenciye, yanlış yaptığı ya da boş bıraktığı soruların konusundan, soru bankanızdaki benzer sorular seçilir. Konunun hap bilgisi de eklenir.')),
            const SizedBox(height: 14),
            Text(tr('Öğrenci başına soru'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final n in const [5, 10, 15, 20])
                ChoiceChip(label: Text('$n'), selected: per == n, onSelected: (_) => set(() => per = n)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: optical,
              onChanged: (v) => set(() => optical = v),
              title: Text(tr('Yalnız çoktan seçmeli sorular')),
              subtitle: Text(tr('Klasik ve boşluk doldurma sorular eklenmez')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: key,
              onChanged: (v) => set(() => key = v),
              title: Text(tr('Sona öğretmen için cevap anahtarı ekle')),
            ),
            Card(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: Text(reviews.isEmpty
                    ? tr('Bu ayarlarla test çıkan öğrenci yok')
                    : tr('{0} öğrenciye toplam {1} soru', [reviews.length, total])),
                subtitle: Text(tr('Eksiği olmayan ya da eksik konusu bankada bulunmayan öğrenciler atlanır.')),
                trailing: IconButton(
                  tooltip: tr('Soruları yeniden karıştır'),
                  icon: const Icon(Icons.shuffle_rounded),
                  onPressed: () => set(() => seed++),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç')))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: reviews.isEmpty ? null : () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(tr('Testleri oluştur')),
                ),
              ),
            ]),
          ]),
        ),
      );
    }),
  );
  if (ok != true || !context.mounted) return;
  final reviews = PersonalReview.build(exam, results, store.studentById, bank,
      o: ReviewOptions(perStudent: per, opticalOnly: optical, seed: seed), only: onlyStudentId == null ? null : {onlyStudentId});
  await ReportPreviewScreen.open(
    context,
    title: tr('Kişiye özel tekrar testi'),
    fileName: '${_safe(exam.name)}_tekrar_testi.pdf',
    build: () => buildPersonalReviewPdf(
      reviews,
      exam: exam,
      school: store.reportSchool,
      image: (id) => bank.imageFile(id)?.readAsBytesSync(),
      tipsFor: (t) => bank.notesFor(t),
      answerKey: key,
    ),
  );
}

