import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/common_exam.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import '../core/progress.dart';
import 'exam_screen.dart';
import 'lan_sync_screen.dart';
import 'pro_screen.dart';
import 'report_preview_screen.dart';
import 'widgets.dart';

/// Dosyayı telefonda paylaşım menüsüyle gönderir, bilgisayarda kaydettirir.
Future<void> shareOrSaveFile(BuildContext context,
    {required String fileName, required String text, required String message}) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  if (Platform.isAndroid || Platform.isIOS) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$fileName');
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/json')],
      text: message,
      subject: fileName,
      sharePositionOrigin: origin,
    ));
  } else {
    final path = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: 'application/json');
    if (path != null && context.mounted) toast(context, tr('Kaydedildi. Dosyayı diğer öğretmenlere gönderebilirsiniz.'));
  }
}

/// İkili dosyayı telefonda paylaşım menüsüyle gönderir, bilgisayarda kaydettirir.
Future<void> saveOrShareBytes(BuildContext context,
    {required String fileName, required Uint8List bytes, required String mimeType, String message = ''}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$fileName');
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: mimeType)],
      text: message,
      subject: fileName,
      sharePositionOrigin: origin,
    ));
  } else {
    final path = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    if (path != null && context.mounted) toast(context, tr('Kaydedildi.'));
  }
}

String _safeName(String s) => s.replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ -]'), '').trim().replaceAll(' ', '_');

/// Sınav ekranındaki "Ortak sınav" menüsü.
Future<void> openCommonExamMenu(BuildContext context, Exam exam) async {
  if (!await requirePro(context, ProFeature.commonExam) || !context.mounted) return;
  final store = StoreScope.of(context);
  final group = exam.isCommon ? commonGroups(store)[exam.commonId] ?? [exam] : [exam];
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            title: Text(tr('Ortak sınav'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(exam.isCommon
                ? tr('Bu sınav {0} şubede ortak. Sonuç dosyaları geldikçe rapor birleşir.', [group.length])
                : tr('Aynı sınavı diğer şubelerin öğretmenleri de okusun; sonuçlar tek raporda birleşsin. İnternet ve hesap gerekmez.')),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: Text(tr('1. Sınavı diğer öğretmenlere gönder')),
            subtitle: Text(tr('Cevap anahtarı, kitapçıklar ve puanlama gider; öğrenci bilgisi gitmez.')),
            onTap: () => Navigator.pop(ctx, 'send'),
          ),
          ListTile(
            leading: const Icon(Icons.outbox_outlined),
            title: Text(tr('2. Bu şubenin sonuçlarını gönder')),
            subtitle: Text(tr('Okuduğunuz kâğıtları sınavı hazırlayan öğretmene gönderin.')),
            onTap: () => Navigator.pop(ctx, 'results'),
          ),
          ListTile(
            leading: const Icon(Icons.move_to_inbox_outlined),
            title: Text(tr('3. Gelen sonuçları içe al')),
            subtitle: Text(tr('Diğer şubelerden gelen sonuç dosyalarını ekleyin.')),
            onTap: () => Navigator.pop(ctx, 'import'),
          ),
          ListTile(
            leading: const Icon(Icons.wifi_rounded),
            title: Text(tr('Aynı Wi-Fi\'daki öğretmenlerle eşitle')),
            subtitle: Text(tr('Dosya göndermeden: sınavı dağıtın ya da sonuçları tek cihazda toplayın.')),
            onTap: () => Navigator.pop(ctx, 'lan'),
          ),
          if (group.length >= 2)
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(tr('Ortak sınav raporu ({0} şube)', [group.length])),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
        ]),
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'send':
      await shareOrSaveFile(context,
          fileName: '${_safeName(exam.name)}_ortak_sinav.${CommonExamFile.extension}',
          text: exportCommonExam(store, exam),
          message: tr('"{0}" ortak sınavı. Netice\'de Profil > Ortak sınav dosyası aç ile kendi şubenize ekleyin.', [exam.name]));
    case 'results':
      if (store.sheetsOf(exam.id).isEmpty) return toast(context, tr('Önce bu şubenin kâğıtlarını okutun.'));
      await shareOrSaveFile(context,
          fileName: '${_safeName(exam.name)}_${_safeName(exam.className)}_sonuclar.${CommonExamFile.extension}',
          text: exportCommonResults(store, exam),
          message: tr('"{0}" ortak sınavı, {1} şubesinin sonuçları.', [exam.name, exam.className]));
    case 'import':
      await importNeticeFile(context);
    case 'report':
      await openCommonReport(context, exam.commonId!);
    case 'lan':
      await openLanSync(context, examId: exam.id);
  }
}

/// Ortak sınavın tüm şubelerini tek PDF raporda birleştirir.
Future<void> openCommonReport(BuildContext context, String commonId) async {
  final store = StoreScope.of(context);
  final exams = commonGroups(store)[commonId] ?? const <Exam>[];
  final rows = compareExams(store, exams).where((r) => r.report.results.isNotEmpty).toList();
  if (rows.length < 2) return toast(context, tr('Birleşik rapor için en az iki şubenin sonucu gerekli.'));
  await ReportPreviewScreen.open(context,
      title: tr('Ortak sınav raporu'),
      fileName: '${_safeName(exams.first.name)}_ortak_rapor.pdf',
      build: () => buildComparePdf(rows, school: store.reportSchool, students: store.studentById));
}

/// Ortak sınav dosyasını ya da sonuç dosyasını seçip içe alır.
Future<void> importNeticeFile(BuildContext context) async {
  final files = await FilePicker.pickFiles(dialogTitle: tr('Ortak sınav veya sonuç dosyası seçin'));
  if (files.isEmpty || !context.mounted) return;
  final text = utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
  if (!context.mounted) return;
  await importNeticeText(context, text);
}

Future<void> importNeticeText(BuildContext context, String text) async {
  final store = StoreScope.of(context);
  switch (commonFileKind(text)) {
    case CommonExamFile.examKind:
      final name = commonExamName(text);
      final className = await _askClass(context, name);
      if (className == null || !context.mounted) return;
      final e = importCommonExam(store, text, className);
      toast(context, tr('"{0}" {1} şubesine eklendi. Formları basıp okutabilirsiniz.', [e.name, e.className]));
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamScreen(examId: e.id)));
    case CommonExamFile.resultsKind:
      try {
        final r = importCommonResults(store, text);
        toast(context, tr('{0} · {1}: {2} kâğıt alındı ({3} yeni öğrenci).', [r.examName, r.className, r.sheets, r.students]));
      } on FormatException catch (e) {
        toast(context, e.message);
      }
    default:
      toast(context, tr('Bu dosya bir Netice ortak sınav dosyası değil.'));
  }
}

Future<String?> _askClass(BuildContext context, String examName) async {
  final store = StoreScope.of(context);
  final c = TextEditingController(text: store.classNames.isEmpty ? '' : store.classNames.first);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('"{0}" hangi şubede okunacak?', [examName])),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: tr('Şube / sınıf'))),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in store.classNames) ActionChip(label: Text(n), onPressed: () => c.text = n),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()), child: Text(tr('Ekle'))),
      ],
    ),
  );
}
