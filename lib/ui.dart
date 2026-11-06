import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';
import 'player_page.dart';

/// Colori di devoo.it: blu notte, giallo per i bambini, azzurro per il mondo.
const navy = Color(0xFF060A16);
const navy2 = Color(0xFF0E1530);
const card = Color(0xFF151E40);
const yellow = Color(0xFFFFCC00);
const yellowSoft = Color(0xFFFFE680);
const sky = Color(0xFF4FC3F7);

Color accentOf(bool kids) => kids ? yellow : sky;

void snack(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)));

int funColor(String s) {
  const colors = [0xFFFFCC00, 0xFFFF6B6B, 0xFF4ECDC4, 0xFF7C6CFF, 0xFFFF9F43, 0xFF2ED573, 0xFFFF6FB5];
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  return colors[h % colors.length];
}

/// Logo del canale su fondo bianco, o l'iniziale colorata se manca.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo(this.c, {super.key, this.size = 56, this.radius = 16});
  final Channel c;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Color(funColor(c.name)), borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: Text(
        c.name.characters.isEmpty ? '📺' : c.name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w900, color: navy),
      ),
    );
    if (!c.hasLogo) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.08),
        child: Image.network(
          c.logo,
          fit: BoxFit.contain,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

/// Riquadro grande di un canale.
class ChannelCard extends StatelessWidget {
  const ChannelCard({super.key, required this.list, required this.index, required this.kids});
  final List<Channel> list;
  final int index;
  final bool kids;

  @override
  Widget build(BuildContext context) {
    final c = list[index];
    final acc = accentOf(kids);
    return ListenableBuilder(
      listenable: Favorites.i,
      builder: (context, _) {
        final fav = Favorites.i.isFav(c, kids);
        return Material(
          color: card,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openPlayer(context, list, index, kids: kids),
            onLongPress: () => Favorites.i.toggle(c, kids),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (_, box) =>
                                Center(child: ChannelLogo(c, size: box.biggest.shortestSide, radius: 18)),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Material(
                            color: Colors.black45,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Favorites.i.toggle(c, kids),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(fav ? Icons.favorite : Icons.favorite_border,
                                    color: fav ? const Color(0xFFFF4D6D) : Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: acc, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded, color: navy, size: 26),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.15, color: Colors.white)),
                  if (c.countryCode.isNotEmpty || c.geoBlocked)
                    Text('${c.flag}${c.geoBlocked ? '  🔒 solo nel paese' : ''}',
                        maxLines: 1, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ChannelGrid extends StatelessWidget {
  const ChannelGrid(this.list, {super.key, required this.kids});
  final List<Channel> list;
  final bool kids;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) => ChannelCard(list: list, index: i, kids: kids),
        ),
      );
}

class BigMessage extends StatelessWidget {
  const BigMessage({super.key, required this.emoji, required this.text, this.action});
  final String emoji;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 60)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap, this.color = yellow});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? color : card,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              child: Text(label,
                  style: TextStyle(color: selected ? navy : Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ),
      );
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.onChanged, this.hint = 'Cerca un canale…', this.color = yellow});
  final ValueChanged<String> onChanged;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: TextField(
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white, fontSize: 17),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: Icon(Icons.search_rounded, color: color),
            filled: true,
            fillColor: card,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
          ),
        ),
      );
}

/// Elenco caricato da internet con caricamento, errore e "riprova".
class ChannelsLoader extends StatefulWidget {
  const ChannelsLoader({super.key, required this.url, required this.builder});
  final String url;
  final Widget Function(BuildContext, List<Channel>, Future<void> Function() refresh) builder;
  @override
  State<ChannelsLoader> createState() => _ChannelsLoaderState();
}

class _ChannelsLoaderState extends State<ChannelsLoader> {
  List<Channel>? _list;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() => _error = false);
    try {
      final l = await TvData.i.channels(widget.url, fresh: fresh);
      if (mounted) setState(() => _list = l);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    if (l != null) return widget.builder(context, l, () => _load(fresh: true));
    if (_error) {
      return BigMessage(
        emoji: '📡',
        text: 'Nessuna connessione. Controlla internet e riprova.',
        action: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: yellow, foregroundColor: navy),
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Riprova'),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: yellow));
  }
}
