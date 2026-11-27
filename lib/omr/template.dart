import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/models.dart';
import 'form_layout.dart';
import 'homography.dart';
import 'omr_reader.dart';

/// Başka firmaların optik formları için şablon.
///
/// Koordinatlar "sayfa birimi"ndedir: sayfa genişliği 1000, yüksekliği
/// 1000 × [aspect]. Sayfa, fotoğraftaki kâğıdın dört kenarından bulunur ve
/// düzleştirilir; daireler bu düzlemde öğretmenin işaretlediği yerlerdedir.
class FormTemplate {
  final String id;
  final String name;

  /// Yükseklik / genişlik (A4 dikey ≈ 1.414).
  final double aspect;
  final List<TemplateBlock> blocks;
  final NumberBlock? number;

  /// Kitapçık türü daireleri (A, B, C…); yoksa null.
  final BookletBlock? booklet;

  /// Ad soyad harf ızgarası (her sütun bir harf); yoksa null.
  final NameBlock? nameGrid;

  /// Öğrenci numarası dışındaki numara alanları (TC kimlik no, okul no…).
  /// Öğrenci eşleştirmede numara bulunamazsa bunlar da denenir.
  final List<NumberBlock> extraNumbers;

  /// Diğer kodlama alanları (doğum tarihi, cinsiyet, sınıf, şube…).
  final List<CodedField> fields;

  const FormTemplate({
    required this.id,
    required this.name,
    this.aspect = 297 / 210,
    this.blocks = const [],
    this.number,
    this.booklet,
    this.nameGrid,
    this.extraNumbers = const [],
    this.fields = const [],
  });

  static const width = 1000.0;
  double get height => width * aspect;

  /// Şablonun kapsadığı soru sayısı.
  int get questionCount => blocks.fold(0, (m, b) => math.max(m, b.start + b.count - 1));

  /// Şablonun en fazla şık sayısı.
  int get choiceCount => blocks.fold(0, (m, b) => math.max(m, b.choices));

  FormTemplate copyWith(
          {String? id,
          String? name,
          double? aspect,
          List<TemplateBlock>? blocks,
          NumberBlock? number,
          bool clearNumber = false,
          BookletBlock? booklet,
          bool clearBooklet = false,
          NameBlock? nameGrid,
          bool clearNameGrid = false,
          List<NumberBlock>? extraNumbers,
          List<CodedField>? fields}) =>
      FormTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        aspect: aspect ?? this.aspect,
        blocks: blocks ?? this.blocks,
        number: clearNumber ? null : (number ?? this.number),
        booklet: clearBooklet ? null : (booklet ?? this.booklet),
        nameGrid: clearNameGrid ? null : (nameGrid ?? this.nameGrid),
        extraNumbers: extraNumbers ?? this.extraNumbers,
        fields: fields ?? this.fields,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aspect': aspect,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        if (number != null) 'number': number!.toJson(),
        if (booklet != null) 'booklet': booklet!.toJson(),
        if (nameGrid != null) 'nameGrid': nameGrid!.toJson(),
        if (extraNumbers.isNotEmpty) 'extraNumbers': [for (final n in extraNumbers) n.toJson()],
        if (fields.isNotEmpty) 'fields': [for (final f in fields) f.toJson()],
      };

  factory FormTemplate.fromJson(Map<String, dynamic> j) => FormTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        aspect: (j['aspect'] as num?)?.toDouble() ?? 297 / 210,
        blocks: [for (final b in (j['blocks'] as List?) ?? const []) TemplateBlock.fromJson(b as Map<String, dynamic>)],
        number: j['number'] == null ? null : NumberBlock.fromJson(j['number'] as Map<String, dynamic>),
        booklet: j['booklet'] == null ? null : BookletBlock.fromJson(j['booklet'] as Map<String, dynamic>),
        nameGrid: j['nameGrid'] == null ? null : NameBlock.fromJson(j['nameGrid'] as Map<String, dynamic>),
        extraNumbers: [for (final n in (j['extraNumbers'] as List?) ?? const []) NumberBlock.fromJson(n as Map<String, dynamic>)],
        fields: [for (final f in (j['fields'] as List?) ?? const []) CodedField.fromJson(f as Map<String, dynamic>)],
      );

  /// Paylaşım dosyası (başka öğretmene gönderilen şablon).
  static const fileKind = 'netice-sablon';

  Map<String, dynamic> toShareJson() => {'kind': fileKind, 'version': 1, 'template': toJson()};

  /// Paylaşım dosyasını okur; yeni bir kimlik verir. Geçersizse null.
  static FormTemplate? fromShareJson(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final t = m['kind'] == fileKind ? (m['template'] as Map).cast<String, dynamic>() : m;
      final tpl = FormTemplate.fromJson({...t, 'id': 'tpl_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'});
      if (tpl.blocks.isEmpty) return null;
      return tpl;
    } catch (_) {
      return null;
    }
  }
}

/// Ad soyad harf ızgarası: her sütun bir harf, harfler yukarıdan aşağı.
class NameBlock {
  /// Optik formlarda kullanılan alfabeler: (dil kodu, harfler).
  static const alphabets = <(String, String)>[
    ('tr', 'ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ'),
    ('en', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
    ('es', 'ABCDEFGHIJKLMNÑOPQRSTUVWXYZ'),
    ('de', 'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ'),
    ('az', 'ABCÇDEƏFGĞHXIİJKQLMNOÖPRSŞTUÜVYZ'),
    ('ru', 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'),
    ('ru', 'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'),
    ('ar', 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي'),
  ];
  static String get turkish => alphabets[0].$2;
  static String get english => alphabets[1].$2;

  /// [rows] harfli ızgara için alfabe: önce uygulama dili, sonra sıradaki ilk uyan.
  static String? alphabetFor(int rows, String lang) {
    final fit = alphabets.where((a) => a.$2.length == rows).toList();
    if (fit.isEmpty) return null;
    return (fit.where((a) => a.$1 == lang).firstOrNull ?? (lang == 'pt' || lang == 'id' || lang == 'fr' || lang == 'it'
            ? fit.where((a) => a.$1 == 'en').firstOrNull
            : null) ??
        fit.first).$2;
  }

  final int columns;
  final String letters;

  /// İlk sütunun ilk harfi ve son sütunun son harfinin merkezleri.
  final Pt first, last;

  const NameBlock({required this.columns, required this.letters, required this.first, required this.last});

  int get rows => letters.length;

  Pt bubble(int col, int row) {
    final fx = columns <= 1 ? 0.0 : col / (columns - 1);
    final fy = rows <= 1 ? 0.0 : row / (rows - 1);
    return Pt(first.x + (last.x - first.x) * fx, first.y + (last.y - first.y) * fy);
  }

  double get radius => _radius(first, last, columns, rows);

  Map<String, dynamic> toJson() => {'columns': columns, 'letters': letters, 'first': [first.x, first.y], 'last': [last.x, last.y]};

  factory NameBlock.fromJson(Map<String, dynamic> j) => NameBlock(
      columns: j['columns'] as int, letters: j['letters'] as String, first: _pt(j['first']), last: _pt(j['last']));
}

/// Formdaki diğer bir kodlama alanı: doğum tarihi, cinsiyet, sınıf, şube…
///
/// [perColumn] true ise her sütun bir karakterdir (rakam ya da harf;
/// [options] satırların karşılığı). false ise tüm daireler tek bir seçimdir
/// (Kadın/Erkek gibi; [options] her dairenin adı, sütun sütun).
class CodedField {
  final String label;
  final int columns, rows;
  final bool perColumn;
  final List<String> options;

  /// İlk sütunun ilk dairesi ve son sütunun son dairesinin merkezleri.
  final Pt first, last;

  /// Ölçülen daire yarıçapı (aralıklı seçeneklerde aralıktan hesaplanan
  /// yarıçap çok büyük kalır); yoksa aralıktan.
  final double? bubbleRadius;

  const CodedField(
      {required this.label,
      required this.columns,
      required this.rows,
      required this.perColumn,
      required this.options,
      required this.first,
      required this.last,
      this.bubbleRadius});

  static const digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

  /// Tek seçimli alanda varsayılan seçenek adları: A, B, C…
  static List<String> letterOptions(int n) => [for (var i = 0; i < n; i++) String.fromCharCode(65 + i)];

  int get cells => columns * rows;

  Pt bubble(int col, int row) {
    final fx = columns <= 1 ? 0.0 : col / (columns - 1);
    final fy = rows <= 1 ? 0.0 : row / (rows - 1);
    return Pt(first.x + (last.x - first.x) * fx, first.y + (last.y - first.y) * fy);
  }

  double get radius {
    final r = _radius(first, last, columns, rows);
    final b = bubbleRadius;
    return b == null ? r : math.min(r, b * 0.95);
  }

  CodedField copyWith({String? label, List<String>? options}) => CodedField(
      label: label ?? this.label,
      columns: columns,
      rows: rows,
      perColumn: perColumn,
      options: options ?? this.options,
      first: first,
      last: last,
      bubbleRadius: bubbleRadius);

  Map<String, dynamic> toJson() => {
        'label': label,
        'columns': columns,
        'rows': rows,
        'perColumn': perColumn,
        'options': options,
        'first': [first.x, first.y],
        'last': [last.x, last.y],
        if (bubbleRadius != null) 'r': bubbleRadius,
      };

  factory CodedField.fromJson(Map<String, dynamic> j) => CodedField(
        label: j['label'] as String? ?? '',
        columns: j['columns'] as int,
        rows: j['rows'] as int,
        perColumn: j['perColumn'] as bool? ?? false,
        options: [for (final o in (j['options'] as List?) ?? const []) '$o'],
        first: _pt(j['first']),
        last: _pt(j['last']),
        bubbleRadius: (j['r'] as num?)?.toDouble(),
      );
}

/// Kitapçık türü daireleri: tek sıra (yan yana ya da alt alta) A, B, C…
class BookletBlock {
  final int count;

  /// A ve son harfin merkezleri.
  final Pt first, last;

  const BookletBlock({required this.count, required this.first, required this.last});

  Pt bubble(int k) {
    final f = count <= 1 ? 0.0 : k / (count - 1);
    return Pt(first.x + (last.x - first.x) * f, first.y + (last.y - first.y) * f);
  }

  double get radius {
    if (count <= 1) return 7;
    final d = math.sqrt(math.pow(last.x - first.x, 2) + math.pow(last.y - first.y, 2)) / (count - 1);
    return d * 0.36;
  }

  Map<String, dynamic> toJson() => {'count': count, 'first': [first.x, first.y], 'last': [last.x, last.y]};

  factory BookletBlock.fromJson(Map<String, dynamic> j) =>
      BookletBlock(count: j['count'] as int, first: _pt(j['first']), last: _pt(j['last']));
}

/// Bir cevap bloğu: art arda gelen sorular, düzenli bir ızgarada.
class TemplateBlock {
  /// Bloğun ilk sorusunun numarası (1'den).
  final int start;
  final int count;
  final int choices;

  /// İlk sorunun ilk şıkkı ve son sorunun son şıkkının merkezleri (sayfa birimi).
  final Pt first, last;

  /// true: her satır bir soru, şıklar yan yana (en yaygın).
  /// false: her sütun bir soru, şıklar alt alta.
  final bool rows;

  const TemplateBlock({
    required this.start,
    required this.count,
    required this.choices,
    required this.first,
    required this.last,
    this.rows = true,
  });

  /// [q]. sorunun (bloğun içinde, 0'dan) [c]. şıkkının merkezi.
  Pt bubble(int q, int c) {
    final fq = count <= 1 ? 0.0 : q / (count - 1);
    final fc = choices <= 1 ? 0.0 : c / (choices - 1);
    final fx = rows ? fc : fq, fy = rows ? fq : fc;
    return Pt(first.x + (last.x - first.x) * fx, first.y + (last.y - first.y) * fy);
  }

  /// Daire yarıçapı: komşu daireler arası mesafeden.
  double get radius => _radius(first, last, rows ? choices : count, rows ? count : choices);

  Map<String, dynamic> toJson() => {
        'start': start,
        'count': count,
        'choices': choices,
        'first': [first.x, first.y],
        'last': [last.x, last.y],
        if (!rows) 'rows': false,
      };

  factory TemplateBlock.fromJson(Map<String, dynamic> j) => TemplateBlock(
        start: j['start'] as int,
        count: j['count'] as int,
        choices: j['choices'] as int,
        first: _pt(j['first']),
        last: _pt(j['last']),
        rows: j['rows'] as bool? ?? true,
      );
}

/// Öğrenci numarası bloğu: her sütun bir basamak, 0–9 yukarıdan aşağı.
class NumberBlock {
  final int digits;

  /// İlk basamağın 0'ı ve son basamağın 9'unun merkezleri.
  final Pt first, last;

  const NumberBlock({required this.digits, required this.first, required this.last});

  Pt bubble(int d, int v) {
    final fx = digits <= 1 ? 0.0 : d / (digits - 1);
    return Pt(first.x + (last.x - first.x) * fx, first.y + (last.y - first.y) * v / 9);
  }

  double get radius => _radius(first, last, digits, 10);

  Map<String, dynamic> toJson() => {'digits': digits, 'first': [first.x, first.y], 'last': [last.x, last.y]};

  factory NumberBlock.fromJson(Map<String, dynamic> j) =>
      NumberBlock(digits: j['digits'] as int, first: _pt(j['first']), last: _pt(j['last']));
}

Pt _pt(Object? v) {
  final l = v as List;
  return Pt((l[0] as num).toDouble(), (l[1] as num).toDouble());
}

double _radius(Pt a, Pt b, int nx, int ny) {
  final sx = nx <= 1 ? double.infinity : (b.x - a.x).abs() / (nx - 1);
  final sy = ny <= 1 ? double.infinity : (b.y - a.y).abs() / (ny - 1);
  final s = math.min(sx, sy);
  return (s.isFinite ? s : 20) * 0.36;
}

// ---------------------------------------------------------------------------
// Sayfa bulma

/// Fotoğraftaki kâğıdın dört köşesini bulur (sol üst, sağ üst, sağ alt, sol alt).
/// Kâğıt, kendisinden koyu bir zemin üzerinde olmalıdır. Tarayıcı görüntüsünde
/// (kâğıt tüm görüntüyü kaplıyorsa) görüntünün köşeleri döner.
class PageFinder {
  static List<Pt> find(GrayImage image, {double aspect = 297 / 210}) {
    const target = 800;
    final f = math.max(1, (math.max(image.width, image.height) / target).ceil());
    final w = image.width ~/ f, h = image.height ~/ f;
    final small = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        small[y * w + x] = image.at(x * f, y * f);
      }
    }
    // Renkli fotoğrafta kâğıttan belirgin biçimde sıcak (kırmızımsı/kahverengi)
    // pikseller zemindir: açık renkli ahşap masada da kâğıt ayrılsın.
    final warm = image.warmth;
    if (warm != null) {
      final ref = <int>[];
      for (var y = h * 3 ~/ 10; y < h * 7 ~/ 10; y += 2) {
        for (var x = w * 3 ~/ 10; x < w * 7 ~/ 10; x += 2) {
          ref.add(warm[(y * f) * image.width + x * f]);
        }
      }
      ref.sort();
      final paper = ref[ref.length ~/ 2];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final extra = warm[(y * f) * image.width + x * f] - paper - 10;
          if (extra > 0) small[y * w + x] = math.max(0, small[y * w + x] - extra * 4);
        }
      }
    }
    final t = _otsu(small);
    // Kenarlara değen parlak bölge yoksa ya da bölge tüm görüntüyse: tarama.
    final mask = Uint8List(w * h);
    for (var i = 0; i < small.length; i++) {
      if (small[i] > t) mask[i] = 1;
    }
    // En büyük parlak bileşen.
    final label = Int32List(w * h);
    var best = 0, bestSize = 0, next = 0;
    final stack = <int>[];
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0 || label[i] != 0) continue;
      next++;
      var size = 0;
      stack.add(i);
      label[i] = next;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        size++;
        final x = p % w, y = p ~/ w;
        void visit(int q) {
          if (mask[q] == 1 && label[q] == 0) {
            label[q] = next;
            stack.add(q);
          }
        }

        if (x > 0) visit(p - 1);
        if (x < w - 1) visit(p + 1);
        if (y > 0) visit(p - w);
        if (y < h - 1) visit(p + w);
      }
      if (size > bestSize) {
        bestSize = size;
        best = next;
      }
    }
    final full = [Pt(0, 0), Pt(image.width - 1.0, 0), Pt(image.width - 1.0, image.height - 1.0), Pt(0, image.height - 1.0)];
    if (bestSize < w * h * 0.15) throw const OmrException('Kâğıt bulunamadı. Kâğıdı koyu bir zemine koyun ve tamamı görünsün.');
    if (bestSize > w * h * 0.93) return full;

    // Kaba köşeler: uç noktalar.
    var tl = 0, tr = 0, br = 0, bl = 0;
    var vtl = 1 << 30, vtr = -(1 << 30), vbr = -(1 << 30), vbl = 1 << 30;
    for (var i = 0; i < label.length; i++) {
      if (label[i] != best) continue;
      final x = i % w, y = i ~/ w;
      if (x + y < vtl) {
        vtl = x + y;
        tl = i;
      }
      if (x + y > vbr) {
        vbr = x + y;
        br = i;
      }
      if (x - y > vtr) {
        vtr = x - y;
        tr = i;
      }
      if (x - y < vbl) {
        vbl = x - y;
        bl = i;
      }
    }
    Pt at(int i) => Pt((i % w).toDouble(), (i ~/ w).toDouble());
    var corners = [at(tl), at(tr), at(br), at(bl)];

    // İnce ayar: her kenar boyunca sınır noktalarına doğru uydur, kesişimleri al.
    final boundary = <Pt>[];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (label[i] != best) continue;
        if (label[i - 1] != best || label[i + 1] != best || label[i - w] != best || label[i + w] != best) {
          boundary.add(Pt(x.toDouble(), y.toDouble()));
        }
      }
    }
    final lines = <(Pt, Pt)?>[];
    for (var s = 0; s < 4; s++) {
      final a = corners[s], b = corners[(s + 1) % 4];
      final len = _dist(a, b);
      if (len < 10) {
        lines.add(null);
        continue;
      }
      final pts = <Pt>[];
      for (final p in boundary) {
        // Kenara uzaklık ve kenar üzerindeki konum.
        final tpar = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / (len * len);
        if (tpar < 0.12 || tpar > 0.88) continue;
        final d = ((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)).abs() / len;
        if (d < len * 0.03 + 2) pts.add(p);
      }
      lines.add(pts.length < 10 ? null : _fitLine(pts));
    }
    if (lines.every((l) => l != null)) {
      final refined = <Pt>[];
      for (var s = 0; s < 4; s++) {
        final p = _intersect(lines[(s + 3) % 4]!, lines[s]!);
        if (p == null || _dist(p, corners[s]) > math.max(w, h) * 0.05) {
          refined.add(corners[s]);
        } else {
          refined.add(p);
        }
      }
      corners = refined;
    }
    // Ölçeği geri al (piksel merkezleri).
    corners = [for (final c in corners) Pt((c.x + 0.5) * f, (c.y + 0.5) * f)];
    // Kâğıt yatay görünüyorsa (dikey şablonda) sırayı bir kaydır.
    final top = _dist(corners[0], corners[1]), side = _dist(corners[1], corners[2]);
    if ((aspect > 1) != (side > top)) corners = [corners[3], corners[0], corners[1], corners[2]];
    return corners;
  }

  static double _dist(Pt a, Pt b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  /// Doğru: (nokta, yön).
  static (Pt, Pt) _fitLine(List<Pt> pts) {
    var mx = 0.0, my = 0.0;
    for (final p in pts) {
      mx += p.x;
      my += p.y;
    }
    mx /= pts.length;
    my /= pts.length;
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (final p in pts) {
      final dx = p.x - mx, dy = p.y - my;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    final ang = 0.5 * math.atan2(2 * sxy, sxx - syy);
    return (Pt(mx, my), Pt(math.cos(ang), math.sin(ang)));
  }

  static Pt? _intersect((Pt, Pt) l1, (Pt, Pt) l2) {
    final (p, r) = l1;
    final (q, s) = l2;
    final den = r.x * s.y - r.y * s.x;
    if (den.abs() < 1e-9) return null;
    final t = ((q.x - p.x) * s.y - (q.y - p.y) * s.x) / den;
    return Pt(p.x + t * r.x, p.y + t * r.y);
  }

  static int _otsu(Uint8List data) {
    final hist = List<int>.filled(256, 0);
    for (final v in data) {
      hist[v]++;
    }
    final total = data.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0, best = 0.0, t = 127;
    for (var i = 0; i < 256; i++) {
      wB += hist[i];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += i * hist[i];
      final mB = sumB / wB, mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        t = i;
      }
    }
    return t;
  }
}

// ---------------------------------------------------------------------------
// Okuma

/// Şablona göre formu okur. Sonuç, Netice formuyla aynı biçimdedir; köşe
/// işaretleri yerine sayfanın dört köşesi döner.
class TemplateReader {
  final FormTemplate template;
  final int questionCount;
  final int choiceCount;
  final OmrThresholds thresholds;

  TemplateReader(this.template, {required this.questionCount, required this.choiceCount, this.thresholds = const OmrThresholds()});

  List<Pt> get pageCorners => [
        Pt(0, 0),
        Pt(FormTemplate.width, 0),
        Pt(FormTemplate.width, template.height),
        Pt(0, template.height),
      ];

  OmrResult read(GrayImage image, {List<Pt>? corners}) {
    final page = corners ?? orient(image, PageFinder.find(image, aspect: template.aspect));
    final hom = Homography.fromPoints(pageCorners, page);
    // Siyah referansı: sayfa içindeki en koyu %0,5.
    final black = _darkLevel(image, page);
    final helper = OmrReader(FormLayout(questionCount: 1, choiceCount: 4), thresholds: thresholds);

    double fillAt(Pt p, double radius) {
      final c = hom.map(p);
      final scale = hom.scaleAt(p);
      final r = radius * scale;
      final white = OmrReader.localWhite(image, c, r * 1.9);
      // En iyi hizayı bul: küçük kaymalara karşı çevrede en koyu noktayı ara.
      var mean = OmrReader.meanInDisk(image, c, r * 0.6);
      final step = r * 0.3;
      for (final d in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final m = OmrReader.meanInDisk(image, Pt(c.x + d.$1 * step, c.y + d.$2 * step), r * 0.6);
        if (m < mean) mean = m;
      }
      final range = white - black;
      if (range < 20) return 0;
      return ((white - mean) / range).clamp(0.0, 1.0);
    }

    final answers = List<OmrQuestion>.generate(
        questionCount, (_) => const OmrQuestion(Answer.blank(), []));
    for (final b in template.blocks) {
      final r = b.radius;
      final raw = <int, List<double>>{};
      for (var q = 0; q < b.count; q++) {
        final idx = b.start - 1 + q;
        if (idx < 0 || idx >= questionCount) continue;
        raw[idx] = [for (var c = 0; c < math.min(b.choices, choiceCount); c++) fillAt(b.bubble(q, c), r)];
      }
      // İçinde harf basılı dairelerde boş daire de biraz koyu görünür: bloğun
      // boş daire düzeyini (alt çeyrek) taban sayıp ondan ölç.
      final base = _baseline([for (final f in raw.values) ...f]);
      for (final e in raw.entries) {
        final fills = _rebase(e.value, base);
        var a = helper.classify(fills);
        if (a.state == MarkState.blank || a.state == MarkState.uncertain) {
          // Açık kurşun kalemle küçük işaret: satırın diğer şıklarından
          // belirgin biçimde koyuysa işaretli say.
          final pick = _relativePick(fills);
          if (pick != null && (a.state == MarkState.blank || a.marked.length == 1)) a = Answer(MarkState.filled, {pick});
        }
        answers[e.key] = OmrQuestion(a, fills);
      }
    }

    int? booklet;
    final bb = template.booklet;
    if (bb != null && bb.count >= 2) {
      final raw = [for (var k = 0; k < bb.count; k++) fillAt(bb.bubble(k), bb.radius)];
      final fills = _rebase(raw, raw.reduce(math.min));
      final a = helper.classify(fills);
      if (a.state == MarkState.filled) booklet = a.marked.first;
    }

    (String?, String?) readNumber(NumberBlock nb) {
      final digits = StringBuffer();
      var ok = true;
      final rawDigits = [
        for (var d = 0; d < nb.digits; d++) [for (var v = 0; v < 10; v++) fillAt(nb.bubble(d, v), nb.radius)]
      ];
      final base = _baseline([for (final f in rawDigits) ...f]);
      for (var d = 0; d < nb.digits; d++) {
        final fills = _rebase(rawDigits[d], base);
        final order = [for (var v = 0; v < 10; v++) v]..sort((x, y) => fills[y].compareTo(fills[x]));
        final best = fills[order[0]], second = fills[order[1]];
        final rel = _relativePick(fills);
        if (best >= 0.25 && best - second >= 0.18 && second < thresholds.empty + 0.05) {
          digits.write(order[0]);
        } else if (rel != null) {
          // Açık kurşun kalemle küçük işaret: sütunun diğerlerinden belirgin koyu.
          digits.write(rel);
        } else if (best < thresholds.empty) {
          // Boş bırakılmış basamak (kısa numara): atla.
          digits.write('-');
        } else {
          ok = false;
          digits.write('?');
        }
      }
      // Baştaki/sondaki boş basamaklar sıfır gibi sayılır (numara sağa ya da sola yaslanmış olabilir).
      final raw = digits.toString().replaceAll('-', '');
      final p = raw.padLeft(FormLayout.studentDigits, '0');
      return (ok && raw.isNotEmpty ? p : null, raw.isEmpty || raw.replaceAll('?', '').isEmpty ? null : p);
    }

    String? number;
    String? pattern;
    final nb = template.number;
    if (nb != null) (number, pattern) = readNumber(nb);
    // Diğer numara alanları (ör. TC kimlik no ile okul numarası ayrı).
    final others = <String>[
      for (final x in template.extraNumbers) ?readNumber(x).$1
    ];

    String? name;
    final na = template.nameGrid;
    if (na != null) {
      final raw = [
        for (var c = 0; c < na.columns; c++) [for (var r = 0; r < na.rows; r++) fillAt(na.bubble(c, r), na.radius)]
      ];
      final base = _baseline([for (final f in raw) ...f]);
      final buf = StringBuffer();
      for (final col in raw) {
        final fills = _rebase(col, base);
        final pick = _relativePick(fills);
        if (pick != null) {
          buf.write(na.letters[pick]);
        } else if (fills.reduce(math.max) < thresholds.empty) {
          buf.write(' ');
        } else {
          final sorted = [...fills]..sort();
          // Belirgin bir işaret yok: boşluk say; birden çok koyu varsa okunamadı.
          buf.write(sorted.last - sorted[sorted.length ~/ 2] < 0.08 ? ' ' : '?');
        }
      }
      final text = buf.toString().trim().replaceAll(RegExp(r' +'), ' ');
      if (text.replaceAll(RegExp(r'[ ?]'), '').length >= 2) name = text;
    }

    // Diğer kodlama alanları: her sütun bir karakter ya da tek seçim.
    final fields = <String, String>{};
    for (final f in template.fields) {
      if (f.cells < 2) continue;
      final raw = [
        for (var c = 0; c < f.columns; c++) [for (var r = 0; r < f.rows; r++) fillAt(f.bubble(c, r), f.radius)]
      ];
      String? value;
      if (f.perColumn) {
        final base = _baseline([for (final col in raw) ...col]);
        final buf = StringBuffer();
        var any = false;
        for (final col in raw) {
          final fills = _rebase(col, base);
          final pick = _relativePick(fills);
          if (pick != null) {
            buf.write(pick < f.options.length ? f.options[pick] : '?');
            any = true;
          } else if (fills.reduce(math.max) < thresholds.empty) {
            buf.write(' ');
          } else {
            final sorted = [...fills]..sort();
            buf.write(sorted.last - sorted[sorted.length ~/ 2] < 0.08 ? ' ' : '?');
          }
        }
        if (any) value = buf.toString().trim();
      } else {
        final flat = [for (final col in raw) ...col];
        final fills = _rebase(flat, flat.reduce(math.min));
        var a = helper.classify(fills);
        if (a.state != MarkState.filled) {
          // İki seçenekli alanlarda (Kadın/Erkek) göreli seçim yapılamaz:
          // tek işaret diğerlerinden belirgin koyuysa yeter.
          final s = [...fills]..sort();
          if (a.state == MarkState.uncertain && a.marked.length == 1 && s.last - s[s.length - 2] >= 0.25) {
            a = Answer(MarkState.filled, a.marked);
          }
          final pick = a.state == MarkState.filled ? null : _relativePick(fills);
          if (pick != null && (a.state == MarkState.blank || a.marked.length == 1)) a = Answer(MarkState.filled, {pick});
        }
        if (a.state == MarkState.filled && a.marked.length == 1) {
          final k = a.marked.first;
          value = k < f.options.length ? f.options[k] : '${k + 1}';
        } else if (a.marked.length > 1) {
          value = '?';
        }
      }
      if (value != null && value.isNotEmpty) {
        // Aynı adlı iki alan birbirini silmesin.
        var key = f.label.trim().isEmpty ? '#${template.fields.indexOf(f) + 1}' : f.label.trim();
        for (var n = 2; fields.containsKey(key); n++) {
          key = '${f.label.trim()} ($n)';
        }
        fields[key] = value;
      }
    }

    return OmrResult(
      questions: answers,
      studentNumber: number,
      numberPattern: pattern,
      markers: page,
      booklet: booklet,
      name: name,
      otherNumbers: others,
      fields: fields,
    );
  }

  /// Bir sırada (satır ya da sütun) diğerlerinden belirgin biçimde koyu tek
  /// daire varsa onun sırası. Açık kurşun kalem ve küçük işaretler için.
  static int? _relativePick(List<double> f) {
    if (f.length < 3) return null;
    final sorted = [...f]..sort();
    final best = sorted.last, second = sorted[sorted.length - 2], mid = sorted[sorted.length ~/ 2];
    final gap = best - mid;
    if (gap < 0.12 || best - second < gap * 0.6) return null;
    return f.indexOf(best);
  }

  /// Boş dairelerin dolulukta görünen düzeyi: değerlerin alt çeyreği.
  static double _baseline(List<double> v) {
    if (v.length < 4) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 4];
  }

  static List<double> _rebase(List<double> f, double base) {
    if (base < 0.04) return f;
    final b = math.min(base, 0.6);
    return [for (final x in f) ((x - b) / (1 - b)).clamp(0.0, 1.0)];
  }

  /// Kâğıt yan ya da ters çekildiyse köşe sırasını düzeltir: dört olası yönün
  /// her birinde basılı daire çemberlerinin beklenen yerde olup olmadığına bakılır.
  List<Pt> orient(GrayImage image, List<Pt> c) {
    var best = c;
    var bestScore = -double.infinity;
    for (var k = 0; k < 4; k++) {
      final cand = [for (var i = 0; i < 4; i++) c[(i + k) % 4]];
      final score = _ringScore(image, Homography.fromPoints(pageCorners, cand));
      if (score > bestScore) {
        bestScore = score;
        best = cand;
      }
    }
    return best;
  }

  double _ringScore(GrayImage image, Homography hom) {
    final samples = <(Pt, double)>[];
    for (final b in template.blocks) {
      for (var q = 0; q < b.count; q += 3) {
        for (var ch = 0; ch < b.choices; ch++) {
          samples.add((b.bubble(q, ch), b.radius));
        }
      }
    }
    final nb = template.number;
    if (nb != null) {
      for (var d = 0; d < nb.digits; d += 2) {
        for (var v = 0; v < 10; v += 3) {
          samples.add((nb.bubble(d, v), nb.radius));
        }
      }
    }
    if (samples.isEmpty) return 0;
    var total = 0.0;
    for (final (p, r) in samples) {
      final scale = hom.scaleAt(p);
      final rr = r * scale;
      // Çember ile çemberin hemen dışı arasındaki koyuluk farkı.
      var ring = 0.0, out = 0.0;
      for (var a = 0; a < 12; a++) {
        final ang = a * math.pi / 6;
        final pr = hom.map(Pt(p.x + r * math.cos(ang), p.y + r * math.sin(ang)));
        final po = hom.map(Pt(p.x + r * 1.45 * math.cos(ang), p.y + r * 1.45 * math.sin(ang)));
        ring += OmrReader.meanInDisk(image, pr, math.max(1, rr * 0.12));
        out += OmrReader.meanInDisk(image, po, math.max(1, rr * 0.12));
      }
      total += (out - ring) / 12;
    }
    return total / samples.length;
  }

  static double _darkLevel(GrayImage im, List<Pt> page) {
    final xs = page.map((p) => p.x), ys = page.map((p) => p.y);
    final x0 = math.max(0, xs.reduce(math.min).floor()), x1 = math.min(im.width - 1, xs.reduce(math.max).ceil());
    final y0 = math.max(0, ys.reduce(math.min).floor()), y1 = math.min(im.height - 1, ys.reduce(math.max).ceil());
    final hist = List<int>.filled(256, 0);
    var n = 0;
    final step = math.max(1, ((x1 - x0) / 400).floor());
    for (var y = y0; y <= y1; y += step) {
      for (var x = x0; x <= x1; x += step) {
        hist[im.at(x, y)]++;
        n++;
      }
    }
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= n * 0.005) return v.toDouble();
    }
    return 0;
  }
}

/// Sayfayı düzleştirip şablon düzleminde (genişlik [width] piksel) bir görüntü üretir.
/// Şablon düzenleyicide ve işaretli kâğıt görüntüsünde kullanılır.
img.Image rectifyPage(GrayImage g, List<Pt> corners, {double aspect = 297 / 210, int width = 1000}) {
  final pageW = FormTemplate.width, pageH = FormTemplate.width * aspect;
  final hom = Homography.fromPoints([Pt(0, 0), Pt(pageW, 0), Pt(pageW, pageH), Pt(0, pageH)], corners);
  final s = pageW / width;
  final h = (pageH / s).round();
  final out = Uint8List(width * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < width; x++) {
      final p = hom.map(Pt(x * s, y * s));
      final xi = p.x.round(), yi = p.y.round();
      out[y * width + x] = (xi < 0 || yi < 0 || xi >= g.width || yi >= g.height) ? 255 : g.at(xi, yi);
    }
  }
  return img.Image.fromBytes(width: width, height: h, bytes: out.buffer, numChannels: 1);
}
