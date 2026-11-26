import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../bank/bank_models.dart';
import '../../bank/bank_store.dart';
import '../../core/doc_text.dart';
import '../../core/spreadsheet.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';

/// Hazır kazanım listeleri: resmi müfredatın kazanımlarını bir kez içe
/// aktarın; soru ve sınav etiketlerinde öneri olarak çıksın.
class OutcomeListsScreen extends StatelessWidget {
  const OutcomeListsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OutcomeListsScreen()));

  Future<void> _fromFile(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: tr('Kazanım listesi seçin'),
        type: FileType.custom,
        allowedExtensions: [...spreadsheetExtensions, 'pdf', 'docx', 'txt'],
      );
      if (files.isEmpty || !context.mounted) return;
      final f = files.first;
      final bytes = await f.readAsBytes();
      final lower = f.name.toLowerCase();
      List<(String, String)> items;
      if (spreadsheetExtensions.any((e) => lower.endsWith('.$e'))) {
        final sheets = spreadsheetSheets(bytes, f.name) ?? const [];
        items = [for (final (_, rows) in sheets) ...OutcomeList.parseRows(rows)];
      } else {
        items = OutcomeList.parseLines(documentText(bytes, f.name));
      }
      if (!context.mounted) return;
      final name = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      await _confirm(context, name, items);
    } catch (e) {
      if (context.mounted) toast(context, tr('Dosya okunamadı: {0}', [e]));
    }
  }

  Future<void> _paste(BuildContext context) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Kazanımları yapıştırın')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: c,
            minLines: 8,
            maxLines: 16,
            decoration: InputDecoration(
              hintText: tr('Her satıra bir kazanım:\nM.5.1.1.1 Milyonlu sayıları okur ve yazar.\nM.5.1.1.2 Sayı örüntüleri oluşturur.'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Devam'))),
        ],
      ),
    );
    if (text == null || !context.mounted) return;
    await _confirm(context, tr('Yeni liste'), OutcomeList.parseLines(text));
  }

  Future<void> _confirm(BuildContext context, String suggested, List<(String, String)> items) async {
    if (items.isEmpty) return toast(context, tr('Kazanım bulunamadı. Her satırda bir kazanım olmalı; Excel\'de "Kod" ve "Kazanım" sütunları.'));
    final name = TextEditingController(text: suggested);
    final subject = TextEditingController();
    final grade = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('{0} kazanım bulundu', [items.length])),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in items.take(4))
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${OutcomeList.labelOf(e)}', maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (items.length > 4) Text(tr('… ve {0} kazanım daha', [items.length - 4])),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: InputDecoration(labelText: tr('Listenin adı'))),
              const SizedBox(height: 8),
              SuggestField(controller: subject, label: tr('Ders (isteğe bağlı)'), icon: Icons.menu_book_outlined, options: () => bank.subjects),
              const SizedBox(height: 8),
              SuggestField(controller: grade, label: tr('Sınıf / düzey (isteğe bağlı)'), icon: Icons.stairs_outlined, options: () => bank.grades),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Kaydet'))),
        ],
      ),
    );
    if (ok != true) return;
    bank.upsertOutcomeList(OutcomeList(
      id: BankStore.newId('o'),
      name: name.text.trim().isEmpty ? tr('Kazanım listesi') : name.text.trim(),
      subject: subject.text.trim(),
      grade: grade.text.trim(),
      items: items,
      created: DateTime.now(),
    ));
    if (context.mounted) toast(context, tr('Kazanım listesi kaydedildi.'));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: bank,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('Kazanım listeleri'))),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const IconBadge(Icons.account_tree_outlined, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr('Ülkenizin ya da programınızın (MEB, Cambridge, IB, Common Core…) kazanım listesini bir kez ekleyin. Soru yazarken ve sınav kazanımlarını girerken kodlar öneri olarak çıkar; raporlar aynı kodlarla birleşir. Excel, PDF, Word ya da düz metin okunur.'),
                          style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.75)),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton.icon(onPressed: () => _fromFile(context), icon: const Icon(Icons.upload_file_rounded), label: Text(tr('Dosyadan ekle'))),
                  FilledButton.tonalIcon(onPressed: () => _paste(context), icon: const Icon(Icons.content_paste_rounded), label: Text(tr('Yapıştırarak ekle'))),
                ]),
                const SizedBox(height: 16),
                if (bank.outcomeLists.isEmpty)
                  Text(tr('Henüz liste yok.'), style: t.textTheme.bodyMedium)
                else
                  for (final l in bank.outcomeLists)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: const Icon(Icons.list_alt_rounded),
                        title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([tr('{0} kazanım', [l.items.length]), if (l.subject.isNotEmpty) l.subject, if (l.grade.isNotEmpty) l.grade].join(' · ')),
                        trailing: IconButton(
                          tooltip: tr('Sil'),
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(tr('"{0}" silinsin mi?', [l.name])),
                                content: Text(tr('Sorularınızdaki kazanım etiketleri silinmez; yalnız öneri listesi kalkar.')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sil'))),
                                ],
                              ),
                            );
                            if (ok == true) bank.deleteOutcomeList(l.id);
                          },
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: [
                          for (final e in l.items.take(50))
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text.rich(TextSpan(children: [
                                  if (e.$1.isNotEmpty) TextSpan(text: '${e.$1}  ', style: const TextStyle(fontWeight: FontWeight.w800, color: NColors.emerald)),
                                  TextSpan(text: e.$2),
                                ])),
                              ),
                            ),
                          if (l.items.length > 50) Text(tr('… ve {0} kazanım daha', [l.items.length - 50])),
                        ],
                      ),
                    ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
