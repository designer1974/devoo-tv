import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Controlla dal telefono quali canali trasmettono davvero adesso.
/// (Dal telefono, così anche i canali visibili solo in certi paesi vengono provati
/// da dove sei tu.) I risultati si ricordano per qualche ora.
class Probe {
  Probe._();
  static final i = Probe._();

  static const _key = 'probe_v1';
  static const _okFor = Duration(hours: 6);
  static const _badFor = Duration(hours: 2);

  final _client = http.Client();
  Map<String, List<int>>? _cache; // url -> [ok 1/0, quando]
  Timer? _saveLater;

  Future<Map<String, List<int>>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final p = await SharedPreferences.getInstance();
      final d = jsonDecode(p.getString(_key) ?? '{}');
      if (d is Map) {
        return _cache = {
          for (final e in d.entries)
            if (e.value is List && (e.value as List).length == 2)
              '${e.key}': [((e.value as List)[0] as num).toInt(), ((e.value as List)[1] as num).toInt()],
        };
      }
    } catch (_) {}
    return _cache = {};
  }

  void _save() {
    _saveLater?.cancel();
    _saveLater = Timer(const Duration(seconds: 2), () async {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final c = _cache ?? {};
        c.removeWhere((_, v) => now - v[1] > _okFor.inMilliseconds); // via i vecchi
        final p = await SharedPreferences.getInstance();
        await p.setString(_key, jsonEncode(c));
      } catch (_) {}
    });
  }

  /// Risultato già noto e ancora valido? null = da provare.
  bool? known(String url) {
    final v = _cache?[url];
    if (v == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - v[1];
    if (v[0] == 1 && age < _okFor.inMilliseconds) return true;
    if (v[0] == 0 && age < _badFor.inMilliseconds) return false;
    return null;
  }

  /// Prova un indirizzo: deve rispondere e mandare davvero del video.
  Future<bool> _try(String url, Map<String, String> headers) async {
    final k = known(url);
    if (k != null) return k;
    var ok = false;
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll({'User-Agent': 'Mozilla/5.0 (Linux; Android 13) DevooTV', ...headers});
      final res = await _client.send(req).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 400) {
        final first = <int>[];
        await for (final chunk in res.stream.timeout(const Duration(seconds: 6))) {
          first.addAll(chunk);
          if (first.length >= 512) break;
        }
        final head = String.fromCharCodes(first.take(512)).trimLeft();
        final isPlaylist = url.toLowerCase().contains('.m3u8') || head.startsWith('#EXTM3U');
        ok = isPlaylist ? head.startsWith('#EXTM3U') : first.isNotEmpty;
        if (ok && isPlaylist && head.contains('#EXT-X-ENDLIST') && !head.contains('#EXT-X-STREAM-INF')) {
          ok = false; // video registrato finito, non diretta
        }
      }
    } catch (_) {
      ok = false;
    }
    (_cache ??= {})[url] = [ok ? 1 : 0, DateTime.now().millisecondsSinceEpoch];
    _save();
    return ok;
  }

  /// Il canale con l'indirizzo che funziona per primo, o null se nessuno funziona.
  Future<Channel?> check(Channel c) async {
    await _load();
    for (final u in c.urls) {
      if (await _try(u, c.headers)) return c.preferring(u);
    }
    return null;
  }

  /// Controlla un elenco, 10 canali alla volta. [onUpdate] riceve i canali buoni
  /// trovati finora (nell'ordine dell'elenco) e quanti sono stati controllati.
  Future<List<Channel>> filter(List<Channel> list, void Function(List<Channel> good, int done) onUpdate,
      {bool Function()? cancelled}) async {
    await _load();
    final result = List<Channel?>.filled(list.length, null);
    var next = 0, done = 0;
    List<Channel> good() => result.whereType<Channel>().toList();
    Future<void> worker() async {
      while (next < list.length) {
        if (cancelled?.call() ?? false) return;
        final i = next++;
        result[i] = await check(list[i]);
        done++;
        onUpdate(good(), done);
      }
    }

    await Future.wait([for (var w = 0; w < 10; w++) worker()]);
    return good();
  }
}
