import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'player_page.dart';
import 'recording.dart';
import 'ui.dart';

const recRed = Color(0xFFFF3B5C);

/// «Registra adesso»: sceglie per quanto, poi registra in alta qualità anche ad app chiusa.
Future<void> recordNow(BuildContext context, Channel c, {required bool kids}) async {
  if (!c.url.startsWith('http')) return;
  if (Schedules.i.recording) {
    snack(context, 'C\'è già una registrazione in corso: fermala prima');
    return;
  }
  final minutes = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: navy2,
    showDragHandle: true,
    builder: (s) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('🔴 Registra «${c.name}» per…',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 6),
            const Text('Si ferma da solo alla fine, oppure quando premi «Ferma».',
                style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in const [15, 30, 60, 90, 120, 180, 240])
                  ActionChip(
                    label: Text(fmtLen(Duration(minutes: m))),
                    labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                    backgroundColor: recRed,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    onPressed: () => Navigator.pop(s, m),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (minutes == null) return;
  final now = DateTime.now();
  try {
    await Schedules.i.add(c, now, now.add(Duration(minutes: minutes)), kids: kids);
    if (context.mounted) snack(context, '🔴 Registro «${c.name}» per ${fmtLen(Duration(minutes: minutes))}');
  } catch (_) {
    if (context.mounted) snack(context, 'Registrazione non avviata. Riprova.');
  }
}

/// Barra rossa sopra il menu mentre si registra.
class RecBanner extends StatelessWidget {
  const RecBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Schedules.i,
      builder: (context, _) {
        final s = Schedules.i;
        if (!s.recording) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(color: recRed, borderRadius: BorderRadius.circular(22)),
          child: Row(
            children: [
              const Icon(Icons.fiber_manual_record_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.runningName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmtDur(s.elapsed),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  Text(fmtSize(s.runningBytes), style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                ],
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: s.stop,
                style: TextButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: recRed, shape: const StadiumBorder()),
                child: const Text('Ferma', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pagina «Registrate»: programmi e video salvati.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key, required this.kids, this.top});
  final bool kids;
  final Widget? top;
  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  @override
  void initState() {
    super.initState();
    Recordings.i.reload();
    Schedules.i.reload();
  }

  Future<void> _rename(RecFile r) async {
    final c = TextEditingController(text: r.name);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: navy2,
        title: const Text('✏️ Nuovo nome', style: TextStyle(color: Colors.white)),
        content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Salva')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.trim().isNotEmpty) await Recordings.i.rename(r, name);
  }

  Future<void> _delete(RecFile r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: navy2,
        title: const Text('🗑️ Eliminare?', style: TextStyle(color: Colors.white)),
        content: Text('«${r.name}» sarà cancellata.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: recRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) await Recordings.i.delete(r);
  }

  Future<void> _share(RecFile r) async {
    try {
      final mime = r.file.path.endsWith('.mp4') ? 'video/mp4' : 'video/mp2t';
      await Share.shareXFiles([XFile(r.file.path, mimeType: mime)], text: r.name);
    } catch (_) {
      if (mounted) snack(context, 'Condivisione non riuscita');
    }
  }

  void _play(List<RecFile> all, int i) {
    final list = [for (final r in all) Channel(id: '', name: r.name, url: r.file.path)];
    openPlayer(context, list, i, kids: widget.kids);
  }

  @override
  Widget build(BuildContext context) {
    final acc = accentOf(widget.kids);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (widget.top != null) widget.top!,
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([Recordings.i, Schedules.i]),
              builder: (context, _) {
                final recs = Recordings.i.of(widget.kids);
                final sched = Schedules.i.items.where((s) => s.kids == widget.kids).toList();
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                        child: Text(
                          'Per registrare: tieni premuto su un canale, oppure usa il pulsante 🔴 mentre lo guardi.',
                          style: TextStyle(color: acc.withValues(alpha: 0.9), fontSize: 13.5, height: 1.35),
                        ),
                      ),
                    ),
                    if (sched.isNotEmpty) ...[
                      const _Title('⏰ Programmate'),
                      SliverList.builder(itemCount: sched.length, itemBuilder: (_, i) => _ScheduleTile(sched[i])),
                    ],
                    const _Title('🎬 Le mie registrazioni'),
                    if (recs.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(24, 4, 24, 30),
                          child: Text('Ancora nessuna registrazione.',
                              style: TextStyle(color: Colors.white60, fontSize: 16)),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 20),
                        sliver: SliverList.builder(
                          itemCount: recs.length,
                          itemBuilder: (_, i) {
                            final r = recs[i];
                            return Container(
                              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: Material(
                                      color: acc,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => _play(recs, i),
                                        child: const Icon(Icons.play_arrow_rounded, color: navy, size: 32),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                                        const SizedBox(height: 3),
                                        Text('${fmtDate(r.date)} · ${fmtSize(r.size)}',
                                            style: const TextStyle(color: Colors.white60, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    iconColor: Colors.white70,
                                    color: navy2,
                                    onSelected: (v) => switch (v) {
                                      'share' => _share(r),
                                      'rename' => _rename(r),
                                      _ => _delete(r),
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'share', child: Text('📤 Condividi', style: TextStyle(color: Colors.white))),
                                      PopupMenuItem(
                                          value: 'rename', child: Text('✏️ Rinomina', style: TextStyle(color: Colors.white))),
                                      PopupMenuItem(
                                          value: 'delete', child: Text('🗑️ Elimina', style: TextStyle(color: Colors.white))),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile(this.s);
  final Schedule s;

  @override
  Widget build(BuildContext context) {
    final when = s.daily
        ? 'ogni giorno ${hhmm(s.start)} – ${hhmm(s.end)}'
        : '${dayLabel(s.start)} ${hhmm(s.start)} – ${hhmm(s.end)}';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: s.running ? Border.all(color: recRed, width: 2) : null,
      ),
      child: Row(
        children: [
          Text(s.running ? '🔴' : '⏰', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.flag.isEmpty ? '' : '${s.flag} '}${s.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(s.running ? 'Sto registrando · fino alle ${hhmm(s.end)}' : '$when · ${fmtLen(s.length)}',
                    style: TextStyle(color: s.running ? const Color(0xFFFF8FA3) : yellowSoft, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            tooltip: s.running ? 'Ferma e salva' : 'Elimina',
            icon: Icon(s.running ? Icons.stop_circle_rounded : Icons.delete_outline_rounded,
                color: s.running ? recRed : Colors.white60, size: 28),
            onPressed: () => s.running ? Schedules.i.stop() : Schedules.i.remove(s),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      );
}

// ───────────────────────── programma con orario ─────────────────────────

const _weekdays = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];

Future<void> openScheduleEditor(BuildContext context, Channel c, {required bool kids}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScheduleEditor(channel: c, kids: kids)));

/// Programma una registrazione: giorno, ora, durata, ogni giorno.
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({super.key, required this.channel, required this.kids});
  final Channel channel;
  final bool kids;
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  int _day = 0;
  late TimeOfDay _time;
  int _durMin = 60;
  bool _daily = false;
  bool _saving = false;
  bool _exactOk = true;
  bool _batteryOk = true;
  static const _durations = [15, 30, 45, 60, 90, 120, 180, 240];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final next = ((now.hour * 60 + now.minute) ~/ 15 + 1) * 15;
    if (next >= 24 * 60) {
      _day = 1;
      _time = TimeOfDay(hour: (next - 24 * 60) ~/ 60, minute: next % 60);
    } else {
      _time = TimeOfDay(hour: next ~/ 60, minute: next % 60);
    }
    _check();
  }

  Future<void> _check() async {
    final e = await Schedules.i.exactOk();
    final b = await Schedules.i.batteryOk();
    if (!mounted) return;
    setState(() {
      _exactOk = e;
      _batteryOk = b;
    });
  }

  DateTime _base(int d) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(Duration(days: d));
  }

  DateTime get _start {
    final b = _base(_day);
    return DateTime(b.year, b.month, b.day, _time.hour, _time.minute);
  }

  DateTime get _end => _start.add(Duration(minutes: _durMin));

  String _dayName(int d) {
    if (d == 0) return 'Oggi';
    if (d == 1) return 'Domani';
    final b = _base(d);
    final w = _weekdays[b.weekday - 1];
    return '${w[0].toUpperCase()}${w.substring(1)} ${b.day}';
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'A che ora inizia?',
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    var start = _start;
    final now = DateTime.now();
    if (_end.isBefore(now)) {
      snack(context, 'Questo orario è già passato: scegli un\'ora più avanti');
      return;
    }
    if (start.isBefore(now)) start = now;
    if (Schedules.i.overlapping(start, _end).isNotEmpty) {
      snack(context, '⚠️ A quest\'ora c\'è già un\'altra registrazione: si registra un canale alla volta');
    }
    setState(() => _saving = true);
    try {
      await Schedules.i.add(widget.channel, start, _end, daily: _daily, kids: widget.kids);
      if (!mounted) return;
      Navigator.pop(context);
      snack(context, '⏰ Programmata: ${widget.channel.name}, ${dayLabel(start)} alle ${hhmm(start)}');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        snack(context, 'Non sono riuscito a programmarla. Riprova.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc = accentOf(widget.kids);
    final c = widget.channel;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
        );
    Widget pick(String l, bool on, VoidCallback tap) => Material(
          color: on ? acc : card,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Text(l, style: TextStyle(color: on ? navy : Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        );
    Widget warn(String text, String button, Future<void> Function() tap) => Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF3A2A00),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: yellow.withValues(alpha: 0.6)),
          ),
          child: Row(children: [
            const Text('⚠️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white, height: 1.3))),
            TextButton(
              onPressed: () async {
                await tap();
                await Future<void>.delayed(const Duration(seconds: 2));
                _check();
              },
              child: Text(button, style: const TextStyle(color: yellow, fontWeight: FontWeight.w900)),
            ),
          ]),
        );
    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('⏰ Programma registrazione', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          Row(children: [
            ChannelLogo(c, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Text('${c.flag} ${c.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ]),
          label('📅 Giorno'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var d = 0; d < 7; d++) pick(_dayName(d), _day == d, () => setState(() => _day = d)),
          ]),
          label('🕒 Inizio'),
          Material(
            color: acc,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _pickTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text('${two(_time.hour)}:${two(_time.minute)}',
                      style: const TextStyle(color: navy, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2)),
                ),
              ),
            ),
          ),
          label('⏳ Quanto dura'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in _durations) pick(fmtLen(Duration(minutes: m)), _durMin == m, () => setState(() => _durMin = m)),
          ]),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
            child: SwitchListTile(
              value: _daily,
              onChanged: (v) => setState(() => _daily = v),
              activeThumbColor: navy,
              activeTrackColor: acc,
              title: const Text('🔁 Ogni giorno', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              subtitle: const Text('Registra alla stessa ora tutti i giorni', style: TextStyle(color: Colors.white60)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Registrerò «${c.name}» ${_daily ? 'ogni giorno' : dayLabel(_start)} dalle ${hhmm(_start)} alle ${hhmm(_end)}, '
            'nella qualità più alta. Funziona anche con l\'app chiusa e lo schermo spento.',
            style: const TextStyle(color: yellowSoft, fontSize: 15, height: 1.35),
          ),
          if (!_exactOk)
            warn('Per partire all\'ora giusta, permetti a Devoo TV di usare «Sveglie e promemoria».', 'Permetti',
                Schedules.i.openExactSettings),
          if (!_batteryOk)
            warn('Il risparmio batteria potrebbe fermare la registrazione. Lascia lavorare l\'app senza limiti.',
                'Consenti', Schedules.i.batteryAsk),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 58,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: acc,
                foregroundColor: navy,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.alarm_add_rounded, size: 28),
              label: const Text('Programma'),
            ),
          ),
        ),
      ),
    );
  }
}
