import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';

/// Kâğıt okununca verilen onay: kısa "kristal" melodi ve hafif titreşim.
/// Melodi Ayarlar > Ses > Okuma sesi ile kapatılabilir; titreşim kalır.
class ScanFeedback {
  static AudioPlayer? _player;
  static bool _ready = false;

  /// Okutma ekranı açılırken çağrılır: ilk okumada gecikme olmasın.
  static Future<void> warmUp() async {
    if (_ready) return;
    try {
      final p = _player ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setSource(AssetSource('sounds/okundu.mp3'));
      await p.setVolume(0.7);
      _ready = true;
    } catch (_) {}
  }

  /// Başarılı okuma: hafif titreşim + melodi.
  static Future<void> success(AppStore store) async {
    HapticFeedback.lightImpact();
    if (!store.scanSound) return;
    try {
      if (!_ready) await warmUp();
      final p = _player;
      if (p == null) return;
      await p.stop();
      await p.resume();
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Aynı kâğıt yeniden okutuldu: yalnız çok hafif bir titreşim.
  static void duplicate() => HapticFeedback.selectionClick();
}
