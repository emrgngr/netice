// Aynı Wi-Fi ağındaki öğretmen cihazları arasında internetsiz eşitleme.
//
// Bir cihaz "toplayıcı" olur (genellikle sınavı hazırlayan öğretmen): yerel
// ağda küçük bir kapı açar ve ekranında 4 haneli bir eşleşme kodu gösterir.
// Diğer öğretmenler aynı ağda toplayıcıyı bulur (yayın + ağ taraması), kodu
// yazar ve ortak sınavı alır ya da kendi şubesinin sonuçlarını gönderir.
// Taşınan içerik ortak sınav dosyalarıyla aynıdır (bkz. common_exam.dart);
// hiçbir veri internete ya da bir sunucuya çıkmaz.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'common_exam.dart';

/// Toplayıcının dinlediği TCP kapısı ve duyuru (UDP) kapısı.
const lanPort = 47821;
const lanBeaconPort = 47820;

/// Ağda bulunan bir toplayıcı cihaz.
class LanPeer {
  final String address;
  final int port;

  /// Toplayıcı öğretmenin adı ve sınavın adı.
  final String teacher;
  final String exam;
  const LanPeer(this.address, this.port, this.teacher, this.exam);

  String get key => '$address:$port';

  @override
  bool operator ==(Object other) => other is LanPeer && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

class LanException implements Exception {
  final String message;
  const LanException(this.message);
  @override
  String toString() => message;
}

/// Bir isteğin/yanıtın en büyük boyutu (sonuç dosyaları birkaç yüz KB olur).
const _maxMessage = 32 * 1024 * 1024;

/// Soketten tek satırlık JSON mesajı okur.
Future<Map<String, dynamic>> _readMessage(Socket s, {Duration timeout = const Duration(seconds: 20)}) async {
  final buf = BytesBuilder(copy: false);
  final done = Completer<Map<String, dynamic>>();
  late StreamSubscription<List<int>> sub;
  void finish(Object r) {
    if (done.isCompleted) return;
    if (r is Map<String, dynamic>) {
      done.complete(r);
    } else {
      done.completeError(r);
    }
    sub.cancel();
  }

  sub = s.listen((chunk) {
    final nl = chunk.indexOf(10);
    if (nl < 0) {
      buf.add(chunk);
      if (buf.length > _maxMessage) finish(const LanException('too large'));
      return;
    }
    buf.add(chunk.sublist(0, nl));
    try {
      final j = jsonDecode(utf8.decode(buf.takeBytes()));
      finish(j is Map<String, dynamic> ? j : const LanException('bad message'));
    } catch (e) {
      finish(LanException('$e'));
    }
  }, onError: (Object e) => finish(LanException('$e')), onDone: () => finish(const LanException('closed')));
  return done.future.timeout(timeout, onTimeout: () {
    sub.cancel();
    throw const LanException('timeout');
  });
}

void _send(Socket s, Map<String, dynamic> j) => s.add(utf8.encode('${jsonEncode(j)}\n'));

/// Toplayıcı (sunucu) taraf.
class LanHost {
  final String commonId;
  final String teacher;
  final String examName;

  /// Ortak sınav dosyasının metni (diğer öğretmenler sınavı buradan alır).
  final String Function() examText;

  /// Gelen sonuç dosyası. İçe aldıktan sonra kısa bir özet döndürür
  /// (ör. "9-B · 28 kâğıt"); hata varsa FormatException fırlatır.
  final String Function(String resultsText, String from) onResults;

  /// 4 haneli eşleşme kodu.
  final String pin;

  ServerSocket? _server;
  RawDatagramSocket? _beacon;
  Timer? _timer;

  LanHost({
    required this.commonId,
    required this.teacher,
    required this.examName,
    required this.examText,
    required this.onResults,
    String? pin,
  }) : pin = pin ?? (1000 + math.Random.secure().nextInt(9000)).toString();

  int get port => _server?.port ?? 0;
  bool get running => _server != null;

  Future<void> start({int port = lanPort, bool beacon = true}) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } on SocketException {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen(_handle, onError: (_) {});
    if (beacon) {
      try {
        _beacon = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _beacon!.broadcastEnabled = true;
        void ping() {
          final msg = utf8.encode(jsonEncode({'app': 'netice', 'kind': 'lan-host', 'port': this.port, 'teacher': teacher, 'exam': examName}));
          try {
            _beacon?.send(msg, InternetAddress('255.255.255.255'), lanBeaconPort);
          } catch (_) {}
        }

        ping();
        _timer = Timer.periodic(const Duration(seconds: 2), (_) => ping());
      } catch (_) {
        // Yayın izni yoksa (ör. iOS) cihazlar ağ taramasıyla ya da adresle bulur.
      }
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _beacon?.close();
    _beacon = null;
    await _server?.close();
    _server = null;
  }

  Future<void> _handle(Socket s) async {
    try {
      final req = await _readMessage(s);
      if (req['app'] != 'netice') throw const LanException('bad app');
      final op = req['op'];
      if (op == 'hello') {
        _send(s, {'ok': true, 'teacher': teacher, 'exam': examName});
      } else if (req['pin'] != pin) {
        _send(s, {'ok': false, 'error': 'pin'});
      } else if (op == 'exam') {
        _send(s, {'ok': true, 'text': examText()});
      } else if (op == 'results') {
        final text = '${req['data'] ?? ''}';
        if (commonFileKind(text) != CommonExamFile.resultsKind) {
          _send(s, {'ok': false, 'error': 'kind'});
        } else if ((jsonDecode(text) as Map)['commonId'] != commonId) {
          _send(s, {'ok': false, 'error': 'exam'});
        } else {
          try {
            final summary = onResults(text, '${req['from'] ?? ''}');
            _send(s, {'ok': true, 'summary': summary});
          } on FormatException catch (e) {
            _send(s, {'ok': false, 'error': 'format', 'message': e.message});
          }
        }
      } else {
        _send(s, {'ok': false, 'error': 'op'});
      }
      await s.flush();
    } catch (_) {
      // Bozuk ya da yarım istek: bağlantıyı kapat.
    } finally {
      await s.close().catchError((_) => s);
      s.destroy();
    }
  }

  /// Bu cihazın yerel ağ adresleri (öğretmen elle yazmak isterse).
  static Future<List<String>> localAddresses() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      final out = <String>[
        for (final i in ifs)
          for (final a in i.addresses)
            if (_private(a.address)) a.address,
      ];
      return out.toSet().toList();
    } catch (_) {
      return const [];
    }
  }

  static bool _private(String a) {
    if (a.startsWith('10.') || a.startsWith('192.168.')) return true;
    final p = a.split('.');
    if (p.length == 4 && p[0] == '172') {
      final b = int.tryParse(p[1]) ?? 0;
      return b >= 16 && b <= 31;
    }
    return false;
  }
}

/// Gönderen (istemci) taraf.
class LanClient {
  /// Tek istek: bağlan, gönder, yanıtı oku.
  static Future<Map<String, dynamic>> request(String address, int port, Map<String, dynamic> body,
      {Duration connectTimeout = const Duration(seconds: 4), Duration timeout = const Duration(seconds: 30)}) async {
    final s = await Socket.connect(address, port, timeout: connectTimeout);
    try {
      _send(s, {'app': 'netice', ...body});
      await s.flush();
      return await _readMessage(s, timeout: timeout);
    } finally {
      s.destroy();
    }
  }

  static Future<LanPeer?> hello(String address, int port, {Duration timeout = const Duration(milliseconds: 600)}) async {
    try {
      final r = await request(address, port, {'op': 'hello'}, connectTimeout: timeout, timeout: const Duration(seconds: 2));
      if (r['ok'] != true) return null;
      return LanPeer(address, port, '${r['teacher'] ?? ''}', '${r['exam'] ?? ''}');
    } catch (_) {
      return null;
    }
  }

  static void _check(Map<String, dynamic> r) {
    if (r['ok'] == true) return;
    throw LanException(switch (r['error']) {
      'pin' => 'pin',
      'exam' => 'exam',
      'kind' => 'kind',
      'format' => '${r['message'] ?? 'format'}',
      _ => '${r['error']}',
    });
  }

  /// Toplayıcıdan ortak sınav dosyasını alır.
  static Future<String> fetchExam(LanPeer p, String pin) async {
    final r = await request(p.address, p.port, {'op': 'exam', 'pin': pin});
    _check(r);
    return '${r['text']}';
  }

  /// Bu şubenin sonuç dosyasını toplayıcıya gönderir; toplayıcının özetini döndürür.
  static Future<String> sendResults(LanPeer p, String pin, String resultsText, {String from = ''}) async {
    final r = await request(p.address, p.port, {'op': 'results', 'pin': pin, 'data': resultsText, 'from': from},
        timeout: const Duration(seconds: 60));
    _check(r);
    return '${r['summary'] ?? ''}';
  }

  /// Ağdaki toplayıcıları bulur: duyuruları dinler ve aynı alt ağdaki
  /// adresleri tarar. Bulunanlar [onFound] ile hemen bildirilir.
  static Future<List<LanPeer>> discover({
    Duration timeout = const Duration(seconds: 4),
    void Function(LanPeer)? onFound,
    int port = lanPort,
  }) async {
    final found = <LanPeer>{};
    void add(LanPeer? p) {
      if (p != null && found.add(p)) onFound?.call(p);
    }

    RawDatagramSocket? udp;
    try {
      udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, lanBeaconPort, reuseAddress: true);
      udp.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = udp?.receive();
        if (d == null) return;
        try {
          final j = jsonDecode(utf8.decode(d.data)) as Map;
          if (j['app'] == 'netice' && j['kind'] == 'lan-host') {
            add(LanPeer(d.address.address, (j['port'] as num).toInt(), '${j['teacher'] ?? ''}', '${j['exam'] ?? ''}'));
          }
        } catch (_) {}
      });
    } catch (_) {
      udp = null;
    }

    // Alt ağ taraması (yayın engelli ağlar ve iOS için).
    final own = await LanHost.localAddresses();
    final targets = <String>{
      for (final a in own)
        for (var i = 1; i < 255; i++) '${a.substring(0, a.lastIndexOf('.'))}.$i',
    }..removeAll(own);
    final list = targets.toList();
    final deadline = DateTime.now().add(timeout);
    for (var i = 0; i < list.length && DateTime.now().isBefore(deadline); i += 96) {
      final batch = list.sublist(i, math.min(i + 96, list.length));
      await Future.wait([for (final a in batch) hello(a, port, timeout: const Duration(milliseconds: 450)).then(add)]);
    }
    final left = deadline.difference(DateTime.now());
    if (left > Duration.zero && found.isEmpty) await Future<void>.delayed(left);
    udp?.close();
    return found.toList();
  }
}
