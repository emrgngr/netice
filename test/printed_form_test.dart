import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/omr_reader.dart';

/// Basılı PDF formun taranmış (döndürülmüş, JPEG) görüntüsünü okur.
/// Görüntü test/fixtures altında; PDF'ten üretilip kalemle doldurulmuş gibi
/// işaretlenmiştir. 6. soru boş bırakılmıştır.
void main() {
  test('basılı PDF formun döndürülmüş taraması doğru okunur', () {
    final bytes = File('test/fixtures/printed_form_scan.jpg').readAsBytesSync();
    final gray = GrayImage.decode(bytes)!;
    final r = OmrReader(FormLayout(questionCount: 20, choiceCount: 5)).read(gray);
    expect(r.studentNumber, '001042');
    const key = 'ABCDEABCDEABCDEABCDE';
    for (var q = 0; q < 20; q++) {
      final a = r.questions[q].answer;
      if (q == 5) {
        expect(a.state, MarkState.blank, reason: 'soru ${q + 1}');
        continue;
      }
      final expected = (key.codeUnitAt(q) - 65 + (q % 4 == 3 ? 1 : 0)) % 5;
      expect(a.marked, {expected}, reason: 'soru ${q + 1} ${r.questions[q].fills}');
      expect(a.state, MarkState.filled, reason: 'soru ${q + 1} ${r.questions[q].fills}');
    }
  });
}
