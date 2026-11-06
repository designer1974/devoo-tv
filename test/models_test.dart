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

  test('doppioni: un canale solo con più indirizzi', () {
    const t = '''#EXTM3U
#EXTINF:-1 tvg-id="2M.ma@SD" group-title="General",2M (720p)
https://a.example/2m-1.m3u8
#EXTINF:-1 tvg-id="2M.ma@HD" group-title="General",2M (1080p)
https://a.example/2m-2.m3u8
#EXTINF:-1 tvg-id="" group-title="General",Canale Senza Id
https://a.example/x1.m3u8
#EXTINF:-1 tvg-id="" group-title="General",Canale senza id
https://a.example/x2.m3u8
''';
    final l = parseM3u(t);
    expect(l.length, 2);
    expect(l[0].urls, ['https://a.example/2m-1.m3u8', 'https://a.example/2m-2.m3u8']);
    expect(l[0].preferring('https://a.example/2m-2.m3u8').urls.first, 'https://a.example/2m-2.m3u8');
    expect(l[0].preferring('https://a.example/2m-2.m3u8').key, l[0].key);
    expect(Channel.fromCompact(l[0].toCompact())!.alts, ['https://a.example/2m-2.m3u8']);
    expect(l[1].alts.length, 1);
  });

  test('stesso logo: un canale solo', () {
    const t = '''#EXTM3U
#EXTINF:-1 tvg-id="2MMonde.ma@SD" tvg-logo="https://l/2m.png" group-title="General",2M Monde (720p)
https://a.example/m1.m3u8
#EXTINF:-1 tvg-id="2M.ma@SD" tvg-logo="https://l/2m.png" group-title="General",2M (720p)
https://a.example/m2.m3u8
#EXTINF:-1 tvg-id="2MMonde.ma@Plus1" tvg-logo="https://l/2M.png" group-title="General",2M Monde +1
https://a.example/m3.m3u8
#EXTINF:-1 tvg-id="AlAoula.ma@SD" tvg-logo="https://l/aoula.png" group-title="General",Al Aoula
https://a.example/a.m3u8
''';
    final l = parseM3u(t);
    expect(l.map((c) => c.name), ['2M', 'Al Aoula']);
    expect(l[0].urls.first, 'https://a.example/m2.m3u8');
    expect(l[0].urls.length, 3);
  });

  test('esclusi film, serie, sport e 24/7; lista nera', () {
    const t = '''#EXTM3U
#EXTINF:-1 tvg-id="Film.it@SD" group-title="Movies",Film TV
https://a.example/f.m3u8
#EXTINF:-1 tvg-id="Toon.us@SD" group-title="Animation;Kids",Cartoon 24/7
https://a.example/t.m3u8
#EXTINF:-1 tvg-id="Sport.it@SD" group-title="Sports",Sport TV
https://a.example/s.m3u8
#EXTINF:-1 tvg-id="Yoyo.it@SD" group-title="Kids",Yoyo
https://a.example/y.m3u8
#EXTINF:-1 tvg-id="Tg.it@SD" group-title="News",Tg
https://bad.example/tg.m3u8
''';
    final l = parseM3u(t);
    expect(l.map((c) => c.name), ['Yoyo', 'Tg']);
    final block = parseBlocklist('# commento\nyoyo.it\nhttps://bad.example/\n');
    expect(l.where((c) => !isBlocked(c, block)), isEmpty);
    expect(isBlocked(l[0], parseBlocklist('Altro')), isFalse);
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
