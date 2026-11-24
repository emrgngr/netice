import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'form_layout.dart';
import 'kid_layout.dart';
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

  /// Çocuk kitapçığının köşesindeki cevap kutusu.
  final bool kids;
  const ReadSpec(
      {required this.questions, required this.choices, this.booklets = 1, this.digits = 6, this.template, this.kids = false});

  KidLayout get kidLayout =>
      KidLayout(questionCount: questions.clamp(1, KidLayout.maxQuestions), choiceCount: choices.clamp(2, 5));
}

/// Kâğıdı okur (Netice formu ya da şablon).
OmrResult readSheet(GrayImage g, ReadSpec s) {
  if (s.kids) return KidReader(s.kidLayout).read(g);
  final t = s.template;
  if (t == null) {
    return OmrReader(FormLayout(questionCount: s.questions, choiceCount: s.choices, booklets: s.booklets, digits: s.digits)).read(g);
  }
  return TemplateReader(t, questionCount: s.questions, choiceCount: s.choices).read(g);
}

/// Okunan kâğıdın düzleştirilmiş JPEG görüntüsü.
Uint8List sheetJpeg(GrayImage g, OmrResult r, ReadSpec s) {
  if (s.kids) return kidSheetJpeg(g, s.kidLayout, r.markers);
  final t = s.template;
  if (t == null) return rectifiedJpeg(g, r.markers);
  final im = rectifyPage(g, r.markers, aspect: t.aspect, width: 840);
  return Uint8List.fromList(img.encodeJpg(im.convert(numChannels: 3), quality: 72));
}
