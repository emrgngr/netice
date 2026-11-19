import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/legal.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../core/scoring.dart';
import '../main.dart';
import 'annotated_sheet.dart';
import 'pro_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// İşaretli kâğıt görüntüsü var mı?
bool hasSheetImage(BuildContext context, Sheet s) => StoreScope.of(context).sheetImageFile(s) != null;

Future<void> openSheetImage(BuildContext context, Exam exam, Result r) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SheetImageScreen(exam: exam, result: r)));

/// Okutulan kâğıdın düzleştirilmiş fotoğrafı; her sorunun sonucu üzerine çizilir.
class SheetImageScreen extends StatefulWidget {
  final Exam exam;
  final Result result;
  const SheetImageScreen({super.key, required this.exam, required this.result});

  @override
  State<SheetImageScreen> createState() => _SheetImageScreenState();
}

class _SheetImageScreenState extends State<SheetImageScreen> {
  final _key = GlobalKey();
  Future<List<int>>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= StoreScope.of(context).sheetImageFile(widget.result.sheet)?.readAsBytes();
  }

  Future<void> _share() async {
    if (!await requirePro(context, ProFeature.parentShare) || !mounted) return;
    final store = StoreScope.of(context);
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final st = store.studentById[widget.result.sheet.studentId];
      final name = (st?.fullName ?? 'kagit').replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ]+'), '_');
      final f = File('${dir.path}${Platform.pathSeparator}${name}_isaretli_kagit.png');
      await f.writeAsBytes(data!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'image/png')],
        subject: '${st?.fullName ?? ''} – ${widget.exam.name} işaretli kâğıt',
        text: '${st?.fullName ?? 'Öğrencinin'} "${widget.exam.name}" sınavındaki işaretli kâğıdı ektedir. '
            'Yeşil: doğru, kırmızı: yanlış, kesikli: doğru cevap.$downloadSignature',
      ));
    } catch (e) {
      if (mounted) toast(context, 'Paylaşılamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final st = store.studentById[widget.result.sheet.studentId];
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(
        title: Text(st?.fullName ?? 'İşaretli kâğıt'),
        actions: [IconButton(tooltip: 'Paylaş', onPressed: _share, icon: const Icon(Icons.ios_share_rounded))],
      ),
      body: FutureBuilder<List<int>>(
        future: _bytes,
        builder: (context, snap) {
          if (_bytes == null) {
            return const Center(child: Text('Bu kâğıdın görüntüsü yok.'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return Column(children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: RepaintBoundary(
                      key: _key,
                      child: DecoratedBox(
                        decoration: BoxDecoration(boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6)),
                        ]),
                        child: AnnotatedSheet(
                          jpeg: Uint8List.fromList(snap.data!),
                          exam: widget.exam,
                          result: widget.result,
                          booklet: widget.result.sheet.booklet,
                          template: store.templateById(widget.exam.templateId),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(children: [
                  Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center, children: [
                    _legend(NColors.emerald, 'Doğru', false),
                    _legend(NColors.coral, 'Yanlış işaret', false),
                    _legend(NColors.emerald, 'Olması gereken', true),
                    _legend(NColors.amber, 'Boş bırakılan', true),
                  ]),
                  const SizedBox(height: 6),
                  Text('İki parmakla yakınlaştırabilirsiniz.', style: TextStyle(color: muted, fontSize: 12)),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _legend(Color c, String label, bool dashed) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: dashed ? c.withValues(alpha: 0.55) : c, width: dashed ? 1.5 : 2.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]);
}
