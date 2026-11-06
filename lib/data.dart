import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Canali da iptv-org (elenco gratuito e aperto di TV che trasmettono pubblicamente).
/// Ogni elenco si salva sul telefono e si riscarica dopo 1 giorno.
class TvData {
  TvData._();
  static final i = TvData._();

  static const _base = 'https://iptv-org.github.io/iptv';
  static const kidsUrl = '$_base/categories/kids.m3u';
  static const allUrl = '$_base/index.m3u'; // tutti i canali, per la ricerca
  static String countryUrl(String code) => '$_base/countries/${code.toLowerCase()}.m3u';
  static String categoryUrl(String id) => '$_base/categories/$id.m3u';

  final _mem = <String, List<Channel>>{};

  Future<File> _file(String key) async {
    final dir = await getApplicationSupportDirectory();
    final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return File('${dir.path}/tv2_$safe.json'); // v2: doppioni uniti
  }

  /// Canali di una playlist. [fresh]: riscarica comunque.
  Future<List<Channel>> channels(String url, {bool fresh = false}) async {
    if (!fresh && _mem[url] != null) return _mem[url]!;
    final f = await _file(url);
    List<Channel>? cached;
    try {
      if (await f.exists()) {
        final c = await compute(_decode, await f.readAsString());
        cached = c;
        final young = DateTime.now().difference(await f.lastModified()) < const Duration(days: 1);
        if (young && !fresh && c.isNotEmpty) return _mem[url] = c;
      }
    } catch (_) {}
    try {
      final r = await http.get(Uri.parse(url), headers: {'User-Agent': 'DevooTV/1.0'}).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final list = await compute(parseM3u, utf8.decode(r.bodyBytes, allowMalformed: true));
      try {
        await f.writeAsString(await compute(_encode, list), flush: true);
      } catch (_) {}
      return _mem[url] = list;
    } catch (e) {
      final c = cached;
      if (c != null && c.isNotEmpty) return _mem[url] = c; // senza internet: l'ultimo elenco
      rethrow;
    }
  }

  List<Country>? _countries;

  /// Elenco dei paesi con i nomi in italiano quando possibile.
  Future<List<Country>> countries() async {
    if (_countries != null) return _countries!;
    try {
      final r = await http
          .get(Uri.parse('https://iptv-org.github.io/api/countries.json'), headers: {'User-Agent': 'DevooTV/1.0'})
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      if (data is List) {
        final it = {for (final c in fallbackCountries) c.code: c.name};
        final list = <Country>[
          for (final c in data)
            if (c is Map && c['code'] is String)
              Country((c['code'] as String).toLowerCase(), it[(c['code'] as String).toLowerCase()] ?? '${c['name']}'),
        ];
        if (list.isNotEmpty) {
          // prima i paesi più usati, poi gli altri in ordine alfabetico
          final top = [for (final c in fallbackCountries.take(6)) c.code];
          list.sort((a, b) {
            final ia = top.indexOf(a.code), ib = top.indexOf(b.code);
            if (ia >= 0 || ib >= 0) return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
            return a.name.compareTo(b.name);
          });
          return _countries = list;
        }
      }
    } catch (_) {}
    return fallbackCountries;
  }
}

List<Channel> _decode(String text) {
  final data = jsonDecode(text);
  if (data is! List) return const [];
  return data.map(Channel.fromCompact).whereType<Channel>().toList();
}

String _encode(List<Channel> list) => jsonEncode(list.map((c) => c.toCompact()).toList());

/// Preferiti: uno per i bambini, uno per il mondo.
class Favorites extends ChangeNotifier {
  Favorites._();
  static final i = Favorites._();

  SharedPreferences? _p;
  List<Channel> kids = [];
  List<Channel> world = [];

  Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
      kids = _read('fav_kids');
      world = _read('fav_world');
    } catch (_) {}
  }

  List<Channel> _read(String k) {
    try {
      final d = jsonDecode(_p?.getString(k) ?? '[]');
      return d is List ? d.map(Channel.fromCompact).whereType<Channel>().toList() : [];
    } catch (_) {
      return [];
    }
  }

  List<Channel> of(bool kidsMode) => kidsMode ? kids : world;

  bool isFav(Channel c, bool kidsMode) => of(kidsMode).any((x) => x.key == c.key);

  void toggle(Channel c, bool kidsMode) {
    final l = of(kidsMode);
    if (isFav(c, kidsMode)) {
      l.removeWhere((x) => x.key == c.key);
    } else {
      l.insert(0, c);
    }
    _p?.setString(kidsMode ? 'fav_kids' : 'fav_world', jsonEncode(l.map((x) => x.toCompact()).toList()));
    notifyListeners();
  }
}
