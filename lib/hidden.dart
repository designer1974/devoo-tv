import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Paesi e canali che l'utente ha nascosto perché non gli servono.
/// Si rimettono dalla pagina «Nascosti».
class Hidden extends ChangeNotifier {
  Hidden._();
  static final i = Hidden._();

  SharedPreferences? _p;
  Set<String> countries = {}; // codici in maiuscolo, es. "US"
  Map<String, String> channels = {}; // chiave del canale -> nome (per mostrarlo nell'elenco)

  Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
      countries = (_p!.getStringList('hidden_countries') ?? const []).toSet();
      final m = jsonDecode(_p!.getString('hidden_channels') ?? '{}');
      if (m is Map) channels = {for (final e in m.entries) '${e.key}': '${e.value}'};
    } catch (_) {}
  }

  void _save() {
    _p?.setStringList('hidden_countries', countries.toList()..sort());
    _p?.setString('hidden_channels', jsonEncode(channels));
    notifyListeners();
  }

  bool country(String code) => countries.contains(code.toUpperCase());
  bool channel(Channel c) => channels.containsKey(c.key);

  void hideCountry(String code) {
    countries.add(code.toUpperCase());
    _save();
  }

  void showCountry(String code) {
    countries.remove(code.toUpperCase());
    _save();
  }

  void hideChannel(Channel c) {
    channels[c.key] = c.name;
    _save();
  }

  void showChannelKey(String key) {
    channels.remove(key);
    _save();
  }

  /// Toglie i canali nascosti (e quelli di paesi nascosti, tranne se [keepCountries]).
  List<Channel> filter(List<Channel> l, {bool keepCountries = false}) => l
      .where((c) => !channel(c) && (keepCountries || c.countryCode.isEmpty || !country(c.countryCode)))
      .toList();
}
