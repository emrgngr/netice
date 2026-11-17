import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/import_export.dart';
import '../core/models.dart';
import '../main.dart';
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
      dialogTitle: 'Öğrenci listesi (CSV)',
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (files.isEmpty || !mounted) return;
    final bytes = await files.first.readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Eski Excel sürümleri Windows-1254 kaydeder; Türkçe harfleri dönüştür.
      text = _cp1254(bytes);
    }
    if (!mounted) return;
    final classCtl = TextEditingController(text: _class ?? '');
    final parsed = StudentImport.parse(text);
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
    StoreScope.of(context).addStudents(list);
    toast(context, '${list.length} öğrenci aktarıldı.');
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
        Row(children: [
          Text('Sınıflar ve öğrenciler', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          FilledButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file), label: const Text('Excel / CSV aktar')),
        ]),
        const SizedBox(height: 6),
        Text('Excel\'de listeyi "CSV (noktalı virgülle ayrılmış)" olarak kaydedip seçin. '
            'Ad, soyad, okul no ve sınıf sütunları otomatik tanınır.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        if (classes.isNotEmpty)
          Wrap(spacing: 8, children: [
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
