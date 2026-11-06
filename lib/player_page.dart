import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'data.dart';
import 'models.dart';
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
  bool _controls = true;
  Tracks _tracks = Tracks();
  Track _track = Track();

  // Come si vede il video:
  // 0 normale (bande nere), 1 schermo intero (allargato, non taglia logo e sottotitoli), 2 zoom (taglia i bordi)
  int _fit = 0;
  String? _flash; // scritta grande al centro per un attimo
  Timer? _flashHide;
  static const _fitNames = ['Normale', 'Schermo intero', 'Zoom'];
  Timer? _hide;
  int _seq = 0;

  Channel get _c => widget.list[_i];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _subs
      ..add(_player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }))
      ..add(_player.stream.tracks.listen((t) {
        if (mounted) setState(() => _tracks = t);
      }))
      ..add(_player.stream.track.listen((t) {
        if (mounted) setState(() => _track = t);
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

  // tracce vere (senza le voci "auto" e "no" che aggiunge il lettore)
  List<SubtitleTrack> get _subTracks => _tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
  List<AudioTrack> get _audioTracks => _tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
  bool get _subsOn => _track.subtitle.id != 'no' && _subTracks.any((t) => t.id == _track.subtitle.id);

  String _name(String? title, String? lang, int n) {
    final parts = [if (title != null && title.isNotEmpty) title, if (lang != null && lang.isNotEmpty) lang.toUpperCase()];
    return parts.isEmpty ? 'Traccia $n' : parts.join(' · ');
  }

  /// Pulsante CC: accende/spegne i sottotitoli e sceglie la lingua (anche dell'audio).
  Future<void> _subtitles() async {
    _hide?.cancel();
    final subs = _subTracks, audio = _audioTracks;
    if (subs.isEmpty && audio.length < 2) {
      _say('Questo canale non ha sottotitoli');
      _showControls();
      return;
    }
    final acc = accentOf(widget.kids);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: navy2,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Text('💬 Sottotitoli', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              if (subs.isEmpty)
                const ListTile(
                  title: Text('Questo canale non ha sottotitoli', style: TextStyle(color: Colors.white60)),
                )
              else ...[
                _choice(c, 'Spenti', !_subsOn, acc, () => _player.setSubtitleTrack(SubtitleTrack.no())),
                for (var n = 0; n < subs.length; n++)
                  _choice(c, _name(subs[n].title, subs[n].language, n + 1), _subsOn && _track.subtitle.id == subs[n].id,
                      acc, () => _player.setSubtitleTrack(subs[n])),
              ],
              if (audio.length > 1) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 14, 12, 6),
                  child: Text('🔊 Lingua audio',
                      style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                ),
                for (var n = 0; n < audio.length; n++)
                  _choice(c, _name(audio[n].title, audio[n].language, n + 1), _track.audio.id == audio[n].id, acc,
                      () => _player.setAudioTrack(audio[n])),
              ],
            ],
          ),
        ),
      ),
    );
    _showControls();
  }

  Widget _choice(BuildContext c, String label, bool on, Color acc, Future<void> Function() pick) => ListTile(
        leading: Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? acc : Colors.white54),
        title: Text(label,
            style: TextStyle(color: Colors.white, fontWeight: on ? FontWeight.w900 : FontWeight.w600, fontSize: 16)),
        onTap: () {
          pick();
          Navigator.pop(c);
        },
      );

  @override
  Widget build(BuildContext context) {
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
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.3,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    backgroundColor: Color(0xAA000000),
                  ),
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 28),
                ),
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

  Widget _overlay(Color acc) {
    final c = _c;
    final hasSubs = _subTracks.isNotEmpty || _audioTracks.length > 1;
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
                      // sottotitoli: acceso = colorato, spento = bianco, non disponibili = grigio
                      round(_subsOn ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined, _subtitles,
                          size: 30, color: _subsOn ? acc : (hasSubs ? Colors.white : Colors.white38)),
                      const SizedBox(width: 10),
                      round(const [Icons.fullscreen_rounded, Icons.zoom_in_rounded, Icons.fullscreen_exit_rounded][_fit],
                          _toggleFill,
                          size: 30),
                      const SizedBox(width: 10),
                      round(fav ? Icons.favorite : Icons.favorite_border, () => Favorites.i.toggle(c, widget.kids),
                          size: 28),
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
                  child: Text('${_i + 1} / ${widget.list.length}',
                      style: TextStyle(color: acc, fontWeight: FontWeight.w800, shadows: const [Shadow(blurRadius: 8)])),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
