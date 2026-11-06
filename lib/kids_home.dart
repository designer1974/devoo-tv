import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';
import 'pin.dart';
import 'ui.dart';
import 'world_home.dart';

/// La parte dei bambini: si apre sempre qui. Solo canali per bambini.
/// Per i canali del mondo serve il PIN dei genitori.
class KidsHome extends StatefulWidget {
  const KidsHome({super.key});
  @override
  State<KidsHome> createState() => _KidsHomeState();
}

class _KidsHomeState extends State<KidsHome> {
  String _q = '';
  String _country = ''; // '' = tutti, '*' = preferiti

  Future<void> _openWorld() async {
    if (!await unlockWorld(context) || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WorldHome()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        bottom: false,
        child: ChannelsLoader(
          url: TvData.kidsUrl,
          builder: (context, all, refresh) => ListenableBuilder(
            listenable: Favorites.i,
            builder: (context, _) {
              // paesi presenti, i più numerosi prima
              final count = <String, int>{};
              for (final c in all) {
                if (c.countryCode.isNotEmpty) count[c.countryCode] = (count[c.countryCode] ?? 0) + 1;
              }
              final countries = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
              final base = _country == '*'
                  ? Favorites.i.kids
                  : all.where((c) => _country.isEmpty || c.countryCode == _country).toList();
              final q = _q.toLowerCase();
              final list = q.isEmpty ? base : base.where((c) => c.name.toLowerCase().contains(q)).toList();
              return RefreshIndicator(
                color: yellow,
                onRefresh: refresh,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _header()),
                    SliverToBoxAdapter(child: SearchBox(onChanged: (v) => setState(() => _q = v))),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 52,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                          children: [
                            Pill(label: '⭐ Tutti', selected: _country.isEmpty, onTap: () => setState(() => _country = '')),
                            Pill(label: '❤️ Preferiti', selected: _country == '*', onTap: () => setState(() => _country = '*')),
                            for (final cc in countries)
                              Pill(
                                label: '${flagEmoji(cc)} ${count[cc]}',
                                selected: _country == cc,
                                onTap: () => setState(() => _country = cc),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (list.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: BigMessage(
                          emoji: _country == '*' ? '❤️' : '🔍',
                          text: _country == '*'
                              ? 'Tocca il cuore sui cartoni che ti piacciono: li ritrovi qui!'
                              : 'Nessun canale qui.',
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                          child: Text('${list.length} canali',
                              style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      ChannelGrid(list, kids: true),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('assets/logo.png', width: 48, height: 48),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Devoo TV',
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: yellow, borderRadius: BorderRadius.circular(20)),
                    child: const Text('KIDS',
                        style: TextStyle(color: navy, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2)),
                  ),
                ],
              ),
            ),
            // ingresso dei genitori: chiede il PIN
            Material(
              color: card,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _openWorld,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🌍', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 6),
                      Icon(Icons.lock_rounded, color: sky, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
