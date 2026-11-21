import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/omr/omr_reader.dart';
import 'package:netice/omr/serial_scanner.dart';

OmrResult res(String number, List<int> answers) => OmrResult(
      studentNumber: number,
      markers: const [],
      questions: [for (final a in answers) OmrQuestion(Answer.choice(a), const [])],
    );

void main() {
  test('iki ardışık aynı okuma kabul edilir, aynı kâğıt tekrar sayılmaz', () {
    final s = SerialScanner();
    expect(s.feed(res('001041', [0, 1])), isNull);
    expect(s.feed(res('001041', [0, 1])), isNotNull);
    expect(s.feed(res('001041', [0, 1])), isNull);
    expect(s.feed(res('001041', [0, 1])), isNull);
  });

  test('titreyen (farklı) okumalar kabul edilmez', () {
    final s = SerialScanner();
    expect(s.feed(res('001041', [0, 1])), isNull);
    expect(s.feed(res('001041', [0, 2])), isNull);
    expect(s.feed(res('001041', [0, 1])), isNull);
    expect(s.feed(res('001041', [0, 1])), isNotNull);
  });

  test('yeni kâğıt konunca okunur; kâğıt kalkınca durum sıfırlanır', () {
    final s = SerialScanner();
    s.feed(res('001041', [0]));
    expect(s.feed(res('001041', [0])), isNotNull);
    expect(s.feed(null), isNull);
    expect(s.formVisible, isFalse);
    s.feed(res('001042', [1]));
    expect(s.feed(res('001042', [1])), isNotNull);
  });
}
