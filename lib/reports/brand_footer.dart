// Uygulamanın ürettiği belgelerin altındaki tanıtım şeridi: Netice logosu,
// kısa slogan ve Google Play / App Store'un resmî "indir" rozetleri.
// Rozetler assets/badges/ altındadır (resmî kaynaktan, değiştirilmeden;
// .github/workflows/magaza-rozetleri.yml ile indirilir).
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/legal.dart';
import '../l10n/l10n.dart';

class BrandAssets {
  final pw.MemoryImage? logo;
  final pw.MemoryImage? googlePlay;
  final String? appStoreSvg;
  const BrandAssets({this.logo, this.googlePlay, this.appStoreSvg});

  static BrandAssets? _cached;
  static String? _cachedLang;

  /// Yüklenmiş rozetler (yüklenmediyse boş; şerit yalnız metinle çizilir).
  static BrandAssets get current => _cached ?? const BrandAssets();

  /// Logo ve uygulama dilindeki rozetleri bir kez yükler.
  static Future<BrandAssets> load() async {
    final lang = L10n.code;
    if (_cached != null && _cachedLang == lang) return _cached!;
    Future<pw.MemoryImage?> img(String path) async {
      try {
        return pw.MemoryImage((await rootBundle.load(path)).buffer.asUint8List());
      } catch (_) {
        return null;
      }
    }

    Future<String?> text(String path) async {
      try {
        return await rootBundle.loadString(path);
      } catch (_) {
        return null;
      }
    }

    _cached = BrandAssets(
      logo: await img('assets/brand/netice_logo_160.png'),
      googlePlay: await img('assets/badges/google_play_$lang.png') ?? await img('assets/badges/google_play_en.png'),
      appStoreSvg: await text('assets/badges/app_store_$lang.svg') ?? await text('assets/badges/app_store_en.svg'),
    );
    _cachedLang = lang;
    return _cached!;
  }
}

const _ink = PdfColor.fromInt(0xFF0F1B3D);
const _emerald = PdfColor.fromInt(0xFF10B981);
const _muted = PdfColor.fromInt(0xFF6B7280);

/// Şeridin yüksekliği (sayfa düzeni hesapları için).
const brandStripHeight = 22.0;

/// Logo + "Netice ile hazırlandı" + slogan + mağaza rozetleri.
pw.Widget brandStrip({BrandAssets? assets, bool divider = true}) {
  final a = assets ?? BrandAssets.current;
  const h = 14.0;
  // Google'ın web rozetinin kendi saydam kenar boşluğu var; görünür kısmı
  // App Store rozetiyle aynı boyda olsun diye biraz büyük çizilir.
  const playH = h * 1.38;
  return pw.Container(
    height: brandStripHeight,
    padding: const pw.EdgeInsets.only(top: 3),
    decoration: divider ? const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.5))) : null,
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      if (a.logo != null) ...[
        pw.ClipRRect(horizontalRadius: 3, verticalRadius: 3, child: pw.Image(a.logo!, width: h, height: h)),
        pw.SizedBox(width: 5),
      ],
      pw.Expanded(
        child: pw.UrlLink(
          destination: downloadUrl,
          child: pw.RichText(
            maxLines: 2,
            text: pw.TextSpan(style: const pw.TextStyle(fontSize: 6.5, color: _muted), children: [
              pw.TextSpan(text: tr('Netice ile hazırlandı'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink)),
              const pw.TextSpan(text: '  ·  '),
              pw.TextSpan(text: tr('Optik kâğıtları telefonla okutun, sonuç ve karne saniyeler içinde.')),
              const pw.TextSpan(text: ' '),
              pw.TextSpan(text: tr('Ücretsiz indirin'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _emerald)),
            ]),
          ),
        ),
      ),
      if (a.googlePlay != null) ...[
        pw.SizedBox(width: 4),
        pw.UrlLink(
          destination: playStoreUrl,
          child: pw.Image(a.googlePlay!, height: playH),
        ),
      ],
      if (a.appStoreSvg != null) ...[
        pw.SizedBox(width: 6),
        pw.UrlLink(destination: appStoreUrl.isNotEmpty ? appStoreUrl : downloadUrl, child: pw.SvgImage(svg: a.appStoreSvg!, height: h)),
      ],
    ]),
  );
}
