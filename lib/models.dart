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
  final List<String> alts; // altri indirizzi dello stesso canale, se il primo non va

  const Channel({
    required this.id,
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '',
    this.referrer = '',
    this.userAgent = '',
    this.geoBlocked = false,
    this.alts = const [],
  });

  /// Chiave unica: lo stesso canale con più indirizzi è un canale solo.
  String get key => dedupeKey(id, name);

  List<String> get urls => [url, ...alts];

  /// Stesso canale, con [u] come primo indirizzo (quello che funziona).
  Channel preferring(String u) => u == url
      ? this
      : Channel(
          id: id,
          name: name,
          url: u,
          logo: logo,
          group: group,
          referrer: referrer,
          userAgent: userAgent,
          geoBlocked: geoBlocked,
          alts: [url, ...alts.where((a) => a != u)],
        );

  Channel withAlt(String u) => urls.contains(u)
      ? this
      : Channel(
          id: id,
          name: name,
          url: url,
          logo: logo,
          group: group,
          referrer: referrer,
          userAgent: userAgent,
          geoBlocked: geoBlocked,
          alts: [...alts, u],
        );

  /// Paese dal tvg-id: "CartoonNetwork.us@SD" → "US".
  String get countryCode {
    final m = RegExp(r'\.([a-z]{2})(@|$)').firstMatch(id.toLowerCase());
    return m == null ? '' : m.group(1)!.toUpperCase();
  }

  String get flag => flagEmoji(countryCode);
  bool get hasLogo => logo.startsWith('http');

  /// Canali con più rischio di essere trasmessi senza diritti: film, serie, sport,
  /// classici e i canali «24/7» dedicati a una sola serie o a un solo cartone.
  bool get isRisky {
    final g = group.toLowerCase();
    if (const ['movies', 'series', 'sports', 'classic'].any(g.contains)) return true;
    final n = name.toLowerCase();
    return n.contains('24/7') || n.contains('24-7') || n.contains('24x7');
  }

  /// Canale per bambini: nel Mondo non compare (sta nella parte Kids).
  bool get isKids => group.toLowerCase().split(';').any((g) => g.trim() == 'kids');

  bool get isAdult {
    final t = '$name $group'.toLowerCase();
    return t.contains('xxx') || t.contains('adult') || t.contains('erotic') || t.contains('porn');
  }

  Map<String, String> get headers => {
        if (referrer.isNotEmpty) 'Referer': referrer,
        if (userAgent.isNotEmpty) 'User-Agent': userAgent,
      };

  List<String> toCompact() =>
      [id, name, url, logo, group, referrer, userAgent, geoBlocked ? '1' : '', alts.join('\n')];

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
      alts: o.length > 8 && '${o[8]}'.isNotEmpty ? '${o[8]}'.split('\n') : const [],
    );
  }
}

/// Chiave per riconoscere i doppioni: il tvg-id senza la parte dopo @
/// ("2M.ma@SD" e "2M.ma@HD" sono lo stesso canale), altrimenti il nome.
String dedupeKey(String id, String name) {
  final base = id.split('@').first.trim().toLowerCase();
  if (base.isNotEmpty) return base;
  return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u00C0-\uFFFF]+'), '');
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

/// Legge una playlist M3U. Niente canali per adulti; i doppioni diventano
/// un canale solo con più indirizzi (si prova il secondo se il primo non va).
List<Channel> parseM3u(String text) {
  final out = <Channel>[];
  final index = <String, int>{};
  final seenUrl = <String>{};
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
      if (c.url.startsWith('http') && c.name.isNotEmpty && !c.isAdult && seenUrl.add(c.url)) {
        final k = c.key;
        final at = index[k];
        if (at == null) {
          index[k] = out.length;
          out.add(c);
        } else {
          out[at] = out[at].withAlt(c.url);
        }
      }
      info = null;
      referrer = '';
      ua = '';
    }
  }
  return mergeSameLogo(out);
}

/// Stesso logo = stesso canale (es. «2M», «2M Monde», «2M Monde +1»):
/// resta uno solo, con il nome più corto e gli altri indirizzi come riserva.
List<Channel> mergeSameLogo(List<Channel> list) {
  final out = <Channel>[];
  final byLogo = <String, int>{};
  for (final c in list) {
    final logo = c.logo.trim().toLowerCase();
    final at = logo.isEmpty ? null : byLogo[logo];
    if (at == null) {
      if (logo.isNotEmpty) byLogo[logo] = out.length;
      out.add(c);
      continue;
    }
    var keep = out[at];
    if (c.name.length < keep.name.length) {
      // il nome più corto è quello "principale": i suoi indirizzi vanno prima
      var merged = c;
      for (final u in keep.urls) {
        merged = merged.withAlt(u);
      }
      keep = merged;
    } else {
      for (final u in c.urls) {
        keep = keep.withAlt(u);
      }
    }
    out[at] = keep;
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

/// Le categorie del mondo (iptv-org), divise in gruppi. Niente "xxx" e niente "kids"
/// (i canali per bambini stanno nella parte Kids).
const worldCategoryGroups = <(String, List<(String, String, String)>)>[
  ('📰 Informazione', [
    ('news', '📰', 'Notizie'),
    ('business', '💼', 'Economia'),
    ('weather', '⛅', 'Meteo'),
    ('legislative', '🏛', 'Parlamento'),
  ]),
  ('🎬 Film e serie', [
    ('movies', '🎬', 'Film'),
    ('series', '🎞️', 'Serie'),
    ('classic', '📼', 'Classici'),
    ('comedy', '😂', 'Comici'),
    ('animation', '🎨', 'Animazione'),
  ]),
  ('📺 Intrattenimento', [
    ('general', '📺', 'Generali'),
    ('entertainment', '🎭', 'Intrattenimento'),
    ('family', '👨‍👩‍👧', 'Famiglia'),
    ('lifestyle', '💄', 'Stile'),
    ('shop', '🛍️', 'Shopping'),
  ]),
  ('⚽ Sport e motori', [
    ('sports', '⚽', 'Sport'),
    ('auto', '🚗', 'Motori'),
    ('outdoor', '🏕️', 'Natura e avventura'),
  ]),
  ('🎵 Musica e relax', [
    ('music', '🎵', 'Musica'),
    ('relax', '🌊', 'Relax'),
  ]),
  ('🎓 Cultura e scienza', [
    ('documentary', '🦁', 'Documentari'),
    ('education', '🎓', 'Educazione'),
    ('science', '🔬', 'Scienza'),
    ('culture', '🏛️', 'Cultura'),
    ('travel', '✈️', 'Viaggi'),
    ('cooking', '🍝', 'Cucina'),
  ]),
  ('🕌 Religione', [
    ('religious', '🕌', 'Religione'),
  ]),
];

/// Tutte le categorie in un elenco solo.
final worldCategories = [for (final g in worldCategoryGroups) ...g.$2];

/// Paesi di riserva se l'elenco online non si carica.
const fallbackCountries = <Country>[
  Country('it', 'Italia'), Country('ma', 'Marocco'), Country('fr', 'Francia'), Country('es', 'Spagna'),
  Country('gb', 'Regno Unito'), Country('us', 'Stati Uniti'), Country('de', 'Germania'), Country('pt', 'Portogallo'),
  Country('dz', 'Algeria'), Country('tn', 'Tunisia'), Country('eg', 'Egitto'), Country('sa', 'Arabia Saudita'),
  Country('ae', 'Emirati Arabi'), Country('tr', 'Turchia'), Country('nl', 'Paesi Bassi'), Country('be', 'Belgio'),
  Country('ch', 'Svizzera'), Country('br', 'Brasile'), Country('mx', 'Messico'), Country('ar', 'Argentina'),
  Country('ca', 'Canada'), Country('in', 'India'), Country('ru', 'Russia'), Country('cn', 'Cina'), Country('jp', 'Giappone'),
];

/// Righe del file della lista nera: un tvg-id, un nome o un pezzo di indirizzo per riga.
/// Le righe che iniziano con # sono commenti.
Set<String> parseBlocklist(String text) => {
      for (final l in text.split(RegExp(r'\r?\n')))
        if (l.trim().isNotEmpty && !l.trim().startsWith('#')) l.trim().toLowerCase(),
    };

bool isBlocked(Channel c, Set<String> block) {
  final id = c.id.toLowerCase(), base = id.split('@').first, name = c.name.toLowerCase();
  for (final b in block) {
    if (b == id || b == base || b == name) return true;
    if (b.startsWith('http') && c.urls.any((u) => u.toLowerCase().startsWith(b))) return true;
  }
  return false;
}
