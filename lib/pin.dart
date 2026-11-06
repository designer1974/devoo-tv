import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui.dart';

/// PIN dei genitori: serve per entrare nei canali del mondo.
/// Si salva solo l'impronta (hash), mai il PIN in chiaro.
class Pin {
  static const _k = 'parent_pin_v1';
  static const _salt = 'devoo-tv-pin';

  static String _hash(String pin) => sha256.convert(utf8.encode('$_salt:$pin')).toString();

  static Future<bool> exists() async => (await SharedPreferences.getInstance()).getString(_k) != null;

  static Future<bool> check(String pin) async =>
      (await SharedPreferences.getInstance()).getString(_k) == _hash(pin);

  static Future<void> set(String pin) async => (await SharedPreferences.getInstance()).setString(_k, _hash(pin));
}

/// Chiede il PIN (o lo crea la prima volta). Ritorna true se si può entrare.
Future<bool> unlockWorld(BuildContext context) async {
  if (!await Pin.exists()) {
    if (!context.mounted) return false;
    final first = await askPin(context, title: 'Crea il PIN dei genitori', hint: 'Scegli 4 numeri da ricordare');
    if (first == null || !context.mounted) return false;
    final again = await askPin(context, title: 'Ripeti il PIN', hint: 'Scrivi di nuovo gli stessi 4 numeri');
    if (again == null || !context.mounted) return false;
    if (again != first) {
      snack(context, 'I due PIN sono diversi. Riprova.');
      return false;
    }
    await Pin.set(first);
    if (context.mounted) snack(context, 'PIN creato ✔ Senza PIN si vedono solo i canali per bambini.');
    return true;
  }
  if (!context.mounted) return false;
  final pin = await askPin(context, title: '🔒 Solo per i genitori', hint: 'Scrivi il PIN', check: Pin.check);
  return pin != null;
}

/// Cambia il PIN (serve quello vecchio).
Future<void> changePin(BuildContext context) async {
  final old = await askPin(context, title: 'PIN attuale', hint: 'Scrivi il PIN di adesso', check: Pin.check);
  if (old == null || !context.mounted) return;
  final n1 = await askPin(context, title: 'Nuovo PIN', hint: 'Scegli 4 numeri');
  if (n1 == null || !context.mounted) return;
  final n2 = await askPin(context, title: 'Ripeti il nuovo PIN', hint: 'Scrivi di nuovo gli stessi 4 numeri');
  if (n2 == null || !context.mounted) return;
  if (n1 != n2) {
    snack(context, 'I due PIN sono diversi. Il PIN non è cambiato.');
    return;
  }
  await Pin.set(n1);
  if (context.mounted) snack(context, 'PIN cambiato ✔');
}

/// Tastierino con 4 pallini. [check]: se c'è, il PIN sbagliato viene rifiutato.
Future<String?> askPin(BuildContext context,
    {required String title, required String hint, Future<bool> Function(String)? check}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinDialog(title: title, hint: hint, check: check),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.hint, this.check});
  final String title;
  final String hint;
  final Future<bool> Function(String)? check;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';
  String? _error;
  int _wrong = 0;
  DateTime? _waitUntil;

  Future<void> _tap(String d) async {
    final wait = _waitUntil;
    if (wait != null && DateTime.now().isBefore(wait)) return;
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < 4) return;
    final check = widget.check;
    if (check == null || await check(_pin)) {
      if (mounted) Navigator.pop(context, _pin);
      return;
    }
    _wrong++;
    if (!mounted) return;
    setState(() {
      _pin = '';
      // dopo 3 errori bisogna aspettare: un bambino non può provare tutti i numeri
      if (_wrong >= 3) {
        final secs = 30 * (_wrong - 2);
        _waitUntil = DateTime.now().add(Duration(seconds: secs));
        _error = 'PIN sbagliato. Aspetta $secs secondi.';
      } else {
        _error = 'PIN sbagliato';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: card,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap ?? () => _tap(label),
              child: SizedBox(
                width: 66,
                height: 66,
                child: Center(
                  child: icon != null
                      ? Icon(icon, color: Colors.white70)
                      : Text(label,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
          ),
        );
    return Dialog(
      backgroundColor: navy2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 6),
            Text(_error ?? widget.hint,
                textAlign: TextAlign.center,
                style: TextStyle(color: _error != null ? const Color(0xFFFF8FA3) : Colors.white60)),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? yellow : Colors.transparent,
                      border: Border.all(color: yellow, width: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                key('', icon: Icons.close_rounded, onTap: () => Navigator.pop(context)),
                key('0'),
                key('', icon: Icons.backspace_outlined, onTap: () {
                  if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
