import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  late HelloAssoImportService service;

  setUp(() {
    service = HelloAssoImportService();
  });

  HelloAssoRegistrant registrant({
    String firstName = 'Léa',
    String lastName = 'Thomas',
    String email = 'lea@exemple.fr',
    String helloassoUserId = 'ha-1',
  }) =>
      HelloAssoRegistrant(
        firstName: firstName,
        lastName: lastName,
        email: email,
        helloassoUserId: helloassoUserId,
      );

  test('creates a public player from the registrant', () {
    final allPlayers = <Player>[];
    final sessionPlayers = <Player>[];
    final player = service.attachRegistrant(
      registrant: registrant(),
      allPlayers: allPlayers,
      sessionPlayers: sessionPlayers,
    );
    expect(player.name, 'Léa Thomas');
    expect(player.type, 'public');
    expect(player.email, 'lea@exemple.fr');
    expect(player.helloassoUserId, 'ha-1');
    expect(allPlayers, [player]);
    expect(sessionPlayers, [player]);
  });

  test('falls back to the email when the name is empty', () {
    final player = service.attachRegistrant(
      registrant: registrant(firstName: '', lastName: ''),
      allPlayers: <Player>[],
      sessionPlayers: <Player>[],
    );
    expect(player.name, 'lea@exemple.fr');
  });

  test('falls back to the HelloAsso label without name or email', () {
    final player = service.attachRegistrant(
      registrant: registrant(firstName: ' ', lastName: ' ', email: ''),
      allPlayers: <Player>[],
      sessionPlayers: <Player>[],
    );
    expect(player.name, 'Participant HelloAsso');
  });

  test('deduplicates by email regardless of the casing', () {
    final existing = testPlayer(
        id: 'known',
        name: 'Léa T',
        firstName: 'Léa',
        lastName: 'T',
        email: 'lea@exemple.fr');
    final allPlayers = <Player>[existing];
    final sessionPlayers = <Player>[];
    final player = service.attachRegistrant(
      registrant: registrant(email: 'LEA@EXEMPLE.FR'),
      allPlayers: allPlayers,
      sessionPlayers: sessionPlayers,
    );
    expect(player.id, 'known');
    expect(allPlayers, hasLength(1));
    expect(player.name, 'Léa Thomas');
    expect(player.lastName, 'Thomas');
    expect(sessionPlayers, [existing]);
  });

  test('deduplicates by name when there is no email', () {
    final existing = testPlayer(id: 'known', name: 'Léa Thomas', email: '');
    final allPlayers = <Player>[existing];
    final player = service.attachRegistrant(
      registrant: registrant(email: ''),
      allPlayers: allPlayers,
      sessionPlayers: <Player>[],
    );
    expect(player.id, 'known');
    expect(allPlayers, hasLength(1));
  });

  test('never duplicates the player inside the session list', () {
    final existing =
        testPlayer(id: 'known', name: 'Léa Thomas', email: 'lea@exemple.fr');
    final sessionPlayers = <Player>[existing];
    service.attachRegistrant(
      registrant: registrant(),
      allPlayers: <Player>[existing],
      sessionPlayers: sessionPlayers,
    );
    expect(sessionPlayers, hasLength(1));
  });

  test('keeps the existing membership type', () {
    final existing = testPlayer(
        id: 'known',
        name: 'Léa Thomas',
        type: 'membre',
        email: 'lea@exemple.fr');
    final player = service.attachRegistrant(
      registrant: registrant(),
      allPlayers: <Player>[existing],
      sessionPlayers: <Player>[],
    );
    expect(player.type, 'membre');
  });
}
