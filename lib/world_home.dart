import 'dart:async';

import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';
import 'pin.dart';
import 'probe.dart';
import 'ui.dart';
import 'update.dart';

/// I canali del mondo (solo per i genitori, dopo il PIN): per paese o per categoria.
/// Uscendo da qui si torna sempre ai bambini, e per rientrare serve di nuovo il PIN.
class WorldHome extends StatefulWidget {
  const WorldHome({super.key});
  @override
  State<WorldHome> createState() => _WorldHomeState();
}

class _WorldHomeState extends State<WorldHome> with WidgetsBindingObserver {
  int _tab = 0;
  String _q = '';
  List<Country>? _countries;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TvData.i.countries().then((l) {
      if (mounted) setState(() => _countries = l);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // l'app va in background: si richiude, così un bambino che la riprende trova solo Kids
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Text('🌍 ', style: TextStyle(fontSize: 22)),
            Text('Canali del mondo', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            color: navy2,
            iconColor: Colors.white,
            onSelected: (v) {
              if (v == 'pin') changePin(context);
              if (v == 'update') checkForUpdateNow(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pin', child: Text('🔑 Cambia PIN', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: 'update', child: Text('🔄 Cerca aggiornamenti', style: TextStyle(color: Colors.white))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: yellow, foregroundColor: navy),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.lock_rounded, size: 18),
              label: const Text('Kids', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [_countriesTab(), _categoriesTab(), _favTab()],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: navy2,
          indicatorColor: sky,
          labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
          iconTheme: WidgetStateProperty.resolveWith(
              (s) => IconThemeData(color: s.contains(WidgetState.selected) ? navy : Colors.white70)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'Paesi'),
            NavigationDestination(
                icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: 'Categorie'),
            NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Preferiti'),
          ],
        ),
      ),
    );
  }

  Widget _countriesTab() {
    final all = _countries;
    if (all == null) return const Center(child: CircularProgressIndicator(color: sky));
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all.where((c) => c.name.toLowerCase().contains(q) || c.code == q).toList();
    return Column(
      children: [
        SearchBox(hint: 'Cerca un paese o un canale…', color: sky, onChanged: (v) => setState(() => _q = v)),
        if (q.length >= 2)
          Expanded(child: SearchResults(query: q, countries: list))
        else
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final c = list[i];
              return ListTile(
                leading: Text(c.flag, style: const TextStyle(fontSize: 30)),
                title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChannelListPage(title: '${c.flag} ${c.name}', url: TvData.countryUrl(c.code)),
                )),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _categoriesTab() => GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
        ),
        itemCount: worldCategories.length,
        itemBuilder: (_, i) {
          final (id, emoji, label) = worldCategories[i];
          return Material(
            color: card,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ChannelListPage(title: '$emoji $label', url: TvData.categoryUrl(id)),
              )),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 34)),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
            ),
          );
        },
      );

  Widget _favTab() => ListenableBuilder(
        listenable: Favorites.i,
        builder: (context, _) {
          final l = Favorites.i.world;
          if (l.isEmpty) {
            return const BigMessage(emoji: '❤️', text: 'Tocca il cuore sui canali che ti piacciono: li ritrovi qui.');
          }
          return CustomScrollView(slivers: [ChannelGrid(l, kids: false)]);
        },
      );
}

/// I canali di un paese o di una categoria, con la ricerca.
class ChannelListPage extends StatefulWidget {
  const ChannelListPage({super.key, required this.title, required this.url});
  final String title;
  final String url;
  @override
  State<ChannelListPage> createState() => _ChannelListPageState();
}

class _ChannelListPageState extends State<ChannelListPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ChannelsLoader(
        url: widget.url,
        color: sky,
        builder: (context, all, refresh) {
          final q = _q.toLowerCase();
          final list = q.isEmpty ? all : all.where((c) => c.name.toLowerCase().contains(q)).toList();
          return RefreshIndicator(
            color: sky,
            onRefresh: refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: SearchBox(color: sky, onChanged: (v) => setState(() => _q = v))),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                    child: Text('${list.length} canali',
                        style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
                  ),
                ),
                if (list.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: BigMessage(emoji: '🔍', text: 'Nessun canale trovato.'),
                  )
                else
                  ChannelGrid(list, kids: false),
              ],
            ),
          );
        },
      ),
    );
  }
}


/// Ricerca in tutto il mondo: i paesi che corrispondono, poi i canali (solo quelli che trasmettono).
class SearchResults extends StatefulWidget {
  const SearchResults({super.key, required this.query, required this.countries});
  final String query;
  final List<Country> countries;
  @override
  State<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
  List<Channel>? _all;
  bool _error = false;
  List<Channel> _good = const [];
  bool _checking = false;
  int _run = 0;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    TvData.i.channels(TvData.allUrl).then((l) {
      if (!mounted) return;
      _all = l;
      _search();
    }, onError: (Object _) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  void didUpdateWidget(SearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _wait?.cancel();
      _wait = Timer(const Duration(milliseconds: 450), _search); // aspetta che finisca di scrivere
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _run++;
    super.dispose();
  }

  Future<void> _search() async {
    final all = _all;
    if (all == null || !mounted) return;
    final run = ++_run;
    final q = widget.query;
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final found = all.where((c) {
      final n = c.name.toLowerCase();
      return words.every(n.contains);
    }).toList()
      ..sort((a, b) {
        final sa = a.name.toLowerCase().startsWith(q) ? 0 : 1, sb = b.name.toLowerCase().startsWith(q) ? 0 : 1;
        return sa != sb ? sa.compareTo(sb) : a.name.length.compareTo(b.name.length);
      });
    final top = found.take(80).toList();
    setState(() {
      _good = const [];
      _checking = true;
    });
    final good = await Probe.i.filter(top, (g, _) {
      if (mounted && run == _run) setState(() => _good = g);
    }, cancelled: () => !mounted || run != _run);
    if (mounted && run == _run) {
      setState(() {
        _good = good;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final countries = widget.countries.take(5).toList();
    return CustomScrollView(
      slivers: [
        if (countries.isNotEmpty) ...[
          const _Head('🏳️ Paesi'),
          SliverList.builder(
            itemCount: countries.length,
            itemBuilder: (_, i) {
              final c = countries[i];
              return ListTile(
                leading: Text(c.flag, style: const TextStyle(fontSize: 28)),
                title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChannelListPage(title: '${c.flag} ${c.name}', url: TvData.countryUrl(c.code)),
                )),
              );
            },
          ),
        ],
        const _Head('📺 Canali'),
        if (_error)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Nessuna connessione. Riprova.', style: TextStyle(color: Colors.white70)),
            ),
          )
        else if (_all == null || (_checking && _good.isEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: sky)),
                  const SizedBox(width: 14),
                  Text(_all == null ? 'Carico tutti i canali del mondo…' : 'Cerco i canali che trasmettono…',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          )
        else if (_good.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nessun canale trovato che trasmette adesso.', style: TextStyle(color: Colors.white70)),
            ),
          )
        else
          ChannelGrid(_good, kids: false),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
        ),
      );
}
