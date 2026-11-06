import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'data.dart';
import 'models.dart';
import 'rec_pages.dart';
import 'recording.dart';
import 'ui.dart';

Future<void> openPlayer(BuildContext context, List<Channel> list, int index, {required bool kids}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerPage(list: list, index: index, kids: kids),
    ));

/// Guarda un canale a schermo intero. Avanti/indietro passa al canale vicino
/// (sempre nello stesso elenco: dai bambini non si arriva ai canali del mondo).
/// Lettore media_kit: legge anche le tracce di sottotitoli e le lingue audio del canale.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.list, required this.index, required this.kids});
  final List<Channel> list;
  final int index;
  final bool kids;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late int _i = widget.index;
  final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final _subs = <StreamSubscription<Object?>>[];

  bool _ready = false;
  bool _failed = false;
  bool _buffering = false;
  // per riguardare le registrazioni
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = true;
  double _rate = 1;
  bool _controls = true;

  // Come si vede il video:
  // 0 normale (bande nere), 1 schermo intero (allargato, non taglia logo e sottotitoli), 2 zoom (taglia i bordi)
  int _fit = 0;
  String? _flash; // scritta grande al centro per un attimo
  Timer? _flashHide;
  static const _fitNames = ['Normale', 'Schermo intero', 'Zoom'];
  Timer? _hide;
  int _seq = 0;

  Channel get _c => widget.list[_i];
  bool get _live => _c.url.startsWith('http'); // le registrazioni (file) non si riregistrano
  Orientation? _lastO;
  final _listScroll = ScrollController();

  /// Schermo intero: gira in orizzontale.
  void _landscape() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  /// Torna in verticale.
  void _portrait() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _onOrientation(Orientation o) {
    if (o == _lastO) return;
    _lastO = o;
    SystemChrome.setEnabledSystemUIMode(o == Orientation.landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (o == Orientation.portrait) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_listScroll.hasClients) {
          _listScroll.jumpTo((_i * 72.0).clamp(0, _listScroll.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values); // verticale e orizzontale
    _subs
      ..add(_player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }))
      ..add(_player.stream.position.listen((p) {
        if (mounted && !_live) setState(() => _pos = p);
      }))
      ..add(_player.stream.duration.listen((d) {
        if (mounted) setState(() => _dur = d);
      }))
      ..add(_player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
      }));
    _open();
  }

  @override
  void dispose() {
    _seq++;
    _hide?.cancel();
    _flashHide?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _listScroll.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  /// Prova un indirizzo: va bene appena arriva il video, no se c'è un errore o dopo 20 secondi.
  Future<bool> _try(String url, Map<String, String> headers, int seq) async {
    final done = Completer<bool>();
    final subs = <StreamSubscription<Object?>>[
      _player.stream.width.listen((w) {
        if (w != null && w > 0 && !done.isCompleted) done.complete(true);
      }),
      _player.stream.error.listen((_) {
        if (!done.isCompleted) done.complete(false);
      }),
    ];
    try {
      await _player.open(Media(url, httpHeaders: headers), play: true);
      return await done.future.timeout(const Duration(seconds: 20), onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      for (final s in subs) {
        s.cancel();
      }
    }
  }

  Future<void> _open() async {
    final seq = ++_seq;
    setState(() {
      _ready = false;
      _failed = false;
    });
    final c = _c;
    // prova gli indirizzi del canale uno dopo l'altro
    for (final u in c.urls) {
      if (seq != _seq || !mounted) return;
      if (await _try(u, c.headers, seq)) {
        if (seq != _seq || !mounted) return;
        setState(() => _ready = true);
        _showControls();
        return;
      }
    }
    if (seq == _seq && mounted) {
      await _player.stop();
      setState(() => _failed = true);
    }
  }

  void _setRate(double r) {
    _player.setRate(r);
    setState(() => _rate = r);
    _say('Velocità ×${r == r.roundToDouble() ? r.toInt() : r}');
  }

  void _go(int d) {
    final n = widget.list.length;
    if (n < 2) return;
    _i = (_i + d) % n;
    if (_i < 0) _i += n;
    _open();
    _showControls();
  }

  void _say(String text) {
    _flashHide?.cancel();
    setState(() => _flash = text);
    _flashHide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _toggleFill() {
    setState(() => _fit = (_fit + 1) % 3);
    _say(_fitNames[_fit]);
    _showControls();
  }

  void _showControls() {
    _hide?.cancel();
    setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && !_failed) setState(() => _controls = false);
    });
  }

  @override
  Widget build(BuildContext context) => OrientationBuilder(builder: (context, o) {
        _onOrientation(o);
        return o == Orientation.landscape ? _landscapeView(context) : _portraitView(context);
      });

  Widget _landscapeView(BuildContext context) {
    final acc = accentOf(widget.kids);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _controls ? setState(() => _controls = false) : _showControls(),
        onDoubleTap: _toggleFill, // doppio tocco: normale → schermo intero → zoom
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 300) _go(v < 0 ? 1 : -1);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Video(
                controller: _video,
                controls: NoVideoControls,
                fill: Colors.black,
                fit: const [BoxFit.contain, BoxFit.fill, BoxFit.cover][_fit],
              ),
            ),
            if (_failed)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📡', style: TextStyle(fontSize: 54)),
                    const SizedBox(height: 10),
                    Text(
                      _c.geoBlocked ? '«${_c.name}» si vede solo nel suo paese.' : '«${_c.name}» non trasmette adesso.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: acc, foregroundColor: navy),
                      onPressed: () => _go(1),
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Prossimo canale'),
                    ),
                  ],
                ),
              )
            else if (!_ready || _buffering)
              Center(child: CircularProgressIndicator(color: acc)),
            if (_controls || _failed) _overlay(acc),
            if (_flash != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(24)),
                  child: Text(_flash!, style: TextStyle(color: acc, fontSize: 20, fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Verticale: video in alto, sotto i pulsanti e l'elenco dei canali.
  Widget _portraitView(BuildContext context) {
    final acc = accentOf(widget.kids);
    final c = _c;
    Widget action(IconData icon, String label, VoidCallback tap, {Color? color}) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: color ?? Colors.white, size: 28),
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Favorites.i,
          builder: (context, _) {
            final fav = Favorites.i.isFav(c, widget.kids);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                  child: Row(children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    ChannelLogo(c, size: 38, radius: 10),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${c.flag} ${c.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    IconButton(
                      onPressed: () => Favorites.i.toggle(c, widget.kids),
                      icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                          color: fav ? const Color(0xFFFF4D6D) : Colors.white),
                    ),
                  ]),
                ),
                GestureDetector(
                  onDoubleTap: _landscape,
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v.abs() > 300) _go(v < 0 ? 1 : -1);
                  },
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: Stack(children: [
                        Positioned.fill(
                          child: Video(controller: _video, controls: NoVideoControls, fill: Colors.black, fit: BoxFit.contain),
                        ),
                        if (_failed)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(c.geoBlocked ? '📡 Si vede solo nel suo paese' : '📡 Non trasmette adesso',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: acc, foregroundColor: navy),
                                  onPressed: () => _go(1),
                                  icon: const Icon(Icons.skip_next_rounded),
                                  label: const Text('Prossimo canale'),
                                ),
                              ]),
                            ),
                          )
                        else if (!_ready || _buffering)
                          Center(child: CircularProgressIndicator(color: acc)),
                      ]),
                    ),
                  ),
                ),
                if (_live) const _RecStatus(),
                if (!_live) _FileControls(state: this, accent: acc),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                  child: Row(children: [
                    if (widget.list.length > 1) action(Icons.skip_previous_rounded, 'Prima', () => _go(-1)),
                    if (_live)
                      action(Icons.fiber_manual_record_rounded, 'Registra',
                          () => Schedules.i.recording ? Schedules.i.stop() : recordNow(context, c, kids: widget.kids),
                          color: recRed),
                    if (_live) action(Icons.alarm_add_rounded, 'Programma', () => openScheduleEditor(context, c, kids: widget.kids)),
                    action(Icons.fullscreen_rounded, 'Intero', _landscape, color: acc),
                    if (widget.list.length > 1) action(Icons.skip_next_rounded, 'Dopo', () => _go(1)),
                  ]),
                ),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: _listScroll,
                    itemCount: widget.list.length,
                    itemExtent: 72,
                    itemBuilder: (_, i) {
                      final x = widget.list[i];
                      final on = i == _i;
                      return ListTile(
                        selected: on,
                        selectedTileColor: acc.withValues(alpha: 0.14),
                        leading: ChannelLogo(x, size: 46, radius: 12),
                        title: Text(x.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: on ? acc : Colors.white, fontWeight: FontWeight.w800)),
                        subtitle: x.countryCode.isEmpty ? null : Text(x.flag),
                        trailing: on ? Icon(Icons.equalizer_rounded, color: acc) : null,
                        onTap: () {
                          if (i == _i) return;
                          setState(() => _i = i);
                          _open();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _overlay(Color acc) {
    final c = _c;
    return ListenableBuilder(
      listenable: Favorites.i,
      builder: (context, _) {
        final fav = Favorites.i.isFav(c, widget.kids);
        Widget round(IconData icon, VoidCallback onTap, {double size = 34, Color color = Colors.white}) => Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, color: color, size: size)),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    children: [
                      round(Icons.arrow_back_rounded, () => Navigator.pop(context), size: 28),
                      const SizedBox(width: 12),
                      ChannelLogo(c, size: 44, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('${c.flag} ${c.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              shadows: [Shadow(blurRadius: 8)],
                            )),
                      ),
                      if (_live) ...[
                        _RecButton(onTap: () => recordNow(context, c, kids: widget.kids)),
                        const SizedBox(width: 10),
                      ],
                      round(const [Icons.fullscreen_rounded, Icons.zoom_in_rounded, Icons.fullscreen_exit_rounded][_fit],
                          _toggleFill,
                          size: 30),
                      const SizedBox(width: 10),
                      round(fav ? Icons.favorite : Icons.favorite_border, () => Favorites.i.toggle(c, widget.kids),
                          size: 28),
                      const SizedBox(width: 10),
                      round(Icons.stay_current_portrait_rounded, _portrait, size: 28),
                    ],
                  ),
                ),
                if (widget.list.length > 1)
                  Align(
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        round(Icons.skip_previous_rounded, () => _go(-1), size: 40),
                        round(Icons.skip_next_rounded, () => _go(1), size: 40),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_live) const _RecStatus(),
                    if (!_live)
                      Container(
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                        child: _FileControls(state: this, accent: acc),
                      ),
                    if (_live)
                      Text('${_i + 1} / ${widget.list.length}',
                          style: TextStyle(color: acc, fontWeight: FontWeight.w800, shadows: const [Shadow(blurRadius: 8)])),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


/// Pulsante 🔴: rosso pieno mentre si registra.
class _RecButton extends StatelessWidget {
  const _RecButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Schedules.i,
        builder: (context, _) {
          final on = Schedules.i.recording;
          return Material(
            color: on ? recRed : Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: on ? Schedules.i.stop : onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(on ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                    color: on ? Colors.white : recRed, size: 28),
              ),
            ),
          );
        },
      );
}


/// Timer della registrazione in corso: ore:minuti:secondi, MB e «Ferma».
class _RecStatus extends StatelessWidget {
  const _RecStatus();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Schedules.i,
        builder: (context, _) {
          final s = Schedules.i;
          if (!s.recording) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(color: recRed, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fiber_manual_record_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              const Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(width: 10),
              Text(fmtDurFull(s.elapsed),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${fmtSize(s.runningBytes)}${s.runningEnd != null ? ' · fino alle ${hhmm(s.runningEnd!)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: s.stop,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: recRed,
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Ferma', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ]),
          );
        },
      );
}

/// Comandi per riguardare una registrazione: tempo, pausa, stop, ±10 s, velocità.
class _FileControls extends StatelessWidget {
  const _FileControls({required this.state, required this.accent});
  final _PlayerPageState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final st = state;
    final p = st._player;
    final total = st._dur.inMilliseconds;
    final pos = st._pos.inMilliseconds.clamp(0, total > 0 ? total : 0);
    Widget btn(IconData i, VoidCallback tap, {double size = 30}) => IconButton(
          onPressed: tap,
          icon: Icon(i, color: Colors.white, size: size),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(fmtDurFull(Duration(milliseconds: pos)),
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          Expanded(
            child: Slider(
              value: pos.toDouble(),
              max: total > 0 ? total.toDouble() : 1,
              activeColor: accent,
              inactiveColor: Colors.white24,
              onChanged: total > 0 ? (v) => p.seek(Duration(milliseconds: v.round())) : null,
            ),
          ),
          Text(fmtDurFull(st._dur), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (st.widget.list.length > 1) btn(Icons.skip_previous_rounded, () => st._go(-1)),
          btn(Icons.replay_10_rounded, () => p.seek(st._pos - const Duration(seconds: 10))),
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: p.playOrPause,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(st._playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: navy, size: 34),
              ),
            ),
          ),
          btn(Icons.forward_10_rounded, () => p.seek(st._pos + const Duration(seconds: 10))),
          btn(Icons.stop_rounded, () async {
            await p.pause();
            await p.seek(Duration.zero);
          }),
          if (st.widget.list.length > 1) btn(Icons.skip_next_rounded, () => st._go(1)),
        ]),
        Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
          for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            ChoiceChip(
              label: Text('×${r == r.roundToDouble() ? r.toInt() : r}'),
              selected: st._rate == r,
              showCheckmark: false,
              selectedColor: accent,
              backgroundColor: card,
              side: BorderSide.none,
              labelStyle: TextStyle(
                  color: st._rate == r ? navy : Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => st._setRate(r),
            ),
        ]),
      ]),
    );
  }
}
