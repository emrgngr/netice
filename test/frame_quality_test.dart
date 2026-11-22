import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/frame_quality.dart';
import 'package:netice/omr/omr_reader.dart';

void main() {
  final layout = FormLayout(questionCount: 30, choiceCount: 5);

  /// Masada, kamera pozlamasıyla (kâğıt saf beyaz değil) çekilmiş form.
  img.Image photo() {
    final im = FormRaster(layout).render(answers: {0: [1]}, studentNumber: '001042');
    final bg = img.Image(width: im.width + 400, height: im.height + 400, numChannels: 3);
    img.fill(bg, color: img.ColorRgb8(150, 140, 120));
    img.compositeImage(bg, im, dstX: 200, dstY: 200);
    return img.adjustColor(bg, brightness: 0.82);
  }

  FrameAdvice advise(img.Image im) {
    final g = GrayImage.fromImage(im);
    List<Pt>? m;
    try {
      m = OmrReader(layout).read(g).markers;
    } catch (_) {}
    return FrameQuality.assess(g, markers: m);
  }

  test('iyi kare: ipucu yok', () => expect(advise(photo()), FrameAdvice.ok));
  test('karanlık ortam', () => expect(advise(img.adjustColor(photo(), brightness: 0.3)), FrameAdvice.tooDark));
  test('parlama', () {
    final im = photo();
    img.fillCircle(im, x: im.width ~/ 2, y: im.height ~/ 2, radius: im.width ~/ 6, color: img.ColorRgb8(255, 255, 255));
    expect(advise(im), FrameAdvice.glare);
  });
  test('tarayıcı görüntüsü (bembeyaz kâğıt) parlama sayılmaz', () {
    final im = FormRaster(layout).render(answers: {0: [1]}, studentNumber: '001042');
    expect(advise(im), FrameAdvice.ok);
  });
  test('form bulunamayan çok bulanık kare', () {
    final im = img.gaussianBlur(img.copyResize(photo(), width: 400), radius: 12);
    expect(FrameQuality.assess(GrayImage.fromImage(im)), FrameAdvice.blurry);
  });
  test('geometri: uzak, eğik, kenarda', () {
    FrameAdvice geo(double cover, double square, double edge) => FrameQuality.advise(
        FrameStats(mean: 170, glare: 0, sharpness: 1, coverage: cover, squareness: square, edgeMargin: edge));
    expect(geo(0.5, 0.95, 0.1), FrameAdvice.ok);
    expect(geo(0.12, 0.95, 0.1), FrameAdvice.tooFar);
    expect(geo(0.5, 0.6, 0.1), FrameAdvice.tilted);
    expect(geo(0.5, 0.95, 0.005), FrameAdvice.edge);
  });
}
