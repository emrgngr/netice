import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';
import '../widgets.dart';

bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Bir belge sayfası (PNG/JPG baytları ve piksel boyutu).
class DocPage {
  final Uint8List bytes;
  final int width;
  final int height;
  const DocPage(this.bytes, this.width, this.height);
}

/// Görseli [rel] (0–1 arası) dikdörtgeninden keser, en fazla [maxW] genişliğe
/// küçültür ve JPG olarak döndürür.
Future<Uint8List> cropBytes(Uint8List src, Rect? rel, {int maxW = 1600}) =>
    compute(_crop, (src, rel == null ? null : [rel.left, rel.top, rel.right, rel.bottom], maxW));

Uint8List _crop((Uint8List, List<double>?, int) a) {
  final (src, r, maxW) = a;
  var im = img.decodeImage(src);
  if (im == null) return src;
  im = img.bakeOrientation(im);
  if (r != null) {
    final x = (r[0].clamp(0.0, 1.0) * im.width).round();
    final y = (r[1].clamp(0.0, 1.0) * im.height).round();
    final w = math.max(8, ((r[2] - r[0]).clamp(0.0, 1.0) * im.width).round());
    final h = math.max(8, ((r[3] - r[1]).clamp(0.0, 1.0) * im.height).round());
    im = img.copyCrop(im, x: x, y: y, width: math.min(w, im.width - x), height: math.min(h, im.height - y));
  }
  if (im.width > maxW) im = img.copyResize(im, width: maxW, interpolation: img.Interpolation.average);
  // Saydam PNG'ler beyaz zemine oturtulur.
  if (im.hasAlpha) {
    final bg = img.Image(width: im.width, height: im.height)..clear(img.ColorRgb8(255, 255, 255));
    im = img.compositeImage(bg, im);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 86));
}

(int, int) _size(Uint8List b) {
  final d = img.findDecoderForData(b);
  final info = d?.startDecode(b);
  return info == null ? (1000, 1400) : (info.width, info.height);
}

/// PDF ya da görsel dosyalarını sayfa görüntülerine çevirir.
Future<List<DocPage>> pickDocumentPages(BuildContext context, {bool camera = false, bool gallery = false}) async {
  final pages = <DocPage>[];
  if (camera || gallery) {
    final picker = ImagePicker();
    final files = camera
        ? [await picker.pickImage(source: ImageSource.camera, requestFullMetadata: false)].whereType<XFile>().toList()
        : await picker.pickMultiImage(requestFullMetadata: false);
    for (final f in files) {
      final b = await cropBytes(await f.readAsBytes(), null, maxW: 2000);
      final (w, h) = _size(b);
      pages.add(DocPage(b, w, h));
    }
    return pages;
  }
  final files = await FilePicker.pickFiles(
    dialogTitle: tr('PDF ya da görsel seçin'),
    type: FileType.custom,
    allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
  );
  for (final f in files) {
    final bytes = await f.readAsBytes();
    if (f.name.toLowerCase().endsWith('.pdf')) {
      await for (final r in Printing.raster(bytes, dpi: 150)) {
        pages.add(DocPage(await r.toPng(), r.width, r.height));
        if (pages.length >= 120) break;
      }
    } else {
      final b = await cropBytes(bytes, null, maxW: 2000);
      final (w, h) = _size(b);
      pages.add(DocPage(b, w, h));
    }
  }
  return pages;
}

/// "Görsel ekle" seçenekleri; kesilmiş JPG baytlarını döndürür.
Future<Uint8List?> pickBankImage(BuildContext context) async {
  final src = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_mobile) ...[
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Fotoğraf çek')),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Galeriden seç')),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(tr('PDF ya da görsel dosyasından')),
          subtitle: Text(tr('Sayfayı açıp istediğiniz bölgeyi kesin')),
          onTap: () => Navigator.pop(ctx, 'file'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (src == null || !context.mounted) return null;
  try {
    final pages = await pickDocumentPages(context, camera: src == 'camera', gallery: src == 'gallery');
    if (pages.isEmpty || !context.mounted) return null;
    return await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => CropScreen(pages: pages)));
  } catch (e) {
    if (context.mounted) toast(context, tr('Açılamadı: {0}', [e]));
    return null;
  }
}

/// Tek görsel kesme ekranı (birden çok sayfa varsa sayfa seçilir).
class CropScreen extends StatefulWidget {
  final List<DocPage> pages;
  const CropScreen({super.key, required this.pages});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  int _page = 0;
  Rect? _rect;
  bool _busy = false;

  Future<void> _done(bool whole) async {
    setState(() => _busy = true);
    final b = await cropBytes(widget.pages[_page].bytes, whole ? null : _rect);
    if (mounted) Navigator.pop(context, b);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pages[_page];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Bölgeyi seçin')),
        actions: [
          TextButton(onPressed: _busy ? null : () => _done(true), child: Text(tr('Tümü'))),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(tr('Parmağınızla ya da fareyle sürükleyerek bir dikdörtgen çizin. Köşelerden boyutunu değiştirebilirsiniz.'),
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65))),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RectSelector(
              key: ValueKey(_page),
              page: p,
              rect: _rect,
              onChanged: (r) => setState(() => _rect = r),
            ),
          ),
        ),
        if (widget.pages.length > 1)
          PageStrip(pages: widget.pages, index: _page, onSelect: (i) => setState(() {
                _page = i;
                _rect = null;
              })),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy || _rect == null ? null : () => _done(false),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.crop_rounded),
            label: Text(tr('Seçili bölgeyi kullan')),
          ),
        ),
      ),
    );
  }
}

/// Alttaki küçük sayfa şeridi.
class PageStrip extends StatelessWidget {
  final List<DocPage> pages;
  final int index;
  final ValueChanged<int> onSelect;
  final Map<int, int> badges;
  const PageStrip({super.key, required this.pages, required this.index, required this.onSelect, this.badges = const {}});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: pages.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => GestureDetector(
            onTap: () => onSelect(i),
            child: Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: i == index ? NColors.emerald : Theme.of(context).colorScheme.outlineVariant, width: i == index ? 2.5 : 1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.memory(pages[i].bytes, height: 66, fit: BoxFit.contain, cacheHeight: 132),
                ),
              ),
              Positioned(
                left: 4,
                bottom: 3,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: NColors.ink)),
              ),
              if ((badges[i] ?? 0) > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: NColors.emerald,
                    child: Text('${badges[i]}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// Sayfa üzerinde dikdörtgen seçimi: boş yerde sürükleyince yeni seçim,
/// içinde sürükleyince taşıma, köşelerden boyutlandırma. Dikdörtgen
/// sayfaya göre 0–1 arası oranlarla tutulur.
class RectSelector extends StatefulWidget {
  final DocPage page;
  final Rect? rect;
  final ValueChanged<Rect?> onChanged;

  /// Daha önce kesilmiş bölgeler (soluk gösterilir).
  final List<Rect> done;
  const RectSelector({super.key, required this.page, required this.rect, required this.onChanged, this.done = const []});

  @override
  State<RectSelector> createState() => _RectSelectorState();
}

enum _Drag { none, draw, move, tl, tr, bl, br }

class _RectSelectorState extends State<RectSelector> {
  _Drag _mode = _Drag.none;
  Offset _start = Offset.zero;
  Rect _orig = Rect.zero;

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    return LayoutBuilder(builder: (context, c) {
      final ar = p.width / p.height;
      var w = c.maxWidth, h = w / ar;
      if (h > c.maxHeight) {
        h = c.maxHeight;
        w = h * ar;
      }
      final size = Size(w, h);
      Offset rel(Offset local) => Offset((local.dx / w).clamp(0.0, 1.0), (local.dy / h).clamp(0.0, 1.0));
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              final r = widget.rect;
              final pt = d.localPosition;
              _start = rel(pt);
              if (r != null) {
                final px = Rect.fromLTRB(r.left * w, r.top * h, r.right * w, r.bottom * h);
                const tol = 22.0;
                bool near(Offset a) => (a - pt).distance < tol;
                _orig = r;
                if (near(px.topLeft)) {
                  _mode = _Drag.tl;
                } else if (near(px.topRight)) {
                  _mode = _Drag.tr;
                } else if (near(px.bottomLeft)) {
                  _mode = _Drag.bl;
                } else if (near(px.bottomRight)) {
                  _mode = _Drag.br;
                } else if (px.contains(pt)) {
                  _mode = _Drag.move;
                } else {
                  _mode = _Drag.draw;
                }
              } else {
                _mode = _Drag.draw;
              }
            },
            onPanUpdate: (d) {
              final cur = rel(d.localPosition);
              Rect? next;
              switch (_mode) {
                case _Drag.draw:
                  next = Rect.fromPoints(_start, cur);
                case _Drag.move:
                  final dx = (cur.dx - _start.dx).clamp(-_orig.left, 1 - _orig.right);
                  final dy = (cur.dy - _start.dy).clamp(-_orig.top, 1 - _orig.bottom);
                  next = _orig.shift(Offset(dx, dy));
                case _Drag.tl:
                  next = Rect.fromPoints(cur, _orig.bottomRight);
                case _Drag.tr:
                  next = Rect.fromPoints(Offset(_orig.left, cur.dy), Offset(cur.dx, _orig.bottom));
                case _Drag.bl:
                  next = Rect.fromPoints(Offset(cur.dx, _orig.top), Offset(_orig.right, cur.dy));
                case _Drag.br:
                  next = Rect.fromPoints(_orig.topLeft, cur);
                case _Drag.none:
                  return;
              }
              widget.onChanged(next);
            },
            onPanEnd: (_) {
              final r = widget.rect;
              // Çok küçük seçim (yanlışlıkla dokunma) silinir.
              if (r != null && (r.width * w < 12 || r.height * h < 12)) widget.onChanged(null);
              _mode = _Drag.none;
            },
            child: Stack(fit: StackFit.expand, children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Image.memory(p.bytes, fit: BoxFit.fill, gaplessPlayback: true),
              ),
              CustomPaint(painter: _SelPainter(widget.rect, widget.done, size)),
            ]),
          ),
        ),
      );
    });
  }
}

class _SelPainter extends CustomPainter {
  final Rect? r;
  final List<Rect> done;
  final Size s;
  _SelPainter(this.r, this.done, this.s);

  Rect _px(Rect x) => Rect.fromLTRB(x.left * s.width, x.top * s.height, x.right * s.width, x.bottom * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in done) {
      final px = _px(d);
      canvas.drawRect(px, Paint()..color = NColors.emerald.withValues(alpha: 0.12));
      canvas.drawRect(px, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = NColors.emerald.withValues(alpha: 0.6));
    }
    final sel = r;
    if (sel == null) return;
    final px = _px(sel);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(px);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.38));
    canvas.drawRect(px, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = NColors.emerald);
    for (final c in [px.topLeft, px.topRight, px.bottomLeft, px.bottomRight]) {
      canvas.drawCircle(c, 8, Paint()..color = Colors.white);
      canvas.drawCircle(c, 8, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = NColors.emerald);
    }
  }

  @override
  bool shouldRepaint(_SelPainter o) => o.r != r || o.done.length != done.length || o.s != s;
}
