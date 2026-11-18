import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/legal.dart';
import '../main.dart';
import 'logo.dart';
import 'onboarding_screen.dart';
import 'school_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ayarlar: okul bilgileri, yedekleme, gizlilik metinleri, rehber, geri bildirim.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _stamp(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  Future<void> _export() async {
    final store = StoreScope.of(context);
    final path = await FilePicker.saveFile(
      dialogTitle: 'Yedeği kaydet',
      fileName: 'netice_yedek_${_stamp(DateTime.now())}.json',
      bytes: Uint8List.fromList(utf8.encode(store.exportBackup())),
    );
    if (!mounted) return;
    if (path != null || Platform.isAndroid || Platform.isIOS) {
      toast(context, 'Yedek kaydedildi. Dosyayı diğer cihaza taşıyıp "Yedekten geri yükle" ile açabilirsiniz.');
    }
  }

  Future<bool> _confirmRestore(String what) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Yedekten geri yüklensin mi?'),
          content: Text('$what\n\nBu cihazdaki mevcut veriler yedektekilerle değiştirilecek. '
              'Mevcut hâlin bir kopyası önce otomatik yedeklere eklenir.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Geri yükle')),
          ],
        ),
      ) ??
      false;

  Future<void> _restoreText(String text, String what) async {
    if (!await _confirmRestore(what) || !mounted) return;
    final store = StoreScope.of(context);
    try {
      final r = await store.restoreBackup(text);
      if (!mounted) return;
      toast(context, 'Geri yüklendi: ${r.students} öğrenci, ${r.exams} sınav, ${r.sheets} kâğıt.');
      setState(() {});
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Netice yedeği seçin',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    await _restoreText(utf8.decode(bytes, allowMalformed: true), 'Dosya: ${f.name}');
  }

  Future<void> _feedback() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Geri bildirim'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Ne iyi çalıştı, ne zorladı, ne eksik? Okunamayan bir kâğıt olduysa ne olduğunu yazın.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dosya olarak kaydet')),
        ],
      ),
    );
    if (ok != true || c.text.trim().isEmpty || !mounted) return;
    final store = StoreScope.of(context);
    final text = 'Netice geri bildirim\n'
        'Sürüm: $appVersion · ${Platform.operatingSystem}\n'
        'Tarih: ${dmy(DateTime.now())} ${hm(DateTime.now())}\n'
        'Kayıtlar: ${store.students.length} öğrenci, ${store.exams.length} sınav, ${store.sheets.length} kâğıt\n\n'
        '${c.text.trim()}\n';
    await FilePicker.saveFile(
      dialogTitle: 'Geri bildirimi kaydet',
      fileName: 'netice_geri_bildirim_${_stamp(DateTime.now())}.txt',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    if (mounted) toast(context, 'Geri bildirim dosyası hazır. E-posta ya da WhatsApp ile iletebilirsiniz.');
  }

  void _openText(String title, String text) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SelectionArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
              for (final para in text.split('\n\n'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: para.contains('\n')
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(para.split('\n').first, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(para.split('\n').skip(1).join('\n'), style: const TextStyle(height: 1.45)),
                        ])
                      : Text(para, style: const TextStyle(height: 1.45)),
                ),
            ]),
          ),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final backups = store.autoBackups();

    Widget tile(IconData icon, Color color, String title, String sub, VoidCallback onTap) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: IconBadge(icon, color: color),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Watermark(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          const SectionTitle('Okul'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: tile(
              Icons.account_balance_outlined,
              store.school.isEmpty ? NColors.amber : NColors.emerald,
              'Okul bilgileri',
              store.school.isEmpty ? 'Raporlarda resmi başlık için girin' : store.school.name,
              () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchoolScreen()));
                if (mounted) setState(() {});
              },
            ),
          ),
          if (store.hasDemo) ...[
            const SectionTitle('Örnek veriler'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: tile(Icons.cleaning_services_outlined, NColors.coral, 'Örnek verileri sil',
                  'Deneme için eklenen 9-A, 9-B sınıfları ve örnek sınavlar', () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Örnek veriler silinsin mi?'),
                    content: const Text('Örnek öğrenciler, örnek sınavlar ve kâğıtları silinir. '
                        'Sizin eklediğiniz sınıf ve sınavlara dokunulmaz.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                store.clearDemo();
                toast(context, 'Örnek veriler silindi.');
                setState(() {});
              }),
            ),
          ],
          const SectionTitle('Yedekleme'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              tile(Icons.save_alt_rounded, NColors.emerald, 'Yedeği dosyaya kaydet',
                  'Telefondan bilgisayara taşımak veya güvende tutmak için', _export),
              const Divider(height: 1),
              tile(Icons.settings_backup_restore_rounded, NColors.ink, 'Yedekten geri yükle',
                  'Başka cihazdan getirdiğiniz yedek dosyasını açın', _import),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              'Netice her gün ilk kayıtta otomatik bir yedek alır ve son 14 yedeği saklar. '
              'Otomatik yedekler bu cihazdadır; uygulamayı silmeden önce dosyaya yedek alın.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
          if (backups.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final f in backups.take(5))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history_rounded),
                    title: Text(_backupLabel(f)),
                    trailing: TextButton(
                      onPressed: () async =>
                          _restoreText(await f.readAsString(), 'Otomatik yedek: ${_backupLabel(f)}'),
                      child: const Text('Geri yükle'),
                    ),
                  ),
              ]),
            ),
          const SectionTitle('Yardım ve gizlilik'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              tile(Icons.school_outlined, NColors.emerald, 'Kullanım rehberi', 'Netice\'yi 4 adımda tanıyın',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()))),
              const Divider(height: 1),
              tile(Icons.lock_outline_rounded, NColors.ink, 'Gizlilik politikası',
                  'Veriler yalnızca bu cihazda', () => _openText('Gizlilik politikası', privacyPolicy)),
              const Divider(height: 1),
              tile(Icons.gavel_rounded, NColors.ink, 'KVKK aydınlatma metni', '6698 sayılı Kanun kapsamında',
                  () => _openText('KVKK aydınlatma metni', kvkkNotice)),
              const Divider(height: 1),
              tile(Icons.chat_bubble_outline_rounded, NColors.amber, 'Geri bildirim',
                  'Görüşlerinizi dosya olarak kaydedip iletin', _feedback),
            ]),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(children: [
              const NeticeMark(size: 36),
              const SizedBox(height: 6),
              Text('Netice $appVersion', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Kâğıttan sonuca, saniyeler içinde.', style: TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }

  String _backupLabel(File f) {
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})').firstMatch(f.uri.pathSegments.last);
    if (m == null) return f.uri.pathSegments.last;
    return '${m[3]}.${m[2]}.${m[1]} ${m[4]}:${m[5]}';
  }
}
