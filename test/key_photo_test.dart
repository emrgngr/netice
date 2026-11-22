import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/ui/key_from_photo.dart';

void main() {
  test('cevap anahtarı doldurulmuş formun görüntüsünden okunur', () {
    const key = [1, 3, 0, 2, 4, 0, 1, 3, 2, 4];
    final form = FormRaster(FormLayout(questionCount: 10, choiceCount: 5))
        .render(answers: {for (var i = 0; i < key.length; i++) i: [key[i]]});
    final bytes = img.encodeJpg(form, quality: 90);
    final r = keyFromImageBytes(bytes, 10, 5)!;
    expect([for (final s in r) s.single], key);
  });
}
