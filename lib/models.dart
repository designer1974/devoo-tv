/// Canali TV e lettura delle playlist M3U di iptv-org.
library;

/// Bandiera emoji dal codice paese (IT → 🇮🇹). Codice non valido → 🌍
String flagEmoji(String code) {
  var c = code.trim().toUpperCase();
  if (c == 'UK') c = 'GB';
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '🌍';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 65));
}

class Channel {
  final String id; // tvg-id, es. "RaiYoyo.it@SD"
  final String name;
  final String url;
  final String logo;
  final String group;
  final String referrer;
  final String userAgent;
  final bool geoBlocked;

  const Channel({
    required this.id,
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '',
    this.referrer = '',
    this.userAgent = '',
    this.geoBlocked = false,
  });

  /// Chiave unica (lo stesso canale può avere più indirizzi).
  String get key => url;

  /// Paese dal tvg-id: "CartoonNetwork.us@SD" → "US".
  String get countryCode {
    final m = RegExp(r'\.([a-z]{2})(@|$)').firstMatch(id.toLowerCase());
    return m == null ? '' : m.group(1)!.toUpperCase();
  }

  String get flag => flagEmoji(countryCode);
  bool get hasLogo => logo.startsWith('http');

  bool get isAdult {
    final t = '$name $group'.toLowerCase();
    return t.contains('xxx') || t.contains('adult') || t.contains('erotic') || t.contains('porn');
  }

  Map<String, String> get headers => {
        if (referrer.isNotEmpty) 'Referer': referrer,
        if (userAgent.isNotEmpty) 'User-Agent': userAgent,
      };

  List<String> toCompact() => [id, name, url, logo, group, referrer, userAgent, geoBlocked ? '1' : ''];

  static Channel? fromCompact(Object? o) {
    if (o is! List || o.length < 8) return null;
    final url = '${o[2]}';
    if (!url.startsWith('http')) return null;
    return Channel(
      id: '${o[0]}',
      name: '${o[1]}',
      url: url,
      logo: '${o[3]}',
      group: '${o[4]}',
      referrer: '${o[5]}',
      userAgent: '${o[6]}',
      geoBlocked: o[7] == '1',
    );
  }
}

String _attr(String line, String name) {
  final m = RegExp('$name="([^"]*)"').firstMatch(line);
  return m?.group(1)?.trim() ?? '';
}

/// Nome pulito: senza "(1080p)", "[Geo-blocked]", "[Not 24/7]".
String cleanChannelName(String raw) => raw
    .replaceAll(RegExp(r'\(\d{3,4}[pi]\)'), '')
    .replaceAll(RegExp(r'\[[^\]]*\]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Legge una playlist M3U. Niente canali per adulti, niente doppioni.
List<Channel> parseM3u(String text) {
  final out = <Channel>[];
  final seen = <String>{};
  String? info;
  var referrer = '', ua = '';
  for (var line in const LineSplitterLite().split(text)) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      info = line;
      referrer = _attr(line, 'http-referrer');
      ua = _attr(line, 'http-user-agent');
    } else if (line.startsWith('#EXTVLCOPT:http-referrer=')) {
      referrer = line.substring('#EXTVLCOPT:http-referrer='.length).trim();
    } else if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
      ua = line.substring('#EXTVLCOPT:http-user-agent='.length).trim();
    } else if (!line.startsWith('#') && info != null) {
      final comma = info.lastIndexOf('",');
      final rawName = comma >= 0 ? info.substring(comma + 2) : info.split(',').last;
      final c = Channel(
        id: _attr(info, 'tvg-id'),
        name: cleanChannelName(rawName),
        url: line,
        logo: _attr(info, 'tvg-logo'),
        group: _attr(info, 'group-title'),
        referrer: referrer,
        userAgent: ua,
        geoBlocked: rawName.contains('[Geo-blocked]'),
      );
      if (c.url.startsWith('http') && c.name.isNotEmpty && !c.isAdult && seen.add(c.url)) out.add(c);
      info = null;
      referrer = '';
      ua = '';
    }
  }
  return out;
}

/// Divide in righe senza importare dart:convert nei test.
class LineSplitterLite {
  const LineSplitterLite();
  Iterable<String> split(String s) => s.split(RegExp(r'\r?\n'));
}

/// Un paese con i suoi canali.
class Country {
  final String code; // es. "it"
  final String name;
  const Country(this.code, this.name);
  String get flag => flagEmoji(code);
}

/// Le categorie del mondo (iptv-org). Niente "xxx".
const worldCategories = <(String, String, String)>[
  ('news', '📰', 'Notizie'),
  ('general', '📺', 'Generali'),
  ('entertainment', '🎭', 'Intrattenimento'),
  ('movies', '🎬', 'Film'),
  ('series', '🎞️', 'Serie'),
  ('sports', '⚽', 'Sport'),
  ('music', '🎵', 'Musica'),
  ('documentary', '🦁', 'Documentari'),
  ('education', '🎓', 'Educazione'),
  ('science', '🔬', 'Scienza'),
  ('culture', '🏛️', 'Cultura'),
  ('cooking', '🍝', 'Cucina'),
  ('travel', '✈️', 'Viaggi'),
  ('outdoor', '🏕️', 'Natura'),
  ('comedy', '😂', 'Comici'),
  ('classic', '📼', 'Classici'),
  ('animation', '🎨', 'Animazione'),
  ('family', '👨‍👩‍👧', 'Famiglia'),
  ('lifestyle', '💄', 'Stile'),
  ('business', '💼', 'Economia'),
  ('weather', '⛅', 'Meteo'),
  ('religious', '🕌', 'Religione'),
  ('legislative', '🏛', 'Parlamento'),
  ('auto', '🚗', 'Motori'),
  ('relax', '🌊', 'Relax'),
  ('shop', '🛍️', 'Shopping'),
];

/// Paesi di riserva se l'elenco online non si carica.
const fallbackCountries = <Country>[
  Country('it', 'Italia'), Country('ma', 'Marocco'), Country('fr', 'Francia'), Country('es', 'Spagna'),
  Country('gb', 'Regno Unito'), Country('us', 'Stati Uniti'), Country('de', 'Germania'), Country('pt', 'Portogallo'),
  Country('dz', 'Algeria'), Country('tn', 'Tunisia'), Country('eg', 'Egitto'), Country('sa', 'Arabia Saudita'),
  Country('ae', 'Emirati Arabi'), Country('tr', 'Turchia'), Country('nl', 'Paesi Bassi'), Country('be', 'Belgio'),
  Country('ch', 'Svizzera'), Country('br', 'Brasile'), Country('mx', 'Messico'), Country('ar', 'Argentina'),
  Country('ca', 'Canada'), Country('in', 'India'), Country('ru', 'Russia'), Country('cn', 'Cina'), Country('jp', 'Giappone'),
];
