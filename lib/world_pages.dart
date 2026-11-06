import 'dart:async';

import 'package:flutter/material.dart';

import 'data.dart';
import 'hidden.dart';
import 'models.dart';
import 'probe.dart';
import 'ui.dart';

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
        noKids: true,
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
    final found = Hidden.i.filter(all.where((c) => !c.isKids).toList()).where((c) {
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
