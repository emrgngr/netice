import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/pro.dart';
import 'pro_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Raporun Word (.docx) sürümünü kaydeder (Pro).
Future<void> saveReportDocx(BuildContext context, String pdfFileName, Uint8List Function() build) async {
  if (!await requirePro(context, ProFeature.wordExport) || !context.mounted) return;
  try {
    final name = pdfFileName.toLowerCase().endsWith('.pdf') ? '${pdfFileName.substring(0, pdfFileName.length - 4)}.docx' : '$pdfFileName.docx';
    final path = await FilePicker.saveFile(
      fileName: name,
      bytes: build(),
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    if (path != null && context.mounted) toast(context, tr('Word belgesi kaydedildi.'));
  } catch (_) {
    if (context.mounted) toast(context, tr('Word belgesi kaydedilemedi.'));
  }
}

/// PDF raporların paylaşmadan/yazdırmadan önce uygulama içinde
/// sayfa sayfa önizlemesi. Üstteki [header] (ör. öğrenci seçici)
/// isteğe bağlıdır.
class ReportPreviewScreen extends StatelessWidget {
  final String title;
  final String fileName;
  final Future<Uint8List> Function() makePdf;
  final Widget? header;

  /// Raporun Word sürümü (varsa üstte "Word" düğmesi çıkar).
  final Uint8List Function()? makeDocx;

  const ReportPreviewScreen({
    super.key,
    required this.title,
    required this.fileName,
    required this.makePdf,
    this.header,
    this.makeDocx,
  });

  static Future<void> open(BuildContext context,
          {required String title,
          required String fileName,
          required Future<Uint8List> Function() build,
          Uint8List Function()? word}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(title: title, fileName: fileName, makePdf: build, makeDocx: word)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        if (makeDocx != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: OutlinedButton.icon(
              onPressed: () => saveReportDocx(context, fileName, makeDocx!),
              icon: const Icon(Icons.description_outlined),
              label: Text(tr('Word olarak kaydet')),
            ),
          ),
      ]),
      body: Column(children: [
        ?header,
        Expanded(
          child: PdfPreview(
            // Seçim değişince önizleme yenilensin.
            key: ValueKey(fileName),
            build: (_) => makePdf(),
            initialPageFormat: PdfPageFormat.a4,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: fileName,
            maxPageWidth: 820,
            scrollViewDecoration: BoxDecoration(color: t.scaffoldBackgroundColor),
            pdfPreviewPageDecoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: NColors.ink.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6))],
            ),
            actionBarTheme: const PdfActionBarTheme(backgroundColor: NColors.ink, iconColor: Colors.white),
            loadingWidget: const Center(child: CircularProgressIndicator()),
          ),
        ),
      ]),
    );
  }
}

/// Öğrenci karnesi önizlemesi: tüm sınıf veya tek öğrenci seçilebilir.
class StudentCardsPreview extends StatefulWidget {
  final String title;
  final String baseFileName;
  final List<(String id, String name)> students;
  final String? initialStudentId;
  final Future<Uint8List> Function(String? studentId) build;

  const StudentCardsPreview({
    super.key,
    required this.title,
    required this.baseFileName,
    required this.students,
    required this.build,
    this.initialStudentId,
  });

  @override
  State<StudentCardsPreview> createState() => _StudentCardsPreviewState();
}

class _StudentCardsPreviewState extends State<StudentCardsPreview> {
  String? _id;

  @override
  void initState() {
    super.initState();
    _id = widget.initialStudentId;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.students.where((s) => s.$1 == _id).firstOrNull?.$2;
    final file = '${widget.baseFileName}_${name == null ? 'tum_sinif' : name.replaceAll(' ', '_')}.pdf';
    return ReportPreviewScreen(
      title: widget.title,
      fileName: file,
      makePdf: () => widget.build(_id),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: DropdownButtonFormField<String?>(
          initialValue: _id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: tr('Karnesi gösterilecek öğrenci'),
            prefixIcon: Icon(Icons.person_search_outlined),
            isDense: true,
          ),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(tr('Tüm sınıf (her öğrenciye bir sayfa)'))),
            for (final s in widget.students) DropdownMenuItem<String?>(value: s.$1, child: Text(s.$2)),
          ],
          onChanged: (v) => setState(() => _id = v),
        ),
      ),
    );
  }
}
