import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';
import 'pin.dart';
import 'ui.dart';
import 'update.dart';
import 'world_pages.dart';

/// Lo scheletro dell'app: una pagina sopra e il menu in basso, come Devoo Radio.
/// Si apre sempre in modalità Kids. Il Mondo si apre solo col PIN, che vale finché
/// l'app resta aperta: uscendo dall'app si torna a Kids e il PIN si richiede.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _world = false;
  int _tab = 0;

  late final AppLifecycleListener _life = AppLifecycleListener(onPause: () {
    Pin.unlocked = false;
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_world) _goKids();
  });

  @override
  void initState() {
    super.initState();
    _life.hashCode; // avvia l'ascolto
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (mounted) checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _goWorld() async {
    if (!await unlockWorld(context) || !mounted) return;
    setState(() {
      _world = true;
      _tab = 0;
    });
  }

  void _goKids() => setState(() {
        _world = false;
        _tab = 0;
      });

  @override
  Widget build(BuildContext context) {
    final acc = accentOf(!_world);
    final pages = _world
        ? const [WorldCountriesPage(), WorldCategoriesPage(), SearchPage(kids: false), FavoritesPage(kids: false)]
        : const [KidsHomePage(), SearchPage(kids: true), FavoritesPage(kids: true)];
    final items = _world
        ? const [
            _Item(Icons.flag_outlined, Icons.flag, 'Paesi'),
            _Item(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Categorie'),
            _Item(Icons.search, Icons.search, 'Cerca'),
            _Item(Icons.favorite_border, Icons.favorite, 'Preferiti'),
            _Item(Icons.child_care_outlined, Icons.child_care, 'Kids'),
          ]
        : const [
            _Item(Icons.home_outlined, Icons.home_rounded, 'Kids'),
            _Item(Icons.search, Icons.search, 'Cerca'),
            _Item(Icons.favorite_border, Icons.favorite, 'Preferiti'),
            _Item(Icons.lock_outline_rounded, Icons.lock_open_rounded, 'Mondo'),
          ];
    return PopScope(
      // "indietro" dal Mondo torna a Kids, non chiude l'app
      canPop: !_world && _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 0) {
          setState(() => _tab = 0);
        } else if (_world) {
          _goKids();
        }
      },
      child: Scaffold(
        backgroundColor: navy,
        body: IndexedStack(
          key: ValueKey(_world),
          index: _tab.clamp(0, pages.length - 1),
          children: pages,
        ),
        bottomNavigationBar: _Footer(
          items: items,
          selected: _tab,
          accent: acc,
          world: _world,
          onTap: (i) {
            if (i == pages.length) {
              // ultimo pulsante: cambia modalità
              _world ? _goKids() : _goWorld();
            } else {
              setState(() => _tab = i);
            }
          },
        ),
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Item(this.icon, this.selectedIcon, this.label);
}

/// Menu in basso: pulsanti grandi, indicatore colorato e l'ultimo pulsante
/// (Mondo 🔒 / Kids) evidenziato perché cambia modalità.
class _Footer extends StatelessWidget {
  const _Footer({required this.items, required this.selected, required this.accent, required this.world, required this.onTap});
  final List<_Item> items;
  final int selected;
  final Color accent;
  final bool world;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: navy2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, -4))],
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.5), width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _button(i, items[i], switchMode: i == items.length - 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(int i, _Item it, {required bool switchMode}) {
    final on = !switchMode && i == selected;
    final other = accentOf(world); // colore dell'altra modalità
    final bg = switchMode ? other : (on ? accent : Colors.transparent);
    final fg = switchMode || on ? navy : Colors.white70;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onTap(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
              child: Icon(on ? it.selectedIcon : it.icon, color: fg, size: 26),
            ),
            const SizedBox(height: 4),
            Text(it.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: on || switchMode ? Colors.white : Colors.white60,
                  fontWeight: on || switchMode ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 12.5,
                )),
          ],
        ),
      ),
    );
  }
}

/// Titolo semplice in alto: logo, nome e modalità.
class TopTitle extends StatelessWidget {
  const TopTitle({super.key, required this.kids, this.title, this.trailing});
  final bool kids;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final acc = accentOf(kids);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/logo.png', width: 40, height: 40),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title ?? 'Devoo TV',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: acc, borderRadius: BorderRadius.circular(20)),
            child: Text(kids ? 'KIDS' : 'MONDO',
                style: const TextStyle(color: navy, fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 1.5)),
          ),
          if (trailing != null) trailing! else const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ───────────────────────── KIDS ─────────────────────────

/// Home dei bambini: tutti i canali per bambini che trasmettono.
class KidsHomePage extends StatelessWidget {
  const KidsHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const TopTitle(kids: true),
          Expanded(
            child: ChannelsLoader(
              url: TvData.kidsUrl,
              builder: (context, list, refresh) => RefreshIndicator(
                color: yellow,
                onRefresh: refresh,
                child: CustomScrollView(slivers: [
                  _Count(list.length),
                  ChannelGrid(list, kids: true),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nomi dei paesi (in italiano quando possibile), caricati una volta.
class CountryNames {
  static Map<String, String> names = {for (final c in fallbackCountries) c.code.toUpperCase(): c.name};
  static Future<void>? _loading;
  static Future<void> load() => _loading ??= TvData.i.countries().then((l) {
        names = {for (final c in l) c.code.toUpperCase(): c.name};
      });
  static String of(String code) => names[code.toUpperCase()] ?? code;
}

/// Cerca: una casella sola, e sotto le schede Canali e Paesi (come Devoo Radio).
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.kids});
  final bool kids;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  final _text = TextEditingController();
  String _q = '';
  List<Country>? _countries;

  @override
  void initState() {
    super.initState();
    CountryNames.load().then((_) {
      if (mounted) setState(() {});
    });
    if (!widget.kids) {
      TvData.i.countries().then((l) {
        if (mounted) setState(() => _countries = l);
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acc = accentOf(widget.kids);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TopTitle(kids: widget.kids, title: 'Cerca'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: TextField(
              controller: _text,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white, fontSize: 17),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _tabs.index == 0 ? 'Cerca un canale…' : 'Cerca un paese…',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: Icon(Icons.search_rounded, color: acc),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () {
                          _text.clear();
                          setState(() => _q = '');
                        },
                      ),
                filled: true,
                fillColor: card,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: acc, width: 2),
                ),
              ),
            ),
          ),
          TabBar(
            controller: _tabs,
            indicatorColor: acc,
            indicatorWeight: 3,
            labelColor: acc,
            unselectedLabelColor: Colors.white60,
            dividerColor: Colors.white10,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            tabs: const [
              Tab(icon: Icon(Icons.live_tv_rounded), text: 'Canali'),
              Tab(icon: Icon(Icons.flag_rounded), text: 'Paesi'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: widget.kids ? [_kidsChannels(), _kidsCountries()] : [_worldChannels(), _worldCountries()],
            ),
          ),
        ],
      ),
    );
  }

  bool _match(Channel c) {
    if (_q.isEmpty) return true;
    final n = c.name.toLowerCase();
    return _q.split(RegExp(r'\s+')).every(n.contains) || CountryNames.of(c.countryCode).toLowerCase().contains(_q);
  }

  Widget _kidsChannels() => ChannelsLoader(
        url: TvData.kidsUrl,
        builder: (context, all, _) {
          final list = all.where(_match).toList();
          if (list.isEmpty) return const BigMessage(emoji: '🔍', text: 'Nessun canale trovato.');
          return CustomScrollView(slivers: [_Count(list.length), ChannelGrid(list, kids: true)]);
        },
      );

  Widget _kidsCountries() => ChannelsLoader(
        url: TvData.kidsUrl,
        builder: (context, all, _) {
          final byCountry = <String, List<Channel>>{};
          for (final c in all) {
            if (c.countryCode.isNotEmpty) byCountry.putIfAbsent(c.countryCode, () => []).add(c);
          }
          final codes = byCountry.keys
              .where((k) => _q.isEmpty || CountryNames.of(k).toLowerCase().contains(_q) || k.toLowerCase() == _q)
              .toList()
            ..sort((a, b) => CountryNames.of(a).compareTo(CountryNames.of(b)));
          if (codes.isEmpty) return const BigMessage(emoji: '🔍', text: 'Nessun paese trovato.');
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
            itemCount: codes.length,
            itemBuilder: (_, i) {
              final cc = codes[i];
              final l = byCountry[cc]!;
              return _CountryTile(
                flag: flagEmoji(cc),
                name: CountryNames.of(cc),
                count: l.length,
                color: yellow,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => _FixedListPage(title: '${flagEmoji(cc)} ${CountryNames.of(cc)}', list: l, kids: true),
                )),
              );
            },
          );
        },
      );

  Widget _worldChannels() {
    if (_q.length < 2) {
      return const BigMessage(emoji: '📺', text: 'Scrivi il nome di un canale, per esempio «MBC 2» o «Rai».');
    }
    return SearchResults(query: _q, countries: const []);
  }

  Widget _worldCountries() {
    final all = _countries;
    if (all == null) return const Center(child: CircularProgressIndicator(color: sky));
    final list = _q.isEmpty ? all : all.where((c) => c.name.toLowerCase().contains(_q) || c.code == _q).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
      itemCount: list.length,
      itemBuilder: (_, i) => _CountryTile(
        flag: list[i].flag,
        name: list[i].name,
        color: sky,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ChannelListPage(title: '${list[i].flag} ${list[i].name}', url: TvData.countryUrl(list[i].code)),
        )),
      ),
    );
  }
}

/// Elenco già pronto (es. i canali Kids di un paese).
class _FixedListPage extends StatelessWidget {
  const _FixedListPage({required this.title, required this.list, required this.kids});
  final String title;
  final List<Channel> list;
  final bool kids;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: navy,
        appBar: AppBar(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: CustomScrollView(slivers: [_Count(list.length), ChannelGrid(list, kids: kids)]),
      );
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({required this.flag, required this.name, required this.color, required this.onTap, this.count});
  final String flag;
  final String name;
  final int? count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Text(flag, style: const TextStyle(fontSize: 30)),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (count != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                child: Text('$count', style: const TextStyle(color: navy, fontWeight: FontWeight.w900)),
              ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
        onTap: onTap,
      );
}

class _Count extends StatelessWidget {
  const _Count(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Text('$n canali', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
        ),
      );
}

/// Preferiti (separati per Kids e Mondo).
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key, required this.kids});
  final bool kids;

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Column(
          children: [
            TopTitle(kids: kids, title: 'Preferiti'),
            Expanded(
              child: ListenableBuilder(
                listenable: Favorites.i,
                builder: (context, _) {
                  final l = Favorites.i.of(kids);
                  if (l.isEmpty) {
                    return BigMessage(
                      emoji: '❤️',
                      text: kids
                          ? 'Tocca il cuore sui cartoni che ti piacciono: li ritrovi qui!'
                          : 'Tocca il cuore sui canali che ti piacciono: li ritrovi qui.',
                    );
                  }
                  return CustomScrollView(slivers: [_Count(l.length), ChannelGrid(l, kids: kids)]);
                },
              ),
            ),
          ],
        ),
      );
}

// ───────────────────────── MONDO ─────────────────────────

class WorldCountriesPage extends StatefulWidget {
  const WorldCountriesPage({super.key});
  @override
  State<WorldCountriesPage> createState() => _WorldCountriesPageState();
}

class _WorldCountriesPageState extends State<WorldCountriesPage> {
  List<Country>? _countries;

  @override
  void initState() {
    super.initState();
    TvData.i.countries().then((l) {
      if (mounted) setState(() => _countries = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _countries;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TopTitle(
            kids: false,
            title: 'Paesi',
            trailing: PopupMenuButton<String>(
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
          ),
          Expanded(
            child: all == null
                ? const Center(child: CircularProgressIndicator(color: sky))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                    itemCount: all.length,
                    itemBuilder: (_, i) => _CountryTile(
                      flag: all[i].flag,
                      name: all[i].name,
                      color: sky,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ChannelListPage(title: '${all[i].flag} ${all[i].name}', url: TvData.countryUrl(all[i].code)),
                      )),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class WorldCategoriesPage extends StatelessWidget {
  const WorldCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Column(
          children: [
            const TopTitle(kids: false, title: 'Categorie'),
            Expanded(
              child: GridView.builder(
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
                          Text(label,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}
