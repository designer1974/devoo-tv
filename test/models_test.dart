import 'package:devoo_tv/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _m3u = '''#EXTM3U
#EXTINF:-1 tvg-id="RaiYoyo.it@SD" tvg-logo="https://x/yoyo.png" group-title="Kids",Rai Yoyo (576p) [Geo-blocked]
https://a.example/yoyo.m3u8
#EXTINF:-1 tvg-id="Toon.us@SD" http-referrer="https://ref.example/" group-title="Animation;Kids",Toon TV (720p)
#EXTVLCOPT:http-user-agent=Mozilla/5.0
https://a.example/toon.m3u8
#EXTINF:-1 tvg-id="" group-title="XXX",Adult Channel
https://a.example/xxx.m3u8
#EXTINF:-1 tvg-id="RaiYoyo.it@SD" group-title="Kids",Rai Yoyo doppione
https://a.example/yoyo.m3u8
''';

void main() {
  test('legge la playlist', () {
    final l = parseM3u(_m3u);
    expect(l.length, 2); // niente adulti, niente doppioni
    expect(l[0].name, 'Rai Yoyo');
    expect(l[0].countryCode, 'IT');
    expect(l[0].flag, '🇮🇹');
    expect(l[0].geoBlocked, isTrue);
    expect(l[0].hasLogo, isTrue);
    expect(l[1].name, 'Toon TV');
    expect(l[1].headers, {'Referer': 'https://ref.example/', 'User-Agent': 'Mozilla/5.0'});
  });

  test('salvataggio compatto', () {
    final c = parseM3u(_m3u).first;
    final back = Channel.fromCompact(c.toCompact())!;
    expect(back.name, c.name);
    expect(back.geoBlocked, isTrue);
  });

  test('bandiere', () {
    expect(flagEmoji('ma'), '🇲🇦');
    expect(flagEmoji('uk'), '🇬🇧');
    expect(flagEmoji(''), '🌍');
  });
}
