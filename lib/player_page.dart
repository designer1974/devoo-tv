import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'data.dart';
import 'models.dart';
import 'ui.dart';

Future<void> openPlayer(BuildContext context, List<Channel> list, int index, {required bool kids}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerPage(list: list, index: index, kids: kids),
    ));

/// Guarda un canale a schermo intero. Avanti/indietro passa al canale vicino
/// (sempre nello stesso elenco: dai bambini non si arriva ai canali del mondo).
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
  VideoPlayerController? _ctl;
  bool _failed = false;
  bool _controls = true;
  bool _fill = false; // schermo intero: il video riempie tutto lo schermo (senza bande nere)
  Timer? _hide;
  int _seq = 0;

  Channel get _c => widget.list[_i];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    WakelockPlus.enable().catchError((Object _) {});
    _open();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _ctl?.dispose();
    WakelockPlus.disable().catchError((Object _) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _open() async {
    final seq = ++_seq;
    final old = _ctl;
    setState(() {
      _ctl = null;
      _failed = false;
    });
    await old?.dispose();
    final c = _c;
    // prova gli indirizzi del canale uno dopo l'altro
    for (final u in c.urls) {
      if (seq != _seq || !mounted) return;
      final ctl = VideoPlayerController.networkUrl(
        Uri.parse(u),
        httpHeaders: c.headers,
        formatHint: u.toLowerCase().contains('.m3u8') ? VideoFormat.hls : null,
      );
      try {
        await ctl.initialize().timeout(const Duration(seconds: 20));
        if (seq != _seq || !mounted) {
          await ctl.dispose();
          return;
        }
        ctl.addListener(() {
          if (ctl.value.hasError && mounted && seq == _seq && !_failed) setState(() => _failed = true);
        });
        await ctl.play();
        setState(() => _ctl = ctl);
        _showControls();
        return;
      } catch (_) {
        await ctl.dispose();
      }
    }
    if (seq == _seq && mounted) setState(() => _failed = true);
  }

  void _go(int d) {
    final n = widget.list.length;
    if (n < 2) return;
    _i = (_i + d) % n;
    if (_i < 0) _i += n;
    _open();
    _showControls();
  }

  void _toggleFill() {
    setState(() => _fill = !_fill);
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
  Widget build(BuildContext context) {
    final ctl = _ctl;
    final acc = accentOf(widget.kids);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _controls ? setState(() => _controls = false) : _showControls(),
        onDoubleTap: _toggleFill, // doppio tocco: schermo intero / normale
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 300) _go(v < 0 ? 1 : -1);
        },
        child: Stack(
          children: [
            Center(
              child: ctl != null && ctl.value.isInitialized
                  ? (_fill
                      ? SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: ctl.value.size.width > 0 ? ctl.value.size.width : 1600,
                              height: ctl.value.size.height > 0 ? ctl.value.size.height : 900,
                              child: VideoPlayer(ctl),
                            ),
                          ),
                        )
                      : AspectRatio(
                          aspectRatio: ctl.value.aspectRatio > 0 ? ctl.value.aspectRatio : 16 / 9,
                          child: VideoPlayer(ctl),
                        ))
                  : _failed
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('📡', style: TextStyle(fontSize: 54)),
                            const SizedBox(height: 10),
                            Text(
                              _c.geoBlocked
                                  ? '«${_c.name}» si vede solo nel suo paese.'
                                  : '«${_c.name}» non trasmette adesso.',
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
                        )
                      : CircularProgressIndicator(color: acc),
            ),
            if (ctl != null && ctl.value.isInitialized && ctl.value.isBuffering)
              Center(child: CircularProgressIndicator(color: acc)),
            if (_controls || _failed) _overlay(acc),
          ],
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
        Widget round(IconData icon, VoidCallback onTap, {double size = 34}) => Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, color: Colors.white, size: size)),
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
                      round(_fill ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, _toggleFill, size: 30),
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
