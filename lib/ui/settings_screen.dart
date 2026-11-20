import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../core/legal.dart';
import '../main.dart';
import 'logo.dart';
import 'onboarding_screen.dart';
import 'rate_share.dart';
import 'help_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'template_screen.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import 'ad_slot.dart';
import 'ad_admin_screen.dart';

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
      dialogTitle: tr('Yedeği kaydet'),
      fileName: 'netice_yedek_${_stamp(DateTime.now())}.json',
      bytes: Uint8List.fromList(utf8.encode(store.exportBackup())),
    );
    if (!mounted) return;
    if (path != null || Platform.isAndroid || Platform.isIOS) {
      toast(context, tr('Yedek kaydedildi. Dosyayı diğer cihaza taşıyıp "Yedekten geri yükle" ile açabilirsiniz.'));
    }
  }

  Future<bool> _confirmRestore(String what) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Yedekten geri yüklensin mi?')),
          content: Text(tr('{0}\n\nBu cihazdaki mevcut veriler yedektekilerle değiştirilecek. Mevcut hâlin bir kopyası önce otomatik yedeklere eklenir.', [what])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Geri yükle'))),
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
      toast(context, tr('Geri yüklendi: {0} öğrenci, {1} sınav, {2} kâğıt.', [r.students, r.exams, r.sheets]));
      setState(() {});
    } on FormatException catch (e) {
      if (mounted) toast(context, tr(e.message));
    }
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('Netice yedeği seçin'),
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    await _restoreText(utf8.decode(bytes, allowMalformed: true), tr('Dosya: {0}', [f.name]));
  }

  Future<void> _feedback() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Geri bildirim')),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: tr('Ne iyi çalıştı, ne zorladı, ne eksik? Okunamayan bir kâğıt olduysa ne olduğunu yazın.'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Dosya olarak kaydet'))),
        ],
      ),
    );
    if (ok != true || c.text.trim().isEmpty || !mounted) return;
    final store = StoreScope.of(context);
    final text = tr('Netice geri bildirim\nSürüm: {0} · {1}\nTarih: {2} {3}\nKayıtlar: {4} öğrenci, {5} sınav, {6} kâğıt\n\n{7}\n', [appVersion, Platform.operatingSystem, dmy(DateTime.now()), hm(DateTime.now()), store.students.length, store.exams.length, store.sheets.length, c.text.trim()]);
    await FilePicker.saveFile(
      dialogTitle: tr('Geri bildirimi kaydet'),
      fileName: 'netice_geri_bildirim_${_stamp(DateTime.now())}.txt',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    if (mounted) toast(context, tr('Geri bildirim dosyası hazır. E-posta ya da WhatsApp ile iletebilirsiniz.'));
  }

  void _openText(String title, String text) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SelectionArea(
            child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
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

  Future<void> _wipe() async {
    final store = StoreScope.of(context);
    var alsoBackups = false;
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          icon: const Icon(Icons.delete_forever_rounded, color: NColors.coral),
          title: Text(tr('Tüm veriler silinsin mi?')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Bu cihazdaki bütün öğrenciler, sınavlar, okutulan kâğıtlar ve okul bilgileri silinir. İsterseniz önce "Yedeği dosyaya kaydet" ile yedek alın.')),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: alsoBackups,
                onChanged: (v) => set(() => alsoBackups = v ?? false),
                title: Text(tr('Otomatik yedekleri de sil')),
                subtitle: Text(alsoBackups
                    ? tr('Geri dönüş olmaz.')
                    : tr('Silmeden önceki hâl otomatik yedeklerde kalır; vazgeçerseniz geri yükleyebilirsiniz.')),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: typed,
                onChanged: (_) => set(() {}),
                decoration: InputDecoration(labelText: tr('Onaylamak için SİL yazın')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: NColors.coral),
              onPressed: typed.text.trim().toUpperCase() == tr('SİL') || typed.text.trim().toLowerCase() == 'sil'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text(tr('Sil')),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok != true || !mounted) return;
    await store.wipeAll(backups: alsoBackups);
    if (!mounted) return;
    toast(context, alsoBackups ? tr('Tüm veriler ve otomatik yedekler silindi.') : tr('Tüm veriler silindi. Önceki hâl otomatik yedeklerde duruyor.'));
    setState(() {});
  }

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
      appBar: AppBar(title: Text(tr('Ayarlar'))),
      body: Watermark(
        child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 40 + MediaQuery.paddingOf(context).bottom), children: [
          SectionTitle(tr('Dil')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const IconBadge(Icons.translate_rounded, color: NColors.emerald),
              title: Text(tr('Uygulama dili'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(store.language == null
                  ? tr('Cihazın dili: {0}', [AppLanguage.byCode(L10n.code).name])
                  : AppLanguage.byCode(L10n.code).name),
              trailing: Text(AppLanguage.byCode(L10n.code).flag, style: const TextStyle(fontSize: 22)),
              onTap: () => pickLanguage(context),
            ),
          ),
          SectionTitle(tr('Ses')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: const IconBadge(Icons.music_note_rounded, color: NColors.emerald),
              value: store.splashSound,
              onChanged: store.setSplashSound,
              title: Text(tr('Açılış melodisi'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Uygulama açılırken kısa bir melodi çalar')),
            ),
          ),
          // Netice Pro, hesap ve okul bilgileri Profil sekmesinde.
          SectionTitle(tr('Formlar')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: tile(
              Icons.grid_on_rounded,
              NColors.emerald,
              tr('Başka firma formları'),
              store.templates.isEmpty ? tr('Yayınevi formları için şablon oluşturun') : tr('{0} şablon', [store.templates.length]),
              () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen()));
                if (mounted) setState(() {});
              },
            ),
          ),
          if (store.hasDemo) ...[
            SectionTitle(tr('Örnek veriler')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: tile(Icons.cleaning_services_outlined, NColors.coral, tr('Örnek verileri sil'),
                  tr('Deneme için eklenen 9-A, 9-B sınıfları ve örnek sınavlar'), () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('Örnek veriler silinsin mi?')),
                    content: Text(tr('Örnek öğrenciler, örnek sınavlar ve kâğıtları silinir. Sizin eklediğiniz sınıf ve sınavlara dokunulmaz.')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sil'))),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                store.clearDemo();
                toast(context, tr('Örnek veriler silindi.'));
                setState(() {});
              }),
            ),
          ],
          SectionTitle(tr('Yedekleme')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              tile(Icons.save_alt_rounded, NColors.emerald, tr('Yedeği dosyaya kaydet'),
                  tr('Telefondan bilgisayara taşımak veya güvende tutmak için'), _export),
              const Divider(height: 1),
              tile(Icons.settings_backup_restore_rounded, NColors.ink, tr('Yedekten geri yükle'),
                  tr('Başka cihazdan getirdiğiniz yedek dosyasını açın'), _import),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              tr('Netice her gün ilk kayıtta otomatik bir yedek alır ve son 14 yedeği saklar. Otomatik yedekler bu cihazdadır; uygulamayı silmeden önce dosyaya yedek alın.'),
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
                          _restoreText(await f.readAsString(), tr('Otomatik yedek: {0}', [_backupLabel(f)])),
                      child: Text(tr('Geri yükle')),
                    ),
                  ),
              ]),
            ),
          SectionTitle(tr('Verileri sil')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: tile(Icons.delete_forever_rounded, NColors.coral, tr('Tüm verileri sil'),
                tr('Öğrenciler, sınavlar, kâğıtlar ve okul bilgileri bu cihazdan silinir'), _wipe),
          ),
          SectionTitle(tr('Netice\'yi yayın')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              tile(Icons.share_rounded, NColors.emerald, tr('Uygulamayı paylaş'), tr('Meslektaşlarınıza WhatsApp veya e-postayla önerin'),
                  () => shareApp(context)),
              const Divider(height: 1),
              tile(Icons.star_rounded, NColors.amber, tr('Yıldız ver'),
                  StoreScope.of(context).rating == 0 ? tr('Görüşünüz bizim için değerli') : tr('Verdiğiniz puan: {0} yıldız', [StoreScope.of(context).rating]),
                  () => showRateDialog(context, onFeedback: _feedback)),
            ]),
          ),
          const AdSlot.card(AdPage.settings, padding: EdgeInsets.only(top: 12)),
          SectionTitle(tr('Yardım ve gizlilik')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              tile(Icons.menu_book_outlined, NColors.emerald, tr('Kullanma kılavuzu'), tr('Adım adım anlatım'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()))),
              const Divider(height: 1),
              tile(Icons.quiz_outlined, NColors.emerald, tr('Sık sorulan sorular'), tr('Aranabilir cevaplar'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen(initialTab: 1)))),
              const Divider(height: 1),
              tile(Icons.play_circle_outline, NColors.ink, tr('Tanıtımı yeniden izle'), tr('Netice\'yi 4 adımda tanıyın'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()))),
              const Divider(height: 1),
              tile(Icons.lock_outline_rounded, NColors.ink, tr('Gizlilik politikası'),
                  tr('Veriler yalnızca bu cihazda'), () => _openText(tr('Gizlilik politikası'), privacyPolicy)),
              const Divider(height: 1),
              tile(Icons.gavel_rounded, NColors.ink, tr('KVKK aydınlatma metni'), tr('6698 sayılı Kanun kapsamında'),
                  () => _openText(tr('KVKK aydınlatma metni'), kvkkNotice)),
              const Divider(height: 1),
              tile(Icons.chat_bubble_outline_rounded, NColors.amber, tr('Geri bildirim'),
                  tr('Görüşlerinizi dosya olarak kaydedip iletin'), _feedback),
            ]),
          ),
          const SizedBox(height: 20),
          // Yönetici girişi: logoya 3 saniye basılı tutmak (görünür bir iz bırakmaz), ardından PIN.
          RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: const Duration(seconds: 3)),
                (r) => r.onLongPress = () => openAdminGate(context),
              ),
            },
            child: Center(
            child: Column(children: [
              const NeticeMark(size: 36),
              const SizedBox(height: 6),
              Text(tr('Netice {0}', [appVersion]), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tr('Kâğıttan sonuca, saniyeler içinde.'), style: TextStyle(color: muted, fontSize: 12)),
            ]),
          )),
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


/// Dil seçici. "Cihazın dili" seçilirse telefonun dili kullanılır.
Future<void> pickLanguage(BuildContext context) async {
  final store = StoreScope.of(context);
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          leading: const Icon(Icons.phone_android_rounded),
          title: Text(tr('Cihazın dili')),
          trailing: store.language == null ? const Icon(Icons.check_rounded, color: NColors.emerald) : null,
          onTap: () => Navigator.pop(ctx, ''),
        ),
        for (final l in AppLanguage.all)
          ListTile(
            leading: Text(l.flag, style: const TextStyle(fontSize: 22)),
            title: Text(l.name),
            trailing: store.language == l.code ? const Icon(Icons.check_rounded, color: NColors.emerald) : null,
            onTap: () => Navigator.pop(ctx, l.code),
          ),
      ]),
    ),
  );
  if (picked == null) return;
  store.setLanguage(picked.isEmpty ? null : picked);
}
