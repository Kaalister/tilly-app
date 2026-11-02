import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

void main() {
  test('the Config page tutorial presents every configuration tab', () {
    final content = tikoTutorialForTab(AppTabIds.config);
    final text = content.messages.join(' ');

    for (final tab in const [
      'Personnalisation',
      'Comptes & services',
      'Mises à jour',
      'Sauvegarde',
      'Remise à zéro',
      'À propos',
    ]) {
      expect(text, contains(tab),
          reason: 'le tuto de Config doit présenter l\'onglet $tab');
    }

    expect(text, isNot(contains('La partie HelloAsso')),
        reason: 'l\'ancienne formulation par parties ne doit plus apparaître');
  });

  test('every page still has a short tutorial', () {
    for (final tabId in AppTabIds.all) {
      final content = tikoTutorialForTab(tabId);
      expect(content.messages, isNotEmpty);
      for (final message in content.messages) {
        expect(message.trim(), isNotEmpty);
        expect(message.length, lessThanOrEqualTo(190),
            reason: 'le tuto de $tabId doit rester court : "$message"');
      }
    }
  });
}
