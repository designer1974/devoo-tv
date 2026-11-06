import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';
import 'pin.dart';
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
    final q = _q.toLowerCase();
    final list = q.isEmpty
        ? all
        : all.where((c) => c.name.toLowerCase().contains(q) || c.code == q).toList();
    return Column(
      children: [
        SearchBox(hint: 'Cerca un paese…', color: sky, onChanged: (v) => setState(() => _q = v)),
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
