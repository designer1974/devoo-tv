import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui.dart';

/// Numero della versione, messo da GitHub quando compila l'APK.
const appBuild = int.fromEnvironment('BUILD');
const _repo = 'designer1974/devoo-tv';
const appChannel = MethodChannel('tv/app');

class UpdateInfo {
  final int build;
  final String url;
  final int size;
  const UpdateInfo(this.build, this.url, this.size);
}

/// C'è una versione più nuova su GitHub?
Future<UpdateInfo?> findUpdate() async {
  if (appBuild <= 0) return null;
  final r = await http.get(Uri.https('api.github.com', '/repos/$_repo/releases', {'per_page': '10'}),
      headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'DevooTV'}).timeout(
      const Duration(seconds: 15));
  if (r.statusCode != 200) return null;
  final list = jsonDecode(r.body);
  if (list is! List) return null;
  var is64 = true;
  try {
    is64 = await appChannel.invokeMethod<bool>('is64') ?? true;
  } catch (_) {}
  final want = is64 ? 'DevooTV.apk' : 'DevooTV-telefoni-vecchi.apk';
  UpdateInfo? best;
  for (final rel in list) {
    if (rel is! Map) continue;
    final tag = '${rel['tag_name']}';
    if (!tag.startsWith('build-')) continue;
    final n = int.tryParse(tag.substring(6)) ?? 0;
    if (n <= appBuild || (best != null && n <= best.build)) continue;
    for (final a in (rel['assets'] as List? ?? const [])) {
      if (a is Map && a['name'] == want) {
        best = UpdateInfo(n, '${a['browser_download_url']}', (a['size'] as num?)?.toInt() ?? 0);
      }
    }
  }
  return best;
}

/// All'avvio: se c'è una versione nuova la propone (una volta per versione, se si sceglie «Più tardi»).
Future<void> checkForUpdate(BuildContext context) async {
  try {
    final info = await findUpdate();
    if (info == null || !context.mounted) return;
    final p = await SharedPreferences.getInstance();
    if ((p.getInt('update_skipped') ?? 0) >= info.build || !context.mounted) return;
    await showUpdateSheet(context, info);
  } catch (_) {
    // senza internet si riprova al prossimo avvio
  }
}

/// Dal menu: cerca subito e dice se è già aggiornata.
Future<void> checkForUpdateNow(BuildContext context) async {
  snack(context, 'Cerco aggiornamenti…');
  try {
    final info = await findUpdate();
    if (!context.mounted) return;
    if (info == null) {
      snack(context, 'Hai già l\'ultima versione ✔');
    } else {
      await showUpdateSheet(context, info);
    }
  } catch (_) {
    if (context.mounted) snack(context, 'Nessuna connessione. Riprova.');
  }
}

Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: navy2,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (_) => UpdateSheet(info: info),
    );

/// Scarica l'aggiornamento e lo installa sopra l'app (preferiti e registrazioni restano).
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.info});
  final UpdateInfo info;
  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

enum _St { ready, downloading, installing, error }

class _UpdateSheetState extends State<UpdateSheet> {
  _St _st = _St.ready;
  double _p = 0;
  int _got = 0;
  String? _msg;
  http.Client? _client;
  Timer? _watch;
  File? _file;

  @override
  void dispose() {
    _watch?.cancel();
    _client?.close();
    super.dispose();
  }

  String _mb(int b) => (b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _go() async {
    setState(() {
      _st = _St.downloading;
      _p = 0;
      _got = 0;
      _msg = null;
    });
    final client = _client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final f = _file = File('${dir.path}/DevooTV-${widget.info.build}.apk');
      // già scaricato prima: si installa subito
      if (widget.info.size > 0 && f.existsSync() && f.lengthSync() == widget.info.size) {
        await _install();
        return;
      }
      final res = await client.send(http.Request('GET', Uri.parse(widget.info.url))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength ?? widget.info.size;
      final sink = f.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        _got += chunk.length;
        if (mounted && total > 0) setState(() => _p = _got / total);
      }
      await sink.close();
      if (!mounted) return;
      await _install();
    } catch (_) {
      if (mounted) {
        setState(() {
          _st = _St.error;
          _msg = 'Download non riuscito. Controlla internet e riprova.';
        });
      }
    }
  }

  /// Apre la finestra «Installa» di Android.
  Future<void> _install() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _p = 1;
      _st = _St.installing;
      _msg = null;
    });
    try {
      final r = await appChannel.invokeMethod<String>('installApk', {'path': f.path});
      if (r != 'ok') throw Exception(r);
      _watchResult();
    } catch (_) {
      if (mounted) {
        setState(() {
          _st = _St.error;
          _msg = 'Installazione non avviata. Riprova.';
        });
      }
    }
  }

  /// Esito dell'installazione: se Android non l'ha fatta, lo dice e si può riprovare.
  void _watchResult() {
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 1), (t) async {
      Map? m;
      try {
        m = await appChannel.invokeMethod<Map>('installStatus');
      } catch (_) {}
      final st = (m?['status'] as num?)?.toInt() ?? -100;
      // -100 attesa, -1 finestra «Installa» aperta, 0 fatto (l'app si riavvia)
      if (st == -100 || st == -1 || st == 0 || !mounted) return;
      t.cancel();
      setState(() {
        _st = _St.error;
        _msg = switch (st) {
          3 => 'Installazione annullata. Tocca «Riprova» e poi «Installa».',
          2 => 'Il telefono ha bloccato l\'installazione. Permetti a Devoo TV di installare app e riprova.',
          4 || 5 || 7 => 'Questa versione non può sostituire quella installata.',
          6 => 'Spazio insufficiente sul telefono.',
          _ => 'Installazione non riuscita. Riprova.',
        };
      });
    });
  }

  Future<void> _later() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('update_skipped', widget.info.build);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_p * 100).clamp(0, 100).round();
    final btn = FilledButton.styleFrom(
      backgroundColor: yellow,
      foregroundColor: navy,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('🎉', style: TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Nuova versione!',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text('Devoo TV build ${widget.info.build} · ${_mb(widget.info.size)} MB',
                      style: const TextStyle(color: Colors.white60)),
                ]),
              ),
            ]),
            const SizedBox(height: 22),
            if (_st == _St.ready || _st == _St.error) ...[
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_msg!, style: const TextStyle(color: Color(0xFFFF8FA3), fontWeight: FontWeight.w700)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: btn,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_st == _St.error ? 'Riprova' : 'Aggiorna ora'),
                  onPressed: _go,
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _later,
                  child: const Text('Più tardi', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Text(_st == _St.installing ? 'Apro l\'installazione…' : 'Scarico l\'aggiornamento…',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  const Spacer(),
                  Text('$pct%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: yellow)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _st == _St.installing ? 1 : _p,
                  minHeight: 14,
                  color: yellow,
                  backgroundColor: card,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _st == _St.installing
                    ? 'Tocca «Installa» nella finestra di Android. Preferiti e PIN restano.'
                    : '${_mb(_got)} di ${_mb(widget.info.size)} MB',
                style: const TextStyle(fontSize: 13, color: Colors.white60),
              ),
              if (_st == _St.installing) ...[
                const SizedBox(height: 16),
                const Text('La finestra si è chiusa?', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: btn,
                    icon: const Icon(Icons.install_mobile),
                    label: const Text('Installa di nuovo'),
                    onPressed: _install,
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Chiudi', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
