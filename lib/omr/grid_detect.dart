import 'dart:math' as math;
import 'dart:typed_data';

import 'form_layout.dart' show Pt;
import 'omr_reader.dart' show GrayImage;
import 'template.dart';

/// Başka firma formunda daire ızgaralarını kendiliğinden bulur.
///
/// Düzleştirilmiş sayfada (genişlik [FormTemplate.width]) basılı daireler
/// aranır; birbirine eşit aralıklı, aynı boydaki daireler ızgara (blok) olarak
/// toplanır ve her blok türüne göre sınıflanır:
///  * 2–6 sütunlu, çok satırlı blok: cevap bloğu (her satır bir soru),
///  * 2–6 satırlı, çok sütunlu blok: şıkları alt alta cevap bloğu,
///  * 10 satırlı (0–9) blok: öğrenci numarası,
///  * tek satır/sütun 2–6 daire (sayfanın üst yarısında): kitapçık türü,
///  * harf ızgarası (ad soyad) gibi büyük bloklar: yok sayılır.
/// Sonuç her zaman öğretmene gösterilir; yanlış bulunan blok elle düzeltilir.
class DetectedForm {
  final List<TemplateBlock> blocks;
  final NumberBlock? number;
  final BookletBlock? booklet;
  final NameBlock? name;
  final List<NumberBlock> extraNumbers;

  /// Bulunan ama kullanılmayan ızgaralar (ad soyad, sınıf, cinsiyet…).
  final int ignored;

  const DetectedForm({this.blocks = const [], this.number, this.booklet, this.name, this.extraNumbers = const [], this.ignored = 0});

  bool get isEmpty => blocks.isEmpty && number == null && booklet == null;

  int get questionCount => blocks.fold(0, (m, b) => math.max(m, b.start + b.count - 1));

  FormTemplate applyTo(FormTemplate t) =>
      FormTemplate(id: t.id, name: t.name, aspect: t.aspect, blocks: blocks, number: number, booklet: booklet, nameGrid: name, extraNumbers: extraNumbers);
}

/// Fotoğraftaki formun ızgaralarını bulur ([corners]: sayfanın dört köşesi).
DetectedForm detectFormGrids(GrayImage g, List<Pt> corners, {double aspect = 297 / 210, String lang = 'tr'}) {
  final page = rectifyPage(g, corners, aspect: aspect, width: FormTemplate.width.round());
  final w = page.width, h = page.height;
  final px = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      px[y * w + x] = page.getPixel(x, y).r.toInt();
    }
  }
  return GridDetector(px, w, h, lang: lang).detect();
}

class _Blob {
  final double cx, cy, bw, bh;
  _Blob(this.cx, this.cy, this.bw, this.bh);
  double get size => (bw + bh) / 2;
}

class _Grid {
  final List<double> xs, ys; // sütun ve satır merkezleri (doğrusal uydurulmuş)
  final double bw, bh;

  /// Başka dairelerle bağlantısı olmayan, kendi başına bir grup mu?
  final bool alone;
  _Grid(this.xs, this.ys, this.bw, this.bh, {this.alone = true});
  int get nc => xs.length;
  int get nr => ys.length;
  double get left => xs.first;
  double get right => xs.last;
  double get top => ys.first;
  double get bottom => ys.last;
  Pt get first => Pt(xs.first, ys.first);
  Pt get last => Pt(xs.last, ys.last);
  double get pitchX => nc < 2 ? 0 : (xs.last - xs.first) / (nc - 1);
}

class GridDetector {
  final Uint8List px;
  final int w, h;

  /// Ad soyad alfabesini seçmek için uygulama dili.
  final String lang;
  GridDetector(this.px, this.w, this.h, {this.lang = 'tr'});

  DetectedForm detect() {
    // Üç yol denenir, en çok daireyi yerleştiren seçilir:
    //  * koyu lekeler 1 piksel genişletilerek (kırık çemberler birleşsin),
    //  * genişletmeden (daireleri birbirine çok yakın sık formlar),
    //  * çember arama (ince, soluk çemberler; numarası daireye değen formlar).
    DetectedForm? best;
    var bestCells = -1;
    for (final mode in const [0, 1, 2, 3]) {
      _ringMaskOverride = mode == 3 ? _faint : null;
      final bl = mode >= 2 ? _rings() : _blobs(grow: mode == 0);
      final gr = _complete(_grids(bl), bl);
      _allBlobs = bl;
      final d = _classify(gr);
      final cells =
          d.blocks.fold(0, (n, b) => n + b.count * b.choices) +
          (d.number == null ? 0 : d.number!.digits * 10) +
          // Eşitlikte ad soyad alanını da bulan yol seçilsin.
          (d.name == null ? 0 : d.name!.columns);
      if (cells > bestCells) {
        bestCells = cells;
        best = d;
      }
    }
    _ringMaskOverride = null;
    return best!;
  }

  Uint8List? _darkCache;
  Uint8List? _faintCache;
  Uint8List? _ringMaskOverride;
  Uint8List get _ringMask => _ringMaskOverride ?? _dark;

  /// Halka arama için daha hassas eşik (soluk baskılı formlar).
  Uint8List get _faint => _faintCache ??= _threshold(7, 0.04);
  List<_Blob> _allBlobs = const [];

  /// Çevresinden belirgin koyu pikseller (yerel zemin: 51×51 kutu ortalaması).
  Uint8List get _dark => _darkCache ??= _threshold(12, 0.06);

  Uint8List _threshold(int minDiff, double frac) {
    final ii = Int64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0;
      for (var x = 0; x < w; x++) {
        row += px[y * w + x];
        ii[(y + 1) * (w + 1) + x + 1] = ii[y * (w + 1) + x + 1] + row;
      }
    }
    const half = 25;
    final dark = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - half), y1 = math.min(h, y + half + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - half), x1 = math.min(w, x + half + 1);
        final s = ii[y1 * (w + 1) + x1] - ii[y0 * (w + 1) + x1] - ii[y1 * (w + 1) + x0] + ii[y0 * (w + 1) + x0];
        final mean = s / ((x1 - x0) * (y1 - y0));
        if (px[y * w + x] < mean - math.max(minDiff, mean * frac)) dark[y * w + x] = 1;
      }
    }
    return dark;
  }

  // -------------------------------------------------------------------------
  // 1b. Çember arama

  /// Her olası merkez ve yarıçap için çember boyunca koyu nokta oranına bakar:
  /// çember kesintisiz koyu, içi (harf hariç) açık olmalı.
  List<_Blob> _rings() {
    final dark = _ringMask;
    const n = 16;
    final cand = <(double, int, int, int)>[]; // (puan, x, y, r)
    for (var r = 5; r <= 22; r++) {
      final ring = <List<int>>[]; // her açı için r-1, r, r+1 kaydırmaları
      final inner = <int>[];
      final outer = <int>[];
      for (var k = 0; k < n; k++) {
        final a = 2 * math.pi * k / n, c = math.cos(a), s = math.sin(a);
        ring.add([
          for (final rr in [r - 1.0, r.toDouble(), r + 1.0]) (s * rr).round() * w + (c * rr).round(),
        ]);
        inner.add((s * r * 0.62).round() * w + (c * r * 0.62).round());
        outer.add((s * (r + 3.5)).round() * w + (c * (r + 3.5)).round());
      }
      final quick = [ring[0], ring[4], ring[8], ring[12]];
      bool hit(int i, List<int> offs) => dark[i + offs[0]] == 1 || dark[i + offs[1]] == 1 || dark[i + offs[2]] == 1;
      for (var y = r + 5; y < h - r - 5; y++) {
        for (var x = r + 5; x < w - r - 5; x++) {
          final i = y * w + x;
          var q = 0;
          for (final o in quick) {
            if (hit(i, o)) q++;
          }
          if (q < 3) continue;
          var cov = 0;
          for (final o in ring) {
            if (hit(i, o)) cov++;
          }
          if (cov < 13) continue;
          var inn = 0;
          for (final o in inner) {
            if (dark[i + o] == 1) inn++;
          }
          if (inn > 7) {
            // Doldurulmuş daire: içi tamamen koyu, hemen dışı açık.
            if (inn < 15 || y < r + 5 || y >= h - r - 5 || x < r + 5 || x >= w - r - 5) continue;
            var out = 0;
            for (final o in outer) {
              if (dark[i + o] == 1) out++;
            }
            if (out > 3) continue;
            cand.add((cov - 2.0 + r * 0.01, x, y, r));
            continue;
          }
          cand.add((cov - 0.5 * inn + r * 0.01, x, y, r));
        }
      }
    }
    // Aynı dairenin komşu merkezlerinden en iyisi; bir dairenin içine ikincisi giremez.
    cand.sort((a, b) => b.$1.compareTo(a.$1));
    final taken = <(int, int, int)>[];
    final grid = <int, List<int>>{};
    const cell = 24;
    final out = <_Blob>[];
    for (final c in cand) {
      final (_, x, y, r) = c;
      final gx = x ~/ cell, gy = y ~/ cell;
      var clash = false;
      for (var dy = -1; dy <= 1 && !clash; dy++) {
        for (var dx = -1; dx <= 1 && !clash; dx++) {
          for (final j in grid[(gy + dy) * 1000 + gx + dx] ?? const <int>[]) {
            final t = taken[j];
            final d2 = (t.$1 - x) * (t.$1 - x) + (t.$2 - y) * (t.$2 - y);
            final lim = math.max(t.$3, r) * 1.6;
            if (d2 < lim * lim) {
              clash = true;
              break;
            }
          }
        }
      }
      if (clash) continue;
      grid.putIfAbsent(gy * 1000 + gx, () => []).add(taken.length);
      taken.add((x, y, r));
      out.add(_Blob(x.toDouble(), y.toDouble(), 2.0 * r, 2.0 * r));
    }
    return out;
  }

  /// Çember var mı? (Kesintili de olsa; ±2 piksel kaymaya izin verilir.)
  bool _ringAt(double cx, double cy, double r, {Uint8List? mask}) {
    final dark = mask ?? _ringMask;
    const n = 16;
    var best = 0;
    for (var oy = -2; oy <= 2 && best < 11; oy += 2) {
      for (var ox = -2; ox <= 2 && best < 11; ox += 2) {
        var cov = 0;
        for (var k = 0; k < n; k++) {
          final a = 2 * math.pi * k / n, c = math.cos(a), s = math.sin(a);
          var hit = false;
          for (final rr in [r - 1, r, r + 1]) {
            final x = (cx + ox + c * rr).round(), y = (cy + oy + s * rr).round();
            if (x >= 0 && y >= 0 && x < w && y < h && dark[y * w + x] == 1) {
              hit = true;
              break;
            }
          }
          if (hit) cov++;
        }
        if (cov > best) best = cov;
      }
    }
    // Doldurulmuş daire de sayılır: merkez ve çevresi koyu.
    if (best < 11) {
      var filled = 0;
      for (var k = 0; k < 8; k++) {
        final a = 2 * math.pi * k / 8;
        final x = (cx + math.cos(a) * r * 0.5).round(), y = (cy + math.sin(a) * r * 0.5).round();
        if (x >= 0 && y >= 0 && x < w && y < h && dark[y * w + x] == 1) filled++;
      }
      if (filled >= 7) return true;
    }
    return best >= 11;
  }

  /// Eksik bulunan ızgaraları tamamlar: kenarda bir sütun/satır daha
  /// varsa (hücrelerin çoğunda çember) ekler; numarası daireye değen şık
  /// sütunu, birkaç dairesi kaçırılan blok böylece tamamlanır. Sonra iç içe
  /// geçen ızgaralardan büyüğü kalır.
  List<_Grid> _complete(List<_Grid> grids, List<_Blob> blobs) {
    if (blobs.isEmpty) return grids;
    // Formdaki en yaygın daire boyu ve aralığı.
    final dom = _median([for (final b in blobs) b.size]);
    final big = grids.where((g) => g.nr >= 3 && g.nc >= 3).toList();
    final typX = big.isEmpty ? 0.0 : _median([for (final g in big) (g.right - g.left) / (g.nc - 1)]);
    final typY = big.isEmpty ? 0.0 : _median([for (final g in big) (g.bottom - g.top) / (g.nr - 1)]);
    final out = <_Grid>[];
    for (final g in grids) {
      final cells = g.nr * g.nc;
      final px = g.nc >= 2 ? (g.right - g.left) / (g.nc - 1) : typX;
      final py = g.nr >= 2 ? (g.bottom - g.top) / (g.nr - 1) : typY;
      if (cells < 3 || px <= 0 || py <= 0) {
        out.add(g);
        continue;
      }
      final xs = [...g.xs], ys = [...g.ys];
      // Dairenin içindeki rakam/harf çember sanılmış olabilir: yaygın boyu kullan.
      final size = (g.bw + g.bh) / 2;
      final r = (size < dom * 0.75 ? dom : size) / 2;
      // Ad soyad gibi uzun ızgaralarda ışık bir yandan azalabilir: soluk
      // çemberler de sayılır, sütunun yarısı yeterli.
      final tall = ys.length >= 20;
      bool ring(double x, double y) => _ringAt(x, y, r) || (tall && _ringAt(x, y, r, mask: _faint));
      bool okCol(double x) => x > r && x < w - r && ys.where((y) => ring(x, y)).length >= ys.length * (tall ? 0.5 : 0.6);
      bool okRow(double y) => y > r && y < h - r && xs.where((x) => ring(x, y)).length >= xs.length * (tall ? 0.5 : 0.6);
      for (var guard = 0; guard < 80; guard++) {
        var grew = false;
        if (okCol(xs.first - px)) {
          xs.insert(0, xs.first - px);
          grew = true;
        }
        if (okCol(xs.last + px)) {
          xs.add(xs.last + px);
          grew = true;
        }
        if (okRow(ys.first - py)) {
          ys.insert(0, ys.first - py);
          grew = true;
        }
        if (okRow(ys.last + py)) {
          ys.add(ys.last + py);
          grew = true;
        }
        if (!grew) break;
      }
      final grown = xs.length * ys.length > cells;
      final bw = size < dom * 0.75 && grown ? dom : g.bw, bh = size < dom * 0.75 && grown ? dom : g.bh;
      out.add(_Grid(xs, ys, bw, bh, alone: g.alone && !grown));
    }
    out.sort((a, b) => (b.nr * b.nc).compareTo(a.nr * a.nc));
    final kept = <_Grid>[];
    for (final g in out) {
      final cx = (g.left + g.right) / 2, cy = (g.top + g.bottom) / 2;
      final inside = kept.any((k) => cx >= k.left - k.bw / 2 && cx <= k.right + k.bw / 2 && cy >= k.top - k.bh / 2 && cy <= k.bottom + k.bh / 2);
      if (!inside) kept.add(g);
    }
    return kept;
  }

  // -------------------------------------------------------------------------
  // 1. Koyu lekeler (daire adayları)

  List<_Blob> _blobs({bool grow = true}) {
    final dark = _dark;
    // Kırık çemberler tek parça olsun diye 1 piksel genişlet.
    final mask = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (dark[y * w + x] == 0) continue;
        if (!grow) {
          mask[y * w + x] = 1;
          continue;
        }
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx >= 0 && xx < w) mask[yy * w + xx] = 1;
          }
        }
      }
    }

    final label = Int32List(w * h);
    final out = <_Blob>[];
    final stack = <int>[];
    var next = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0 || label[i] != 0) continue;
      next++;
      label[i] = next;
      stack.add(i);
      var area = 0, minX = w, maxX = 0, minY = h, maxY = 0;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        area++;
        final x = p % w, y = p ~/ w;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x > 0 && mask[p - 1] == 1 && label[p - 1] == 0) {
          label[p - 1] = next;
          stack.add(p - 1);
        }
        if (x < w - 1 && mask[p + 1] == 1 && label[p + 1] == 0) {
          label[p + 1] = next;
          stack.add(p + 1);
        }
        if (y > 0 && mask[p - w] == 1 && label[p - w] == 0) {
          label[p - w] = next;
          stack.add(p - w);
        }
        if (y < h - 1 && mask[p + w] == 1 && label[p + w] == 0) {
          label[p + w] = next;
          stack.add(p + w);
        }
      }
      // Genişletmeyi geri al (her yönde ~1 piksel).
      final shrink = grow ? 1 : -1;
      final bw = (maxX - minX - shrink).toDouble(), bh = (maxY - minY - shrink).toDouble();
      if (bw < 7 || bh < 7 || bw > 70 || bh > 70) continue;
      final ratio = bw / bh;
      if (ratio < 0.55 || ratio > 2.4) continue;
      final fill = area / ((maxX - minX + 1) * (maxY - minY + 1));
      if (fill < 0.12 || fill > 0.9) continue;
      // Köşeleri dolu kutular (yazı kutusu, kare çerçeve) daire değildir.
      var cornersDark = 0;
      for (final (x, y) in [(minX + 1, minY + 1), (maxX - 1, minY + 1), (minX + 1, maxY - 1), (maxX - 1, maxY - 1)]) {
        var any = false;
        for (var dy = 0; dy <= 2 && !any; dy++) {
          for (var dx = 0; dx <= 2 && !any; dx++) {
            final xx = x < (minX + maxX) / 2 ? x + dx : x - dx, yy = y < (minY + maxY) / 2 ? y + dy : y - dy;
            if (dark[yy * w + xx] == 1) any = true;
          }
        }
        if (any) cornersDark++;
      }
      if (cornersDark >= 3) continue;
      out.add(_Blob((minX + maxX) / 2, (minY + maxY) / 2, bw, bh));
    }
    // Dairenin içindeki harf ayrı leke olarak çıkar: daha büyük bir lekenin
    // içinde kalanları at.
    out.sort((a, b) => b.size.compareTo(a.size));
    final kept = <_Blob>[];
    for (final b in out) {
      final inside = kept.any((k) => k.size > b.size * 1.3 && (b.cx - k.cx).abs() < k.bw / 2 && (b.cy - k.cy).abs() < k.bh / 2);
      if (!inside) kept.add(b);
    }
    return kept;
  }

  // -------------------------------------------------------------------------
  // 2. Izgaralar

  List<_Grid> _grids(List<_Blob> blobs) {
    final n = blobs.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    // Komşu: aynı boy, aynı satır (ya da sütun) üzerinde ve yakın.
    final order = List<int>.generate(n, (i) => i)..sort((a, b) => blobs[a].cx.compareTo(blobs[b].cx));
    for (var ai = 0; ai < n; ai++) {
      final a = blobs[order[ai]];
      for (var bi = ai + 1; bi < n; bi++) {
        final b = blobs[order[bi]];
        final s = math.max(a.size, b.size);
        if (b.cx - a.cx > 2.8 * s) break;
        if ((a.bw - b.bw).abs() > 0.22 * math.max(a.bw, b.bw) || (a.bh - b.bh).abs() > 0.22 * math.max(a.bh, b.bh)) continue;
        final dx = (b.cx - a.cx).abs(), dy = (b.cy - a.cy).abs();
        final horiz = dy < 0.3 * math.min(a.bh, b.bh) && dx < 2.8 * s;
        final vert = dx < 0.3 * math.min(a.bw, b.bw) && dy < 2.8 * s;
        if (horiz || vert) parent[find(order[ai])] = find(order[bi]);
      }
    }
    final groups = <int, List<_Blob>>{};
    for (var i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => []).add(blobs[i]);
    }

    final grids = <_Grid>[];
    for (final g in groups.values) {
      if (g.length < 2) continue;
      final bw = _median([for (final b in g) b.bw]), bh = _median([for (final b in g) b.bh]);
      // Önce büyük sütun boşluklarından, sonra her parçada büyük satır
      // boşluklarından, sonra yine sütunlardan böl.
      for (final colPart in _split(g, bw, (b) => b.cx)) {
        for (final rowPart in _split(colPart, bh, (b) => b.cy)) {
          for (final part in _split(rowPart, bw, (b) => b.cx)) {
            final cs = _cluster([for (final b in part) b.cx], 0.45 * bw);
            final rs = _cluster([for (final b in part) b.cy], 0.45 * bh);
            final cells = cs.length * rs.length;
            if (cells < 2 || part.length < cells * 0.7) continue;
            if (!_regular(cs) || !_regular(rs)) continue;
            // Her sütun/satır merkezini o sütundaki dairelerden yeniden hesapla, doğruya uydur.
            final xs = _fit([
              for (final c in cs)
                _median([
                  for (final b in part)
                    if ((b.cx - c).abs() < 0.45 * bw) b.cx,
                ]),
            ]);
            final ys = _fit([
              for (final r in rs)
                _median([
                  for (final b in part)
                    if ((b.cy - r).abs() < 0.45 * bh) b.cy,
                ]),
            ]);
            grids.add(_Grid(xs, ys, bw, bh, alone: g.length <= part.length + 1));
          }
        }
      }
    }
    return grids;
  }

  /// Daireleri bir eksende kümeleyip büyük boşluklardan parçalara ayırır.
  static List<List<_Blob>> _split(List<_Blob> g, double size, double Function(_Blob) axis) {
    if (g.isEmpty) return const [];
    final centers = _cluster([for (final b in g) axis(b)], 0.45 * size);
    final parts = _splitByGap(centers);
    if (parts.length == 1) return [g];
    return [
      for (final p in parts)
        [
          for (final b in g)
            if (axis(b) >= p.first - 0.45 * size && axis(b) <= p.last + 0.45 * size) b,
        ],
    ];
  }

  /// Değerleri yakınlığa göre kümeler, küme ortalamalarını sıralı döndürür.
  static List<double> _cluster(List<double> v, double gap) {
    final s = [...v]..sort();
    final out = <double>[];
    var sum = s.first, cnt = 1;
    for (var i = 1; i < s.length; i++) {
      if (s[i] - s[i - 1] > gap) {
        out.add(sum / cnt);
        sum = 0;
        cnt = 0;
      }
      sum += s[i];
      cnt++;
    }
    out.add(sum / cnt);
    return out;
  }

  /// Büyük boşluklardan böler (iki soru sütunu arasındaki numara alanı gibi).
  static List<List<double>> _splitByGap(List<double> c) {
    if (c.length < 3) return [c];
    final gaps = [for (var i = 1; i < c.length; i++) c[i] - c[i - 1]];
    final m = _median(gaps);
    final out = <List<double>>[];
    var cur = [c.first];
    for (var i = 1; i < c.length; i++) {
      if (gaps[i - 1] > 1.55 * m) {
        out.add(cur);
        cur = [];
      }
      cur.add(c[i]);
    }
    out.add(cur);
    return out;
  }

  static bool _regular(List<double> c) {
    if (c.length < 3) return true;
    final gaps = [for (var i = 1; i < c.length; i++) c[i] - c[i - 1]];
    final m = _median(gaps);
    return gaps.every((g) => (g - m).abs() <= m * 0.35);
  }

  /// En küçük kareler doğrusu: eşit aralıklı merkezler.
  static List<double> _fit(List<double> v) {
    final n = v.length;
    if (n < 3) return v;
    final mi = (n - 1) / 2, mv = v.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (i - mi) * (v[i] - mv);
      sxx += (i - mi) * (i - mi);
    }
    final b = sxy / sxx;
    return [for (var i = 0; i < n; i++) mv + b * (i - mi)];
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  // -------------------------------------------------------------------------
  // 3. Sınıflama

  /// Dilin alfabesine 1–2 satır eksik harf ızgarasını aşağı doğru tamamlar:
  /// harfin içi çemberi bozabildiği için soluk satırda sütunların beşte biri,
  /// eklenen satırların toplamında üçte biri yeter.
  _Grid _fitAlphabet(_Grid g) {
    final own = NameBlock.alphabets.where((a) => a.$1 == lang).map((a) => a.$2.length).toList();
    if (own.isEmpty) own.add(NameBlock.english.length);
    if (own.contains(g.nr) || own.contains(g.nr - 1)) return g;
    final py = (g.bottom - g.top) / (g.nr - 1);
    final r = (g.bw + g.bh) / 4;
    for (final want in own) {
      final miss = want - g.nr;
      if (miss < 1 || miss > 2) continue;
      final ys = [...g.ys];
      var ok = true, all = 0;
      for (var k = 0; k < miss && ok; k++) {
        final y = ys.last + py;
        final hits = y < h - r ? g.xs.where((x) => _ringAt(x, y, r, mask: _faint) || _ringAt(x, y, r, mask: _dark)).length : 0;
        all += hits;
        if (hits >= g.nc / 5) {
          ys.add(y);
        } else {
          ok = false;
        }
      }
      ok = ok && all >= miss * g.nc / 3;
      if (ok) return _Grid(g.xs, ys, g.bw, g.bh);
    }
    return g;
  }

  DetectedForm _classify(List<_Grid> grids) {
    final answers = <(_Grid, bool)>[]; // (ızgara, şıklar yan yana mı)
    final numbers = <_Grid>[];
    final singles = <_Grid>[];
    var ignored = 0;
    final names = <_Grid>[];
    for (final g in grids) {
      final nr = g.nr, nc = g.nc;
      if (nr >= 24 && nr <= 34 && nc >= 6) {
        // Son harf satırları (Y, Z gibi) çoğu formda soluk basılır ya da
        // ışık azalır: dilin alfabesine 1–2 satır eksikse alt satırlar denenir.
        final ng = _fitAlphabet(g);
        // Ad soyad harf ızgarası; üstte harflerin yazıldığı kutular da sayılmış olabilir.
        if (NameBlock.alphabetFor(ng.nr, lang) != null) {
          names.add(ng);
        } else if (NameBlock.alphabetFor(ng.nr - 1, lang) != null) {
          names.add(_Grid(ng.xs, ng.ys.sublist(1), ng.bw, ng.bh));
        } else {
          ignored++;
        }
      } else if (nr == 1 || nc == 1) {
        if (nr * nc >= 2 && nr * nc <= 6) {
          singles.add(g);
        } else {
          ignored++;
        }
      } else if (nr == 10 && nc >= 6 && nc <= 12) {
        numbers.add(g);
      } else if ((nr == 11 || nr == 12) && nc >= 6 && nc <= 12) {
        // Üstte rakamın yazıldığı kutular da daire sanılmış: alttaki 10 satır.
        numbers.add(_Grid(g.xs, g.ys.sublist(nr - 10), g.bw, g.bh));
      } else if (nc >= 3 && nc <= 6 && nr >= 3 && nr <= 60) {
        answers.add((g, true));
      } else if (nr >= 3 && nr <= 6 && nc >= 7 && nc <= 60) {
        answers.add((g, false));
      } else {
        ignored++;
      }
    }

    // Cevap daireleri formun her yerinde aynı boydadır: en çok daireyi
    // taşıyan boydan çok farklı olan parçalar (ad soyad ızgarası kırıntısı) atılır.
    if (answers.length > 1) {
      final weight = <int, int>{};
      for (final (g, _) in answers) {
        final k = ((g.bw + g.bh) / 2).round();
        weight[k] = (weight[k] ?? 0) + g.nr * g.nc;
      }
      final main = weight.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      final before = answers.length;
      answers.removeWhere((a) => ((a.$1.bw + a.$1.bh) / 2 - main).abs() > main * 0.25);
      ignored += before - answers.length;
    }

    // Şıkları alt alta bloklar nadirdir; yan yana bloklar varsa bunlar
    // (çoğunlukla ad soyad ızgarası parçası) atılır.
    if (answers.any((a) => a.$2)) {
      final before = answers.length;
      answers.removeWhere((a) => !a.$2);
      ignored += before - answers.length;
    }
    _fillMissingBlocks(answers);

    // 10 satırlı, 3–5 sütunlu blok: cevap mı numara mı? Diğer cevap
    // bloklarından farklı sütun sayısı varsa ya da hepsinin üstündeyse numara.
    if (numbers.isEmpty) {
      final tens = answers.where((a) => a.$2 && a.$1.nr == 10 && a.$1.nc >= 3).toList();
      final others = answers.where((a) => !tens.contains(a)).toList();
      for (final t in tens) {
        if (others.isEmpty) continue;
        final majority = _mode([for (final o in others) o.$1.nc]);
        final above = others.where((o) => o.$1.nr != 10).every((o) => t.$1.bottom < o.$1.top);
        if (t.$1.nc != majority || above) {
          answers.remove(t);
          numbers.add(t.$1);
          break;
        }
      }
    }

    NumberBlock? number;
    final extraNumbers = <NumberBlock>[];
    if (numbers.isNotEmpty) {
      numbers.sort((a, b) => b.nc.compareTo(a.nc));
      final g = numbers.first;
      number = NumberBlock(digits: g.nc, first: g.first, last: g.last);
      for (final o in numbers.skip(1)) {
        extraNumbers.add(NumberBlock(digits: o.nc, first: o.first, last: o.last));
      }
    }

    // Kitapçık: sayfanın üst yarısındaki tek sıra 2–6 daire; en kalabalığı,
    // eşitlikte en üstteki (cinsiyet gibi alanlar genelde daha aşağıda).
    BookletBlock? booklet;
    final pageH = h.toDouble();
    final ref = [for (final (g, _) in answers) (g.bw + g.bh) / 2, if (number != null) (numbers.first.bw + numbers.first.bh) / 2];
    final refSize = ref.isEmpty ? 0.0 : ref.reduce((a, b) => a + b) / ref.length;
    final minSize = 0.85 * refSize;
    // Kitapçık sırası tek başınadır: hemen üstünde/altında (yan yana sırada)
    // ya da solunda/sağında (alt alta sırada) başka daire yoktur.
    bool isolated(_Grid s) {
      final horizontal = s.nr == 1;
      final size = (s.bw + s.bh) / 2;
      final step = horizontal ? (s.nc >= 2 ? (s.right - s.left) / (s.nc - 1) : size * 1.3) : (s.nr >= 2 ? (s.bottom - s.top) / (s.nr - 1) : size * 1.3);
      // Üstte (ya da solda) "KİTAPÇIK" gibi bir başlık yazısı olabilir; bir
      // yanı boş olması yeter. Bir ızgaranın parçası olan sıranın iki yanı da doludur.
      final near = [0, 0];
      var total = 0;
      for (final x in s.xs) {
        for (final y in s.ys) {
          total++;
          for (var k = 0; k < 2; k++) {
            final d = k == 0 ? -step : step;
            final px = horizontal ? x : x + d, py = horizontal ? y + d : y;
            // Yalnız benzer boydaki daireler sayılır.
            if (_ringAt(px, py, size / 2, mask: _dark) ||
                _allBlobs.any((b) => (b.cx - px).abs() < size * 0.5 && (b.cy - py).abs() < size * 0.5 && (b.size - size).abs() <= size * 0.25)) {
              near[k]++;
            }
          }
        }
      }
      return math.min(near[0], near[1]) <= total * 0.25;
    }

    final cands = singles
        .where(
          (s) =>
              s.top < pageH * 0.6 &&
              math.min(s.bw, s.bh) >= minSize &&
              (refSize == 0 || ((s.bw + s.bh) / 2 - refSize).abs() <= refSize * 0.25) &&
              // Yazıdaki harfler sık dizilir; kitapçık daireleri arasında boşluk vardır.
              (s.nr * s.nc < 2 || (s.nr == 1 ? (s.right - s.left) / (s.nc - 1) : (s.bottom - s.top) / (s.nr - 1)) >= 1.6 * (s.bw + s.bh) / 2) &&
              !answers.any(
                (a) => s.left <= a.$1.right + a.$1.bw && s.right >= a.$1.left - a.$1.bw && s.top <= a.$1.bottom + a.$1.bh && s.bottom >= a.$1.top - a.$1.bh,
              ) &&
              isolated(s),
        )
        .toList();
    if (cands.isNotEmpty) {
      double boxDist(_Grid s, double l, double t, double r, double b) {
        final x = (s.left + s.right) / 2, y = (s.top + s.bottom) / 2;
        final dx = x < l ? l - x : (x > r ? x - r : 0.0), dy = y < t ? t - y : (y > b ? y - b : 0.0);
        return math.sqrt(dx * dx + dy * dy);
      }

      double distToNumber(_Grid s) {
        final toAnswers = answers.isEmpty ? double.infinity : answers.map((a) => boxDist(s, a.$1.left, a.$1.top, a.$1.right, a.$1.bottom)).reduce(math.min);
        if (number != null) {
          return math.min(
            toAnswers,
            boxDist(
              s,
              math.min(number.first.x, number.last.x),
              math.min(number.first.y, number.last.y),
              math.max(number.first.x, number.last.x),
              math.max(number.first.y, number.last.y),
            ),
          );
        }
        return answers.isEmpty ? s.top : toAnswers;
      }

      cands.sort((a, b) {
        // Kitapçık daireleri çoğunlukla yan yana (A B C D); alt alta tek sıra
        // daireler genelde cinsiyet, öğrenim gibi alanlardır.
        final hz = (b.nr == 1 ? 1 : 0).compareTo(a.nr == 1 ? 1 : 0);
        if (hz != 0) return hz;
        // Sonra numara alanına (yoksa cevap alanına) en yakın olan: başlık
        // yazısındaki harfler gibi uzaktaki "daireler" elenir.
        final da = distToNumber(a), db = distToNumber(b);
        if ((da - db).abs() > 10) return da.compareTo(db);
        // Daha çok daireli sıra (A B C D) iki daireli kırıntıdan önce gelir.
        final cnt = (b.nr * b.nc).compareTo(a.nr * a.nc);
        if (cnt != 0) return cnt;
        // Eşit uzaklıkta üstteki (cinsiyet gibi alanlar genelde daha aşağıda).
        return a.top.compareTo(b.top);
      });

      final g = cands.first;
      booklet = BookletBlock(count: g.nr * g.nc, first: g.first, last: g.last);
    }
    ignored += singles.length - (booklet == null ? 0 : 1);

    // Soru numaraları: formlar çoğunlukla sütun sütun numaralanır. Yatayda
    // örtüşen bloklar bir sütundur; sütunlar soldan sağa, her sütunda üstten alta.
    answers.sort((a, b) => a.$1.left.compareTo(b.$1.left));
    final columns = <List<(_Grid, bool)>>[];
    for (final a in answers) {
      final col = columns.where((c) => c.any((o) => a.$1.left - a.$1.bw < o.$1.right + o.$1.bw && o.$1.left - o.$1.bw < a.$1.right + a.$1.bw)).firstOrNull;
      if (col != null) {
        col.add(a);
      } else {
        columns.add([a]);
      }
    }
    final blocks = <TemplateBlock>[];
    var start = 1;
    for (final col in columns) {
      col.sort((a, b) => a.$1.top.compareTo(b.$1.top));
      for (final (g, rows) in col) {
        final count = rows ? g.nr : g.nc;
        final choices = rows ? g.nc : g.nr;
        blocks.add(TemplateBlock(start: start, count: count, choices: choices, first: g.first, last: g.last, rows: rows));
        start += count;
      }
    }
    NameBlock? name;
    if (names.isNotEmpty) {
      names.sort((a, b) => (b.nr * b.nc).compareTo(a.nr * a.nc));
      final g = names.first;
      name = NameBlock(columns: g.nc, letters: NameBlock.alphabetFor(g.nr, lang)!, first: g.first, last: g.last);
    }
    return DetectedForm(blocks: blocks, number: number, booklet: booklet, name: name, extraNumbers: extraNumbers, ignored: ignored);
  }

  /// Düzenli formlarda bloklar bir tablo gibi dizilir (ör. 6 sütun × 5 sıra
  /// beşer soruluk blok). Bulunan blokların sütun ve sıra konumlarından
  /// eksik kalan blokların yeri tahmin edilir; orada gerçekten daireler varsa eklenir.
  void _fillMissingBlocks(List<(_Grid, bool)> answers) {
    if (answers.length < 3) return;
    final shapes = <String, int>{};
    for (final (g, _) in answers) {
      shapes['${g.nr}x${g.nc}'] = (shapes['${g.nr}x${g.nc}'] ?? 0) + 1;
    }
    final shape = shapes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    final same = [
      for (final a in answers)
        if ('${a.$1.nr}x${a.$1.nc}' == shape) a.$1,
    ];
    if (same.length < 3) return;
    final nr = same.first.nr, nc = same.first.nc;
    final bw = _median([for (final g in same) g.right - g.left]), bh = _median([for (final g in same) g.bottom - g.top]);
    final size = _median([for (final g in same) (g.bw + g.bh) / 2]);
    List<List<_Grid>> groups(double Function(_Grid) key, double tol) {
      final sorted = [...same]..sort((a, b) => key(a).compareTo(key(b)));
      final out = <List<_Grid>>[];
      for (final g in sorted) {
        if (out.isNotEmpty && (key(g) - key(out.last.last)).abs() < tol) {
          out.last.add(g);
        } else {
          out.add([g]);
        }
      }
      return out;
    }

    final cols = groups((g) => g.left, math.max(bw, size) * 0.5);
    final rows = groups((g) => g.top, math.max(bh, size) * 0.5);
    if (cols.length < 2 || rows.length < 2) return;
    double mean(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
    final colX = [for (final c in cols) mean(c.map((g) => g.left))];
    final rowY = [for (final r in rows) mean(r.map((g) => g.top))];
    final r = size / 2;
    for (var ci = 0; ci < cols.length; ci++) {
      for (var ri = 0; ri < rows.length; ri++) {
        final exists = answers.any((a) => (a.$1.left - colX[ci]).abs() < bw * 0.5 + size && (a.$1.top - rowY[ri]).abs() < bh * 0.5 + size);
        if (exists) continue;
        // Bu sıradaki bloklar sütun ortalamasından ne kadar kaymış (eğik kâğıt)?
        final dx = rows[ri].map((g) => g.left - colX[cols.indexWhere((c) => c.contains(g))]);
        final dy = cols[ci].map((g) => g.top - rowY[rows.indexWhere((rr) => rr.contains(g))]);
        final x0 = colX[ci] + mean(dx), y0 = rowY[ri] + mean(dy);
        _Grid? best;
        var bestHits = 0;
        for (var oy = -4; oy <= 4; oy += 2) {
          for (var ox = -4; ox <= 4; ox += 2) {
            final xs = [for (var k = 0; k < nc; k++) x0 + ox + bw * k / (nc - 1)];
            final ys = [for (var k = 0; k < nr; k++) y0 + oy + bh * k / (nr - 1)];
            if (xs.last + r > w || ys.last + r > h || xs.first - r < 0 || ys.first - r < 0) continue;
            var hits = 0;
            for (final y in ys) {
              for (final x in xs) {
                if (_ringAt(x, y, r)) hits++;
              }
            }
            if (hits > bestHits) {
              bestHits = hits;
              best = _Grid(xs, ys, size, size);
            }
          }
        }
        if (best != null && bestHits >= nr * nc * 0.5) answers.add((best, true));
      }
    }
  }

  static int _mode(List<int> v) {
    final c = <int, int>{};
    for (final x in v) {
      c[x] = (c[x] ?? 0) + 1;
    }
    return c.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
