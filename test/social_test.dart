import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/ads.dart';

void main() {
  test('sosyal medya adresi kullanıcı adından ya da tam adresten', () {
    expect(SocialNetwork.normalize(SocialNetwork.instagram, '@neticeoptik'), 'https://www.instagram.com/neticeoptik');
    expect(SocialNetwork.normalize(SocialNetwork.youtube, 'neticeoptik'), 'https://www.youtube.com/@neticeoptik');
    expect(SocialNetwork.normalize(SocialNetwork.x, 'x.com/neticeoptik'), 'https://x.com/neticeoptik');
    expect(SocialNetwork.normalize(SocialNetwork.facebook, 'http://facebook.com/netice'), 'https://facebook.com/netice');
    expect(SocialNetwork.normalize(SocialNetwork.facebook, 'https://evil.com/x'), isNull);
    expect(SocialNetwork.normalize(SocialNetwork.instagram, ''), isNull);
    expect(SocialNetwork.normalize(SocialNetwork.instagram, 'a b'), isNull);
  });

  test('ayarlarda sosyal adresler gidip gelir, yabancı adres atılır', () {
    final s = AdSettings.fromJson({
      'sosyal': {'instagram': 'neticeoptik', 'x': 'https://evil.com/a', 'youtube': 'https://www.youtube.com/@netice'},
    });
    expect(s.social, {'instagram': 'https://www.instagram.com/neticeoptik', 'youtube': 'https://www.youtube.com/@netice'});
    expect(AdSettings.fromJson(s.toJson()).social, s.social);
    expect(const AdSettings().toJson().containsKey('sosyal'), isFalse);
  });
}
