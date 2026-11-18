import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/import_export.dart';
import '../core/models.dart';
import '../main.dart';
import 'student_detail_screen.dart';
import 'theme.dart';
import 'widgets.dart';

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
      dialogTitle: 'Öğrenci listesi (Excel veya CSV)',
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv', 'txt', 'xls'],
    );
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final name = file.name.toLowerCase();
    List<Student> parsed;
    if (name.endsWith('.xls')) {
      return toast(context, 'Eski .xls biçimi okunamıyor. Excel\'de "Farklı Kaydet" ile .xlsx olarak kaydedip tekrar deneyin.');
    } else if (name.endsWith('.xlsx')) {
      try {
        parsed = StudentImport.parseXlsx(bytes);
      } catch (_) {
        return toast(context, 'Excel dosyası okunamadı. Dosyayı .xlsx veya CSV olarak yeniden kaydedin.');
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${parsed.length} öğrenci bulundu'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final s in parsed.take(5)) Text('${s.number}  ${s.fullName}  ${s.className}'),
            if (parsed.length > 5) Text('… ve ${parsed.length - 5} öğrenci daha'),
            if (needsClass) ...[
              const SizedBox(height: 12),
              TextField(controller: classCtl, decoration: const InputDecoration(labelText: 'Sınıf / şube (dosyada yok)')),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: parsed.isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('Aktar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cls = classCtl.text.trim();
    final list = [
      for (final s in parsed)
        s.className.isNotEmpty
            ? s
            : Student(id: s.id, firstName: s.firstName, lastName: s.lastName, number: s.number, className: cls)
    ];
    final store = StoreScope.of(context);
    final before = store.students.length;
    store.addStudents(list);
    final added = store.students.length - before;
    final classes = list.map((s) => s.className).toSet().length;
    toast(
        context,
        '$added öğrenci, $classes sınıfa aktarıldı.'
        '${added < list.length ? ' ${list.length - added} kişi zaten kayıtlı olduğu için atlandı.' : ''}');
  }

  /// Elle öğrenci ekleme veya düzenleme. [existing] varsa düzenler.
  Future<void> _edit({Student? existing}) async {
    final store = StoreScope.of(context);
    final first = TextEditingController(text: existing?.firstName ?? '');
    final last = TextEditingController(text: existing?.lastName ?? '');
    final no = TextEditingController(text: existing?.number ?? '');
    final cls = TextEditingController(text: existing?.className ?? _class ?? store.classNames.firstOrNull ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Öğrenci ekle' : 'Öğrenciyi düzenle'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: first, autofocus: true, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Adı')),
              const SizedBox(height: 10),
              TextField(controller: last, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Soyadı')),
              const SizedBox(height: 10),
              TextField(controller: no, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Okul no', helperText: 'Optik formdaki numarayla eşleşir')),
              const SizedBox(height: 10),
              TextField(controller: cls, textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Sınıf / şube', hintText: 'ör. 9-A')),
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
            ]),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              style: TextButton.styleFrom(foregroundColor: NColors.coral),
              child: const Text('Sil'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Kaydet')),
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
    if (first.text.trim().isEmpty) return toast(context, 'Öğrencinin adını yazın.');
    if (className.isEmpty) return toast(context, 'Sınıf / şube yazın.');
    final clash = store.students.any((s) =>
        s.id != existing?.id && s.className == className && number.isNotEmpty && s.number == number);
    if (clash) return toast(context, '$className sınıfında $number numaralı bir öğrenci zaten var.');
    final st = Student(
      id: existing?.id ?? 's${DateTime.now().microsecondsSinceEpoch}',
      firstName: first.text.trim(),
      lastName: last.text.trim(),
      number: number,
      className: className,
    );
    if (existing == null) {
      store.addStudents([st]);
    } else {
      store.updateStudent(st);
    }
    setState(() => _class = className);
    toast(context, existing == null ? '${st.fullName} eklendi.' : 'Kaydedildi.');
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
            Text('Sınıflar ve öğrenciler', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file), label: const Text('Excel aktar')),
              OutlinedButton.icon(
                  onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt), label: const Text('Öğrenci ekle')),
            ]),
          ],
        ),
        const SizedBox(height: 6),
        Text('Tüm sınıfları tek Excel dosyasında (.xlsx veya CSV) aktarabilirsiniz: okul no, ad, soyad ve sınıf '
            'sütunları otomatik tanınır, öğrenciler sınıflarına kendiliğinden ayrılır. '
            'Öğrencinin geçmişini görmek için üstüne, düzenlemek için kalem simgesine dokunun.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        if (classes.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in classes)
              ChoiceChip(label: Text('$c (${store.studentsOf(c).length})'), selected: c == current, onSelected: (_) => setState(() => _class = c)),
          ]),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Ad ya da numara ara'),
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
                subtitle: Text('No ${s.number}'),
                trailing: IconButton(
                  tooltip: 'Düzenle',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _edit(existing: s),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => StudentDetailScreen(studentId: s.id, onEdit: (st) => _edit(existing: st)))),
              ),
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('Bu sınıfta öğrenci yok.')),
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
