import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/doc_text.dart';
import '../core/import_export.dart';
import '../core/spreadsheet.dart';
import '../core/models.dart';
import '../main.dart';
import 'student_detail_screen.dart';
import 'theme.dart';
import 'transfer_ui.dart';
import 'illustrations.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import 'ad_slot.dart';

/// Sınıflar ve öğrenciler; Excel/CSV'den aktarma.
class StudentsScreen extends StatefulWidget {
  final bool embedded;
  const StudentsScreen({super.key, this.embedded = false});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  String? _class;
  String _query = '';

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('Öğrenci listesi (Excel, PDF, Word veya CSV)'),
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'ods', 'pdf', 'docx', 'csv', 'txt'],
    );
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final name = file.name.toLowerCase();
    List<Student> parsed;
    if (name.endsWith('.xlsx') || name.endsWith('.xls') || name.endsWith('.ods')) {
      try {
        final sheets = await compute((List<Object> a) => spreadsheetSheets(a[0] as Uint8List, a[1] as String), [bytes, name]);
        parsed = sheets == null ? StudentImport.parse(utf8.decode(bytes, allowMalformed: true)) : StudentImport.parseSheets(sheets);
      } catch (_) {
        if (!mounted) return;
        return toast(context, tr('Excel dosyası okunamadı. Dosyayı .xlsx veya CSV olarak yeniden kaydedin.'));
      }
      if (!mounted) return;
    } else if (name.endsWith('.pdf') || name.endsWith('.docx')) {
      try {
        final text = await compute((List<Object> a) => documentText(a[0] as Uint8List, a[1] as String), [bytes, name]);
        parsed = StudentImport.parseText(text);
      } catch (_) {
        parsed = const [];
      }
      if (!mounted) return;
      if (parsed.isEmpty) {
        return toast(context,
            tr('Belgede öğrenci listesi bulunamadı. Satırlar "sıra no, okul no, ad, soyad" düzeninde olmalı. Taranmış (fotoğraf) PDF okunamaz.'));
      }
    } else {
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        // Eski Excel sürümleri Windows-1254 kaydeder; Türkçe harfleri dönüştür.
        text = _cp1254(bytes);
      }
      parsed = StudentImport.parse(text);
    }
    final classCtl = TextEditingController(text: _class ?? '');
    final needsClass = parsed.any((s) => s.className.isEmpty);
    final byClass = <String, int>{};
    for (final s in parsed) {
      byClass[s.className] = (byClass[s.className] ?? 0) + 1;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('{0} öğrenci bulundu', [parsed.length])),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (byClass.length > 1) ...[
              Text(tr('{0} sınıf bulundu:', [byClass.length]), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text([for (final e in byClass.entries) '${e.key.isEmpty ? '?' : e.key} (${e.value})'].join(', ')),
              const SizedBox(height: 10),
            ],
            for (final s in parsed.take(5)) Text('${s.number}  ${s.fullName}  ${s.className}'),
            if (parsed.length > 5) Text(tr('… ve {0} öğrenci daha', [parsed.length - 5])),
            if (needsClass) ...[
              const SizedBox(height: 12),
              TextField(controller: classCtl, decoration: InputDecoration(labelText: tr('Sınıf / şube (dosyada yok)'))),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: parsed.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(tr('Aktar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cls = classCtl.text.trim();
    final list = [
      for (final s in parsed)
        s.className.isNotEmpty
            ? s
            : s.copyWith(className: cls)
    ];
    final store = StoreScope.of(context);
    final before = store.students.length;
    final numbered = store.addStudents(list);
    final added = store.students.length - before;
    final classes = list.map((s) => s.className).toSet().length;
    final numberNote = numbered > 0 ? tr('Numarası olmayan {0} öğrenciye sıra numarası verildi.', [numbered]) : '';
    toast(
        context,
        [
          tr('{0} öğrenci, {1} sınıfa aktarıldı.{2}', [added, classes, added < list.length ? tr(' {0} kişi zaten kayıtlı olduğu için atlandı.', [list.length - added]) : '']),
          if (numberNote.isNotEmpty) numberNote,
        ].join(' '));
  }

  /// Elle öğrenci ekleme veya düzenleme. [existing] varsa düzenler.
  Future<void> _edit({Student? existing}) async {
    final store = StoreScope.of(context);
    final first = TextEditingController(text: existing?.firstName ?? '');
    final last = TextEditingController(text: existing?.lastName ?? '');
    final no = TextEditingController(text: existing?.number ?? '');
    final cls = TextEditingController(text: existing?.className ?? _class ?? store.classNames.firstOrNull ?? '');
    final phone = TextEditingController(text: existing?.parentPhone ?? '');
    final mail = TextEditingController(text: existing?.email ?? '');
    final goal = TextEditingController(text: existing?.goal == null ? '' : '${existing!.goal!.round()}');
    var lang = existing?.parentLanguage ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? tr('Öğrenci ekle') : tr('Öğrenciyi düzenle')),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: first, autofocus: true, textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('Adı'))),
              const SizedBox(height: 10),
              TextField(controller: last, textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('Soyadı'))),
              const SizedBox(height: 10),
              TextField(controller: no, keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Okul no'), helperText: tr('Optik formdaki numarayla eşleşir. Boş bırakılırsa sıra numarası verilir.'))),
              const SizedBox(height: 10),
              TextField(controller: cls, textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: tr('Sınıf / şube'), hintText: tr('ör. 9-A'))),
              if (store.classNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final c in store.classNames)
                      ActionChip(label: Text(c), onPressed: () => cls.text = c),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              TextField(controller: phone, keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: tr('Veli telefonu (isteğe bağlı)'),
                      hintText: tr('ör. 0532 123 45 67'),
                      helperText: tr('Karneyi WhatsApp\'tan doğrudan veliye açmak için. Yalnız bu cihazda kalır.'),
                      helperMaxLines: 2)),
              const SizedBox(height: 10),
              TextField(controller: mail, keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: tr('Öğrenci e-postası (isteğe bağlı)'),
                      helperText: tr('Moodle\'a not aktarırken öğrenciyi kesin eşleştirir.'),
                      helperMaxLines: 2)),
              const SizedBox(height: 10),
              StatefulBuilder(
                builder: (ctx, setLang) => DropdownButtonFormField<String>(
                  initialValue: lang,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: tr('Velinin dili'),
                      helperText: tr('Karne ve veli mesajı bu dilde hazırlanır.'),
                      prefixIcon: const Icon(Icons.translate_rounded)),
                  items: [
                    DropdownMenuItem(value: '', child: Text(tr('Uygulamanın dili'))),
                    for (final l in AppLanguage.all) DropdownMenuItem(value: l.code, child: Text('${l.flag}  ${l.name}')),
                  ],
                  onChanged: (v) => setLang(() => lang = v ?? ''),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: goal, keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: tr('Kişisel hedef % (isteğe bağlı)'),
                      hintText: tr('ör. 75'),
                      helperText: tr('Karnede ve gelişim grafiğinde hedef çizgisi olarak görünür.'),
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.flag_outlined))),
            ]),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              style: TextButton.styleFrom(foregroundColor: NColors.coral),
              child: Text(tr('Sil')),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Kaydet'))),
        ],
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'delete') {
      store.deleteStudent(existing!.id);
      return toast(context, '${existing.fullName} silindi.');
    }
    final number = no.text.replaceAll(RegExp(r'\D'), '');
    final className = cls.text.trim();
    if (first.text.trim().isEmpty) return toast(context, tr('Öğrencinin adını yazın.'));
    if (className.isEmpty) return toast(context, tr('Sınıf / şube yazın.'));
    final clash = store.students.any((s) =>
        s.id != existing?.id && s.className == className && number.isNotEmpty && s.number == number);
    if (clash) return toast(context, tr('{0} sınıfında {1} numaralı bir öğrenci zaten var.', [className, number]));
    final st = Student(
      id: existing?.id ?? 's${DateTime.now().microsecondsSinceEpoch}',
      firstName: first.text.trim(),
      lastName: last.text.trim(),
      number: number,
      className: className,
      parentPhone: phone.text.trim(),
      email: mail.text.trim(),
      parentLanguage: lang,
      goal: (() {
        final g = double.tryParse(goal.text.trim().replaceAll(',', '.').replaceAll('%', ''));
        return g?.clamp(1, 100).toDouble();
      })(),
    );
    if (existing == null) {
      store.addStudents([st]);
    } else {
      store.updateStudent(st);
    }
    setState(() => _class = className);
    toast(context, existing == null ? '${st.fullName} eklendi.' : tr('Kaydedildi.'));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final classes = store.classNames;
    final current = _class ?? (classes.isEmpty ? null : classes.first);
    final list = current == null
        ? <Student>[]
        : store.studentsOf(current).where((s) => _query.isEmpty || s.fullName.toLowerCase().contains(_query.toLowerCase()) || s.number.contains(_query)).toList();

    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Text(tr('Sınıflar ve öğrenciler'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file), label: Text(tr('Excel / PDF aktar'))),
              OutlinedButton.icon(
                  onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt), label: Text(tr('Öğrenci ekle'))),
            ]),
          ],
        ),
        const SizedBox(height: 6),
        Text(tr('Tüm sınıfları tek Excel dosyasında (.xlsx, eski .xls, .ods veya CSV) aktarabilirsiniz: okul no, ad, soyad ve sınıf sütunları otomatik tanınır, öğrenciler sınıflarına kendiliğinden ayrılır. Öğrencinin geçmişini görmek için üstüne, düzenlemek için kalem simgesine dokunun.'),
            style: Theme.of(context).textTheme.bodySmall),
        const AdSlot.card(AdPage.classes, padding: EdgeInsets.only(top: 14)),
        const SizedBox(height: 16),
        if (classes.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in classes)
              ChoiceChip(label: Text('$c (${store.studentsOf(c).length})'), selected: c == current, onSelected: (_) => setState(() => _class = c)),
          ]),
        if (current != null && list.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => openTransferFile(context, current),
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text(tr('Sınıfın devir dosyası')),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Ad ya da numara ara')),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final s in list)
              ListTile(
                leading: CircleAvatar(child: Text(s.firstName.isEmpty ? '?' : s.firstName.characters.first)),
                title: Text(s.fullName),
                subtitle: Text('${tr('No')} ${s.number}'),
                trailing: IconButton(
                  tooltip: tr('Düzenle'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _edit(existing: s),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => StudentDetailScreen(studentId: s.id, onEdit: (st) => _edit(existing: st)))),
              ),
            if (list.isEmpty)
              EmptyState(
                kind: IllustrationKind.students,
                title: tr('Bu sınıfta öğrenci yok'),
                message: tr('e-Okul\'dan aldığınız Excel listesini "Excel aktar" ile yükleyin ya da öğrencileri tek tek ekleyin.'),
              ),
          ]),
        ),
      ]),
    );
  }
}

String _cp1254(List<int> bytes) {
  const map = {
    0xD0: 'Ğ', 0xDD: 'İ', 0xDE: 'Ş', 0xF0: 'ğ', 0xFD: 'ı', 0xFE: 'ş',
    0xC7: 'Ç', 0xE7: 'ç', 0xD6: 'Ö', 0xF6: 'ö', 0xDC: 'Ü', 0xFC: 'ü',
  };
  return String.fromCharCodes(bytes.map((b) => b < 0x80 ? b : (map[b]?.codeUnitAt(0) ?? b)));
}
