import 'omr_reader.dart';

/// Seri (deklanşörsüz) okuma kararı.
///
/// Kamera kareleri art arda gelir. Bir kâğıt, ancak iki ardışık karede
/// aynı biçimde okunursa kabul edilir (titreme ve bulanıklığa karşı).
/// Aynı kâğıt çerçevede kaldıkça tekrar sayılmaz; yeni kâğıt
/// konduğunda (okuma değişince) bir sonraki kabul yapılır.
class SerialScanner {
  /// Kabul için gereken ardışık aynı okuma sayısı.
  final int requiredMatches;

  /// Bu kadar ardışık karede form görünmezse son kabul edilen kâğıt
  /// unutulur; aynı cevaplı bir sonraki kâğıt da kabul edilir. 0 = hiç
  /// unutma. İsimsiz çocuk kartlarında (aynı cevaplı tam puanlı kâğıtlar
  /// art arda gelebilir) kullanılır.
  final int releaseAfter;

  SerialScanner({this.requiredMatches = 2, this.releaseAfter = 0});

  int _gone = 0;

  String? _candidate;
  int _matches = 0;
  String? _lastAccepted;

  /// Son durumda form çerçevede görünüyor mu (arayüz ipucu için).
  bool formVisible = false;

  static String signature(OmrResult r) =>
      '${r.studentNumber ?? r.code?.studentNumber ?? '?'}|${r.questions.map((q) => '${q.answer.state.index}${q.answer.marked.join()}').join(',')}';

  /// Bir karenin sonucunu verir; kabul edilen yeni bir kâğıt varsa döndürür.
  OmrResult? feed(OmrResult? r) {
    if (r == null) {
      formVisible = false;
      _candidate = null;
      _matches = 0;
      if (releaseAfter > 0 && ++_gone >= releaseAfter) _lastAccepted = null;
      return null;
    }
    _gone = 0;
    formVisible = true;
    final sig = signature(r);
    if (sig == _lastAccepted) return null; // aynı kâğıt hâlâ çerçevede
    if (sig == _candidate) {
      _matches++;
    } else {
      _candidate = sig;
      _matches = 1;
    }
    if (_matches >= requiredMatches) {
      _lastAccepted = sig;
      _candidate = null;
      _matches = 0;
      return r;
    }
    return null;
  }

  /// Kullanıcı aynı kâğıdı bilerek yeniden okutmak isterse.
  void reset() {
    _lastAccepted = null;
    _candidate = null;
    _matches = 0;
  }
}
