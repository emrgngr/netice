import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'form_layout.dart';
import 'omr_reader.dart';
import 'rectify.dart';
import 'template.dart';

/// Bir sınavın kâğıtlarını okumak için gereken bilgi: Netice formu ya da
/// başka bir firmanın formu için şablon.
class ReadSpec {
  final int questions;
  final int choices;
  /// Kitapçık türü sayısı (1 = tek kitapçık).
  final int booklets;
  /// Öğrenci numarası hane sayısı (6 ya da 10).
  final int digits;
  final FormTemplate? template;
  const ReadSpec({required this.questions, required this.choices, this.booklets = 1, this.digits = 6, this.template});

  /// Bu sınav çeyrek A4 kısa quiz formuyla da basılabilir mi?
  bool get allowsMini => template == null && booklets == 1 && questions <= MiniFormLayout.maxQuestionsFor(digits);

}

/// Kâğıdı okur (Netice formu ya da şablon).
OmrResult readSheet(GrayImage g, ReadSpec s) {
  final t = s.template;
  if (t == null) {
    final a4 = FormLayout(questionCount: s.questions, choiceCount: s.choices, booklets: s.booklets, digits: s.digits);
    if (!s.allowsMini) return OmrReader(a4).read(g);
    return OmrReader.readAny(g, [a4, MiniFormLayout(questionCount: s.questions, choiceCount: s.choices, digits: s.digits)]);
  }
  return TemplateReader(t, questionCount: s.questions, choiceCount: s.choices).read(g);
}

/// Okunan kâğıdın düzleştirilmiş JPEG görüntüsü.
Uint8List sheetJpeg(GrayImage g, OmrResult r, ReadSpec s) {
  final t = s.template;
  if (t == null) return rectifiedJpeg(g, r.markers);
  final im = rectifyPage(g, r.markers, aspect: t.aspect, width: 840);
  return Uint8List.fromList(img.encodeJpg(im.convert(numChannels: 3), quality: 72));
}
