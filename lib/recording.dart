import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'update.dart' show appChannel;

String two(int n) => n.toString().padLeft(2, '0');

String fmtDur(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String fmtSize(int b) => b >= 1024 * 1024 * 1024
    ? '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB'
    : b >= 1024 * 1024
        ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
        : '${(b / 1024).toStringAsFixed(0)} KB';

String fmtDate(DateTime d) => '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
String hhmm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String fmtLen(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? (h == 1 ? '1 ora' : '$h ore') : '$h h $m min';
}

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (diff == 0) return 'oggi';
  if (diff == 1) return 'domani';
  return '${two(d.day)}/${two(d.month)}';
}

/// Una registrazione salvata (.ts o .mp4).
class RecFile {
  final File file;
  final String name;
  final DateTime date;
  final int size;
  RecFile(this.file, this.name, this.date, this.size);
}

/// Le registrazioni: una cartella per i bambini e una per il Mondo
/// (così i bambini vedono solo le loro).
class Recordings extends ChangeNotifier {
  Recordings._();
  static final i = Recordings._();

  List<RecFile> kids = [];
  List<RecFile> world = [];

  List<RecFile> of(bool k) => k ? kids : world;

  Future<Directory> dir(bool k) async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/recordings/${k ? 'kids' : 'world'}');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<RecFile>> _list(bool k) async {
    final d = await dir(k);
    final out = <RecFile>[];
    for (final e in d.listSync()) {
      if (e is! File) continue;
      final base = e.path.split('/').last;
      if (base.endsWith('.part') || base.startsWith('.')) continue;
      final dot = base.lastIndexOf('.');
      if (dot <= 0) continue;
      final st = e.statSync();
      out.add(RecFile(e, base.substring(0, dot), st.modified, st.size));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<void> reload() async {
    try {
      kids = await _list(true);
      world = await _list(false);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> delete(RecFile r) async {
    try {
      await r.file.delete();
    } catch (_) {}
    await reload();
  }

  Future<void> rename(RecFile r, String name) async {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    final ext = r.file.path.split('.').last;
    final dirPath = r.file.parent.path;
    var p = '$dirPath/$clean.$ext';
    var n = 2;
    while (p != r.file.path && File(p).existsSync()) {
      p = '$dirPath/$clean ($n).$ext';
      n++;
    }
    if (p != r.file.path) await r.file.rename(p);
    await reload();
  }
}

/// Una registrazione programmata (anche quella "adesso", che è un programma che parte subito).
class Schedule {
  final String id;
  final String name;
  final String flag;
  final DateTime start;
  final DateTime end;
  final bool daily;
  final bool running;
  final bool kids;
  const Schedule(this.id, this.name, this.flag, this.start, this.end, this.daily, this.running, this.kids);

  Duration get length => end.difference(start);

  static Schedule? from(Map m) {
    try {
      return Schedule(
        '${m['id']}',
        '${m['name'] ?? ''}',
        '${m['flag'] ?? ''}',
        DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
        DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
        m['daily'] == true,
        m['running'] == true,
        m['kids'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Programmi di registrazione: li esegue il servizio Android, anche ad app chiusa e schermo spento.
class Schedules extends ChangeNotifier {
  Schedules._() {
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _status());
  }
  static final i = Schedules._();

  // ignore: unused_field
  Timer? _poll;
  List<Schedule> items = [];

  // registrazione in corso
  String? runningId;
  String runningName = '';
  DateTime? runningStart;
  DateTime? runningEnd;
  int runningBytes = 0;

  bool get recording => runningId != null;

  Duration get elapsed => runningStart == null ? Duration.zero : DateTime.now().difference(runningStart!);

  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  Future<void> _status() async {
    try {
      final m = await appChannel.invokeMethod<Map>('recStatus');
      if (m == null) return;
      final id = m['schedId'] as String?;
      if (id != null && m['busy'] == true) {
        final first = runningId != id;
        runningId = id;
        runningName = '${m['schedName'] ?? ''}';
        final st = (m['startedAt'] as num?)?.toInt() ?? 0;
        runningStart = st > 0 ? DateTime.fromMillisecondsSinceEpoch(st) : DateTime.now();
        final e = (m['schedEnd'] as num?)?.toInt() ?? 0;
        runningEnd = e > 0 ? DateTime.fromMillisecondsSinceEpoch(e) : null;
        runningBytes = (m['bytes'] as num?)?.toInt() ?? 0;
        if (first) unawaited(reload());
        notifyListeners();
      } else if (runningId != null) {
        runningId = null;
        runningBytes = 0;
        notifyListeners();
        _messages.add('Registrazione salvata in Registrate 🎬');
        unawaited(Recordings.i.reload());
        unawaited(reload());
      }
    } catch (_) {}
  }

  Future<void> reload() async {
    try {
      final l = await appChannel.invokeMethod<List>('schedList') ?? const [];
      items = l.whereType<Map>().map(Schedule.from).whereType<Schedule>().toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      notifyListeners();
    } catch (_) {}
  }

  /// Programma (o registra subito, se [start] è adesso) un canale.
  Future<void> add(Channel c, DateTime start, DateTime end, {bool daily = false, required bool kids}) async {
    final dir = await Recordings.i.dir(kids);
    await appChannel.invokeMethod('schedAdd', {
      'id': '${DateTime.now().microsecondsSinceEpoch}',
      'name': c.name,
      'flag': c.flag == '🌍' ? '' : c.flag,
      'url': c.url,
      'headersJson': jsonEncode(c.headers),
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'daily': daily,
      'dir': dir.path,
      'kids': kids,
    });
    await reload();
  }

  Future<void> remove(Schedule s) async {
    try {
      await appChannel.invokeMethod('schedRemove', {'id': s.id});
    } catch (_) {}
    await reload();
  }

  /// Ferma quella in corso e la salva.
  Future<void> stop() async {
    try {
      await appChannel.invokeMethod('schedStop');
    } catch (_) {}
  }

  List<Schedule> overlapping(DateTime start, DateTime end) =>
      items.where((x) => x.start.isBefore(end) && start.isBefore(x.end)).toList();

  Future<bool> _ask(String m, bool fallback) async {
    try {
      return await appChannel.invokeMethod<bool>(m) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<bool> exactOk() => _ask('schedExactOk', true);
  Future<bool> batteryOk() => _ask('batteryOk', true);
  Future<void> batteryAsk() => _ask('batteryAsk', true);
  Future<void> openExactSettings() => _ask('schedExactSettings', true);
}
