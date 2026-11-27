// Okuma parçası ekleme / düzenleme: birden çok sorunun ortak metni, grafiği
// ya da tablosu. Kitapçıkta parça bir kez basılır, bağlı sorular altında
// "X–Y. soruları aşağıdaki metne göre cevaplayınız" yönergesiyle sıralanır.
import 'package:material_ui/material_ui.dart';

import '../../bank/bank_models.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';
import 'image_tools.dart';

class PassageEditorScreen extends StatefulWidget {
  final BankPassage? passage;
  const PassageEditorScreen({super.key, this.passage});

  /// Parçayı açar; kaydedilirse parçayı döndürür.
  static Future<BankPassage?> open(BuildContext context, [BankPassage? p]) =>
      Navigator.of(context).push<BankPassage>(MaterialPageRoute(builder: (_) => PassageEditorScreen(passage: p)));

  @override
  State<PassageEditorScreen> createState() => _PassageEditorScreenState();
}

class _PassageEditorScreenState extends State<PassageEditorScreen> {
  late BankPassage _p = widget.passage ?? bank.newPassage();
  late final _title = TextEditingController(text: _p.title);
  late final _text = TextEditingController(text: _p.text);
  late final _subject = TextEditingController(text: _p.subject);

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final b = await pickBankImage(context);
    if (b == null) return;
    final id = await bank.saveImage(b);
    setState(() => _p = _p.copyWith(imageId: id));
  }

  void _save() {
    final p = _p.copyWith(title: _title.text.trim(), text: _text.text.trim(), subject: _subject.text.trim());
    if (p.isEmpty) return toast(context, tr('Parçanın metnini yazın ya da bir görsel ekleyin.'));
    bank.upsertPassage(p);
    Navigator.pop(context, p);
  }

  Future<void> _delete() async {
    final linked = bank.questionsOfPassage(_p.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Parça silinsin mi?')),
        content: Text(linked == 0
            ? tr('Bu parçaya bağlı soru yok.')
            : tr('{0} soru bu parçaya bağlı. Sorular silinmez, yalnız parçayla bağları kalkar.', [linked])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sil'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    bank.removePassage(_p.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final linked = widget.passage == null ? const <BankQuestion>[] : bank.questionsOfPassage(_p.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.passage == null ? tr('Yeni okuma parçası') : tr('Okuma parçası')),
        actions: [
          if (widget.passage != null) IconButton(tooltip: tr('Sil'), onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: FilledButton(onPressed: _save, child: Text(tr('Kaydet'))),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(
              tr('Okuma metni, grafik, tablo ya da harita gibi birden çok sorunun ortak kaynağı. Kitapçıkta bir kez basılır; bağlı sorular hemen altında birlikte gelir ve kitapçıklar karıştırılsa da ayrılmaz.'),
              style: TextStyle(color: muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(controller: _title, decoration: InputDecoration(labelText: tr('Başlık (isteğe bağlı)'), hintText: tr('Örn. Yağmur ormanları'))),
            const SizedBox(height: 12),
            SuggestField(controller: _subject, label: tr('Ders'), icon: Icons.menu_book_outlined, options: () => bank.subjects),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 8,
              maxLines: 30,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Metin'), alignLabelWithHint: true, hintText: tr('Parçanın metnini yazın ya da yapıştırın')),
            ),
            const SizedBox(height: 12),
            if (_p.imageId == null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(tr('Görsel ekle'))),
              )
            else
              Container(
                decoration: BoxDecoration(
                    border: Border.all(color: t.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12), color: Colors.white),
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  ConstrainedBox(constraints: const BoxConstraints(maxHeight: 360), child: BankImage(_p.imageId)),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton.icon(onPressed: _pick, icon: const Icon(Icons.swap_horiz_rounded), label: Text(tr('Değiştir'))),
                    TextButton.icon(
                      onPressed: () => setState(() => _p = _p.copyWith(clearImage: true)),
                      style: TextButton.styleFrom(foregroundColor: NColors.coral),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(tr('Kaldır')),
                    ),
                  ]),
                ]),
              ),
            if (linked.isNotEmpty) ...[
              SectionTitle(tr('Bağlı sorular ({0})', [linked.length])),
              for (final q in linked)
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text(q.text.trim().isEmpty ? q.type.label : q.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(q.type.label),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Soru düzenleyicideki "Okuma parçası" seçimi: parça seç, yeni parça, bağı kaldır.
class PassagePicker extends StatelessWidget {
  final String? passageId;
  final ValueChanged<String?> onChanged;
  const PassagePicker({super.key, required this.passageId, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = bank.passageById(passageId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p == null)
        Text(tr('Birden çok soru aynı metne, grafiğe ya da tabloya dayanıyorsa bir okuma parçasına bağlayın; kitapçıkta birlikte basılırlar.'),
            style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.65)))
      else
        Card(
          margin: EdgeInsets.zero,
          color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(p.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(tr('{0} soru bağlı', [bank.questionsOfPassage(p.id).length])),
            trailing: IconButton(
              tooltip: tr('Parçayı düzenle'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => PassageEditorScreen.open(context, p),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (bank.passages.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () async {
              final id = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (ctx) => SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
                    child: ListView(shrinkWrap: true, children: [
                      ListTile(title: Text(tr('Okuma parçası seçin'), style: const TextStyle(fontWeight: FontWeight.w800))),
                      for (final x in bank.passages)
                        ListTile(
                          leading: const Icon(Icons.article_outlined),
                          title: Text(x.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text([if (x.subject.isNotEmpty) x.subject, tr('{0} soru bağlı', [bank.questionsOfPassage(x.id).length])].join(' · ')),
                          selected: x.id == passageId,
                          onTap: () => Navigator.pop(ctx, x.id),
                        ),
                    ]),
                  ),
                ),
              );
              if (id != null) onChanged(id);
            },
            icon: const Icon(Icons.list_alt_rounded),
            label: Text(tr('Parça seç')),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final np = await PassageEditorScreen.open(context);
            if (np != null) onChanged(np.id);
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Yeni parça')),
        ),
        if (p != null)
          TextButton.icon(
            onPressed: () => onChanged(null),
            style: TextButton.styleFrom(foregroundColor: NColors.coral),
            icon: const Icon(Icons.link_off_rounded),
            label: Text(tr('Bağı kaldır')),
          ),
      ]),
    ]);
  }
}
