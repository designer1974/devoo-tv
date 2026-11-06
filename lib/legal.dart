import 'package:flutter/material.dart';

import 'ui.dart';

Future<void> openLegal(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalPage()));

/// Note legali: da dove vengono i canali e come chiedere di toglierne uno.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    const title = TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900);
    const body = TextStyle(color: Colors.white70, fontSize: 15.5, height: 1.45);
    Widget section(String t, String b) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: title),
            const SizedBox(height: 6),
            Text(b, style: body),
          ]),
        );
    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('⚖️ Note legali', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          section('Da dove vengono i canali',
              'Devoo TV mostra canali che trasmettono gratuitamente in internet, presi dall\'elenco pubblico '
              'iptv-org (github.com/iptv-org/iptv). Devoo TV non trasmette, non registra e non salva nessun video: '
              'il video arriva direttamente dal sito di chi trasmette il canale.'),
          section('Nessun canale a pagamento',
              'L\'app non contiene abbonamenti né canali a pagamento. Per prudenza sono esclusi anche i canali di '
              'film, serie, sport, classici e i canali «24/7», oltre a tutti i canali per adulti.'),
          section('Marchi e diritti',
              'Nomi, loghi e programmi appartengono ai rispettivi proprietari. Devoo TV non è collegata ai canali mostrati.'),
          section('Togliere un canale',
              'Se hai i diritti di un canale e non vuoi che compaia in Devoo TV, scrivici tramite il sito devoo.it '
              'indicando il nome del canale: lo togliamo da tutte le app, senza bisogno di aggiornarle.'),
          section('Bambini',
              'La parte Kids mostra solo canali della categoria bambini. Gli altri canali si aprono solo con il PIN '
              'dei genitori. L\'app non chiede nomi, email o altri dati personali.'),
        ],
      ),
    );
  }
}
