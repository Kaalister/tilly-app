import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../controllers/app_controller.dart';
import '../domain/models.dart';
import '../platform/backup_and_links.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firebase_sync_service.dart';
import '../utils/iterable_extensions.dart';
import 'theme.dart';
import 'widgets/common_widgets.dart';
import 'widgets/tiko_tutorial.dart';

const helloAssoConnectionFailedMessage =
    'Connexion HelloAsso impossible. Vérifie la configuration et réessaie.';

Future<void> showPlayerDialog(BuildContext context, AppController controller,
    {Player? player}) async {
  final existingPlayers = player == null
      ? controller.allPlayers
          .where((candidate) =>
              !controller.players.any((current) => current.id == candidate.id))
          .toList()
      : <Player>[];
  final result = await showDialog<_PlayerDialogResult>(
    context: context,
    builder: (context) => _PlayerDialog(
      player: player,
      existingPlayers: existingPlayers,
    ),
  );

  if (result == null) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  if (result.delete && player != null) {
    if (!await confirm(context, 'Supprimer ${player.name} ?')) return;
    await controller.removePlayer(player);
    return;
  }
  if (!result.hasInput) return;
  if (player == null) {
    await controller.addPlayer(
      firstName: result.firstName,
      lastName: result.lastName,
      email: result.email,
      type: result.type,
    );
  } else {
    await controller.updatePlayer(
      player,
      firstName: result.firstName,
      lastName: result.lastName,
      email: result.email,
      type: result.type,
    );
  }
}

class _PlayerDialogResult {
  const _PlayerDialogResult.save({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.type,
  }) : delete = false;

  const _PlayerDialogResult.delete()
      : firstName = '',
        lastName = '',
        email = '',
        type = 'public',
        delete = true;

  final String firstName;
  final String lastName;
  final String email;
  final String type;
  final bool delete;

  bool get hasInput =>
      firstName.trim().isNotEmpty ||
      lastName.trim().isNotEmpty ||
      email.trim().isNotEmpty;
}

class _PlayerDialog extends StatefulWidget {
  const _PlayerDialog({
    required this.player,
    required this.existingPlayers,
  });

  final Player? player;
  final List<Player> existingPlayers;

  @override
  State<_PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<_PlayerDialog> {
  late final TextEditingController firstName;
  late final TextEditingController lastName;
  late final TextEditingController email;
  late String type;
  String? selectedExistingId;

  @override
  void initState() {
    super.initState();
    final player = widget.player;
    final splitName = player == null
        ? (firstName: '', lastName: '')
        : splitPlayerName(player.firstName.isEmpty && player.lastName.isEmpty
            ? player.name
            : '${player.firstName} ${player.lastName}');
    firstName = TextEditingController(
        text: player?.firstName.isNotEmpty == true
            ? player!.firstName
            : splitName.firstName);
    lastName = TextEditingController(
        text: player?.lastName.isNotEmpty == true
            ? player!.lastName
            : splitName.lastName);
    email = TextEditingController(text: player?.email ?? '');
    type = player?.type ?? 'public';
  }

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return AlertDialog(
      title:
          Text(player == null ? 'Nouveau participant' : 'Modifier participant'),
      content: SizedBox(
        width: min(MediaQuery.sizeOf(context).width - 48, 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.existingPlayers.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedExistingId,
                  decoration:
                      const InputDecoration(labelText: 'Participant existant'),
                  hint: const Text('Sélectionner un ancien participant'),
                  items: [
                    for (final existing in widget.existingPlayers)
                      DropdownMenuItem(
                        value: existing.id,
                        child: Text(existing.name,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _selectExistingPlayer,
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: firstName,
                          autofocus: true,
                          decoration:
                              const InputDecoration(labelText: 'Prénom'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: lastName,
                          decoration: const InputDecoration(labelText: 'Nom'))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'public',
                      label: Text('Public'),
                      icon: Icon(Icons.person)),
                  ButtonSegment(
                      value: 'membre',
                      label: Text('Adhérent'),
                      icon: Icon(Icons.verified_user)),
                ],
                selected: {type},
                onSelectionChanged: (value) =>
                    setState(() => type = value.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (player != null)
          TextButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context, const _PlayerDialogResult.delete());
              },
              child: const Text('Supprimer')),
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context, _saveResult());
            },
            child: const Text('Enregistrer')),
      ],
    );
  }

  void _selectExistingPlayer(String? value) {
    final existing = widget.existingPlayers
        .where((candidate) => candidate.id == value)
        .firstOrNull;
    if (existing == null) return;
    setState(() {
      selectedExistingId = existing.id;
      final parts = splitPlayerName(
          existing.firstName.isEmpty && existing.lastName.isEmpty
              ? existing.name
              : '${existing.firstName} ${existing.lastName}');
      firstName.text =
          existing.firstName.isNotEmpty ? existing.firstName : parts.firstName;
      lastName.text =
          existing.lastName.isNotEmpty ? existing.lastName : parts.lastName;
      email.text = existing.email;
      type = existing.type;
    });
  }

  _PlayerDialogResult _saveResult() {
    return _PlayerDialogResult.save(
      firstName: firstName.text,
      lastName: lastName.text,
      email: email.text,
      type: type,
    );
  }
}

Future<void> showCreateSessionDialog(
    BuildContext context, AppController controller) async {
  final result = await showDialog<_CreateSessionDialogResult>(
    context: context,
    builder: (context) => _CreateSessionDialog(controller: controller),
  );
  if (result == null) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  try {
    await controller.createSession(result.name,
        helloassoEvent:
            result.selectedEventEnabled ? result.selectedEvent : null);
    if (context.mounted) {
      snack(
          context,
          result.selectedEvent == null
              ? 'Nouvelle session active'
              : 'Session créée avec participants HelloAsso');
    }
  } catch (error) {
    if (context.mounted) {
      snack(
          context,
          result.selectedEventEnabled
              ? helloAssoConnectionFailedMessage
              : 'Création impossible : $error');
    }
  }
}

class _CreateSessionDialogResult {
  const _CreateSessionDialogResult({
    required this.name,
    required this.selectedEventEnabled,
    required this.selectedEvent,
  });

  final String name;
  final bool selectedEventEnabled;
  final HelloAssoEvent? selectedEvent;
}

class _CreateSessionDialog extends StatefulWidget {
  const _CreateSessionDialog({required this.controller});

  final AppController controller;

  @override
  State<_CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<_CreateSessionDialog> {
  late final TextEditingController field;
  var loadingEvents = false;
  var helloAssoError = '';
  var selectedEventEnabled = false;
  HelloAssoEvent? selectedEvent;
  var events = <HelloAssoEvent>[];

  @override
  void initState() {
    super.initState();
    field = TextEditingController(
        text: 'Événement ${dateLabel(DateTime.now())}');
    loadingEvents = widget.controller.helloAssoSettings.isConfigured;
    if (loadingEvents) _fetchEvents();
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  Future<void> _fetchEvents() async {
    try {
      final loaded = await widget.controller.fetchHelloAssoEvents();
      if (!mounted) return;
      setState(() {
        events = loaded;
        loadingEvents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        helloAssoError =
            'Connexion impossible. Tu peux continuer sans liaison.';
        loadingEvents = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final helloAssoConfigured =
        widget.controller.helloAssoSettings.isConfigured;
    return AlertDialog(
      title: const Text('Nouvelle session'),
      content: SizedBox(
        width: min(MediaQuery.sizeOf(context).width - 48, 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: field,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'Nom de l\'événement')),
            if (helloAssoConfigured) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: selectedEventEnabled,
                onChanged: events.isEmpty
                    ? null
                    : (value) => setState(() => selectedEventEnabled = value),
                title: const Text('Lier un événement HelloAsso'),
              ),
              if (loadingEvents) const LinearProgressIndicator(),
              if (helloAssoError.isNotEmpty)
                Text('HelloAsso : $helloAssoError',
                    style: const TextStyle(color: AppColors.warn)),
              if (selectedEventEnabled)
                DropdownButtonFormField<HelloAssoEvent>(
                  isExpanded: true,
                  initialValue: selectedEvent,
                  decoration: const InputDecoration(labelText: 'Événement'),
                  items: [
                    for (final event in events)
                      DropdownMenuItem(
                          value: event,
                          child: Text(event.name,
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (event) => setState(() {
                    selectedEvent = event;
                    if (event != null) field.text = event.name;
                  }),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(
                context,
                _CreateSessionDialogResult(
                  name: field.text,
                  selectedEventEnabled: selectedEventEnabled,
                  selectedEvent: selectedEvent,
                ),
              );
            },
            child: const Text('Créer')),
      ],
    );
  }
}

Future<void> showFirebaseSetupDialog(
    BuildContext context, AppController controller,
    {bool editProject = false}) async {
  final result = await showDialog<FirebaseSyncResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FirebaseSetupDialog(
      controller: controller,
      editProject: editProject,
    ),
  );
  if (result != null && context.mounted) snack(context, result.message);
}

Future<void> showFirebaseHelpDialog(BuildContext context) async {
  final openGuide = await showDialog<bool>(
    context: context,
    builder: (context) => TikoTutorialDialog(
      content: tikoFirebaseHelpTutorial(),
      primaryActionLabel: 'Ouvrir le tutoriel',
    ),
  );

  if (openGuide != true || !context.mounted) return;
  try {
    await openExternalUrl(firebaseSetupGuideUrl);
  } catch (error) {
    if (context.mounted) {
      snack(context, 'Impossible d’ouvrir le tutoriel : $error');
    }
  }
}

Future<void> showHelloAssoHelpDialog(BuildContext context,
    {bool mealsEnabled = true}) async {
  final openGuide = await showDialog<bool>(
    context: context,
    builder: (context) => TikoTutorialDialog(
      content: tikoHelloAssoHelpTutorial(mealsEnabled: mealsEnabled),
      primaryActionLabel: 'Ouvrir le tutoriel',
    ),
  );

  if (openGuide != true || !context.mounted) return;
  try {
    await openExternalUrl(helloAssoSetupGuideUrl);
  } catch (error) {
    if (context.mounted) {
      snack(context, 'Impossible d’ouvrir le tutoriel : $error');
    }
  }
}

class _FirebaseSetupDialog extends StatefulWidget {
  const _FirebaseSetupDialog({
    required this.controller,
    required this.editProject,
  });

  final AppController controller;
  final bool editProject;

  @override
  State<_FirebaseSetupDialog> createState() => _FirebaseSetupDialogState();
}

class _FirebaseSetupDialogState extends State<_FirebaseSetupDialog> {
  final configuration = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  late final TextEditingController apiKey;
  late final TextEditingController appId;
  late final TextEditingController messagingSenderId;
  late final TextEditingController projectId;
  late final TextEditingController authDomain;
  late final TextEditingController storageBucket;
  late final TextEditingController measurementId;
  late final TextEditingController iosBundleId;
  late FirebaseSettings settings;
  late bool editingProject;
  bool manualEntry = false;
  bool obscurePassword = true;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    settings = widget.controller.firebaseSettings;
    editingProject = widget.editProject || !settings.isConfigured;
    apiKey = TextEditingController(text: settings.apiKey);
    appId = TextEditingController(text: settings.appId);
    messagingSenderId = TextEditingController(text: settings.messagingSenderId);
    projectId = TextEditingController(text: settings.projectId);
    authDomain = TextEditingController(text: settings.authDomain);
    storageBucket = TextEditingController(text: settings.storageBucket);
    measurementId = TextEditingController(text: settings.measurementId);
    iosBundleId = TextEditingController(text: settings.iosBundleId);
  }

  @override
  void dispose() {
    configuration.dispose();
    email.dispose();
    password.dispose();
    apiKey.dispose();
    appId.dispose();
    messagingSenderId.dispose();
    projectId.dispose();
    authDomain.dispose();
    storageBucket.dispose();
    measurementId.dispose();
    iosBundleId.dispose();
    super.dispose();
  }

  FirebaseSettings _enteredSettings() {
    if (!manualEntry) return parseFirebaseSettings(configuration.text);
    return FirebaseSettings(
      apiKey: apiKey.text,
      appId: appId.text,
      messagingSenderId: messagingSenderId.text,
      projectId: projectId.text,
      authDomain: authDomain.text,
      storageBucket: storageBucket.text,
      measurementId: measurementId.text,
      iosBundleId: iosBundleId.text,
    );
  }

  Future<void> _activate() async {
    if (loading) return;
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Renseigne l’email et le mot de passe du compte.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (editingProject) {
        final enteredSettings = _enteredSettings();
        await widget.controller.saveFirebaseSettings(enteredSettings);
        settings = enteredSettings;
        editingProject = false;
      }
      await FirebaseBootstrap.auth.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
      final result = await widget.controller.connectFirebaseUser();
      if (mounted) Navigator.pop(context, result);
    } on FirebaseAuthException catch (exception) {
      if (mounted) setState(() => error = _firebaseAuthError(exception));
    } catch (exception) {
      if (mounted) {
        setState(() => error = '$exception'
            .replaceFirst('Bad state: ', '')
            .replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Activer la synchronisation'),
      content: SizedBox(
        width: min(MediaQuery.sizeOf(context).width - 48, 620),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editingProject) ...[
                const Text('1. Projet Firebase',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (!manualEntry)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: configuration,
                        minLines: 5,
                        maxLines: 9,
                        decoration: const InputDecoration(
                          labelText: 'Configuration à coller',
                          alignLabelWithHint: true,
                          hintText:
                              'firebaseConfig, google-services.json ou GoogleService-Info.plist',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : _pasteConfiguration,
                          icon: const Icon(Icons.content_paste),
                          label: const Text('Coller'),
                        ),
                      ),
                    ],
                  )
                else
                  _buildManualFields(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: loading
                        ? null
                        : () => setState(() => manualEntry = !manualEntry),
                    icon: Icon(manualEntry ? Icons.content_paste : Icons.tune),
                    label: Text(manualEntry
                        ? 'Revenir au collage'
                        : 'Options avancées'),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    const Icon(Icons.cloud_done, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Projet ${settings.projectId}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => setState(() => editingProject = true),
                      child: const Text('Changer'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Text(
                  editingProject
                      ? '2. Compte utilisateur'
                      : 'Compte utilisateur',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: obscurePassword,
                onSubmitted: (_) => _activate(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    tooltip: obscurePassword ? 'Afficher' : 'Masquer',
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                    icon: Icon(obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: loading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: loading ? null : _activate,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_done),
          label: const Text('Activer'),
        ),
      ],
    );
  }

  Widget _buildManualFields() {
    return Column(
      children: [
        TextField(
            controller: apiKey,
            decoration: const InputDecoration(labelText: 'API key *')),
        const SizedBox(height: 8),
        TextField(
            controller: appId,
            decoration: const InputDecoration(labelText: 'App ID *')),
        const SizedBox(height: 8),
        TextField(
            controller: messagingSenderId,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Messaging sender ID *')),
        const SizedBox(height: 8),
        TextField(
            controller: projectId,
            decoration: const InputDecoration(labelText: 'Project ID *')),
        const SizedBox(height: 8),
        TextField(
            controller: authDomain,
            decoration:
                const InputDecoration(labelText: 'Auth domain (optionnel)')),
        const SizedBox(height: 8),
        TextField(
            controller: storageBucket,
            decoration:
                const InputDecoration(labelText: 'Storage bucket (optionnel)')),
        const SizedBox(height: 8),
        TextField(
            controller: measurementId,
            decoration:
                const InputDecoration(labelText: 'Measurement ID (optionnel)')),
        const SizedBox(height: 8),
        TextField(
            controller: iosBundleId,
            decoration: const InputDecoration(
                labelText: 'Bundle ID Apple (optionnel)')),
      ],
    );
  }

  Future<void> _pasteConfiguration() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) setState(() => error = 'Le presse-papiers est vide.');
      return;
    }
    configuration.text = text;
    if (mounted) setState(() => error = null);
  }
}

String _firebaseAuthError(FirebaseAuthException exception) {
  switch (exception.code) {
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      return 'Email ou mot de passe incorrect.';
    case 'invalid-email':
      return 'Adresse email invalide.';
    case 'network-request-failed':
      return 'Connexion réseau impossible.';
    case 'too-many-requests':
      return 'Trop de tentatives. Réessaie plus tard.';
    default:
      return exception.message ?? exception.code;
  }
}

Future<void> showHelloAssoSettingsDialog(
    BuildContext context, AppController controller) async {
  final current = controller.helloAssoSettings;
  final settings = await showDialog<HelloAssoSettings>(
    context: context,
    builder: (context) => _HelloAssoSettingsDialog(current: current),
  );
  if (settings == null) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  await controller.saveHelloAssoSettings(settings);
  if (context.mounted) snack(context, 'Configuration HelloAsso enregistrée');
}

class _HelloAssoSettingsDialog extends StatefulWidget {
  const _HelloAssoSettingsDialog({required this.current});

  final HelloAssoSettings current;

  @override
  State<_HelloAssoSettingsDialog> createState() =>
      _HelloAssoSettingsDialogState();
}

class _HelloAssoSettingsDialogState extends State<_HelloAssoSettingsDialog> {
  late final TextEditingController organizationSlug;
  late final TextEditingController clientId;
  late final TextEditingController clientSecret;
  late String environment;
  var showClientSecret = false;

  @override
  void initState() {
    super.initState();
    organizationSlug =
        TextEditingController(text: widget.current.organizationSlug);
    clientId = TextEditingController(text: widget.current.clientId);
    clientSecret = TextEditingController(text: widget.current.clientSecret);
    environment = widget.current.environment;
  }

  @override
  void dispose() {
    organizationSlug.dispose();
    clientId.dispose();
    clientSecret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configuration HelloAsso'),
      content: SizedBox(
        width: min(MediaQuery.sizeOf(context).width - 48, 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: organizationSlug,
                  decoration:
                      const InputDecoration(labelText: 'Organization slug')),
              const SizedBox(height: 10),
              TextField(
                  controller: clientId,
                  decoration: const InputDecoration(labelText: 'Client ID')),
              const SizedBox(height: 10),
              TextField(
                controller: clientSecret,
                obscureText: !showClientSecret,
                decoration: InputDecoration(
                  labelText: 'Client secret',
                  suffixIcon: IconButton(
                    tooltip: showClientSecret
                        ? 'Masquer le secret'
                        : 'Afficher le secret',
                    onPressed: () =>
                        setState(() => showClientSecret = !showClientSecret),
                    icon: Icon(showClientSecret
                        ? Icons.visibility_off
                        : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'production', label: Text('Production')),
                  ButtonSegment(value: 'sandbox', label: Text('Sandbox')),
                ],
                selected: {environment},
                onSelectionChanged: (value) =>
                    setState(() => environment = value.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(
                context,
                HelloAssoSettings(
                  organizationSlug: organizationSlug.text.trim(),
                  clientId: clientId.text.trim(),
                  clientSecret: clientSecret.text.trim(),
                  environment: environment,
                ),
              );
            },
            child: const Text('Enregistrer')),
      ],
    );
  }
}

Future<void> showSessionPicker(
    BuildContext context, AppController controller) async {
  final selected = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Changer de session'),
      content: SizedBox(
        width: 420,
        child: controller.sessions.isEmpty
            ? const Text('Aucune session disponible')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: controller.sessions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final session = controller.sessions[index];
                  final active = controller.activeSession?.id == session.id;
                  return ListTile(
                    leading: Icon(
                        active
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: active ? AppColors.accent : AppColors.muted),
                    title: Text(session.name),
                    subtitle: Text(dateLabel(session.eventDate)),
                    onTap: () => Navigator.pop(context, session.id),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
      ],
    ),
  );
  if (selected != null && selected != controller.activeSession?.id) {
    await Future<void>.delayed(kThemeAnimationDuration);
    if (!context.mounted) return;
    await controller.switchSession(selected);
    if (context.mounted) snack(context, 'Session chargée');
  }
}

Future<void> showCategoryDialog(BuildContext context, AppController controller,
    {String? category}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (context) => _CategoryDialog(
      controller: controller,
      category: category,
    ),
  );
  if (value == null || value == category) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  if (category == null) {
    await controller.addArticleCategory(value);
    if (context.mounted) snack(context, 'Catégorie ajoutée');
  } else {
    await controller.renameArticleCategory(category, value);
    if (context.mounted) snack(context, 'Catégorie modifiée');
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.controller,
    required this.category,
  });

  final AppController controller;
  final String? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController name;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.category ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    return AlertDialog(
      title:
          Text(category == null ? 'Nouvelle catégorie' : 'Modifier catégorie'),
      content: TextField(
        controller: name,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration:
            InputDecoration(labelText: 'Nom de la catégorie', errorText: error),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  void _submit() {
    final normalized = normalizedCategoryName(name.text);
    if (normalized.isEmpty) {
      setState(() => error = 'Saisissez un nom de catégorie');
      return;
    }
    if (widget.controller
        .containsArticleCategory(normalized, except: widget.category)) {
      setState(() => error = 'Cette catégorie existe déjà');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.pop(context, normalized);
  }
}

Future<void> showArticleDialog(BuildContext context, AppController controller,
    {Article? article}) async {
  final categoryOptions = <String>[...controller.managedArticleCategories]
      .map((category) => category.trim().toUpperCase())
      .where((category) => category.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) {
      if (a == 'LOCATION') return 1;
      if (b == 'LOCATION') return -1;
      if (a == 'DIVERS') return 1;
      if (b == 'DIVERS') return -1;
      return a.compareTo(b);
    });
  if (categoryOptions.isEmpty) categoryOptions.add('DIVERS');

  final draft = await showDialog<Article>(
    context: context,
    builder: (context) => _ArticleDialog(
      article: article,
      categoryOptions: categoryOptions,
    ),
  );

  if (draft == null) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  await controller.upsertArticle(draft, replacing: article);
}

class _ArticleDialog extends StatefulWidget {
  const _ArticleDialog({
    required this.article,
    required this.categoryOptions,
  });

  final Article? article;
  final List<String> categoryOptions;

  @override
  State<_ArticleDialog> createState() => _ArticleDialogState();
}

class _ArticleDialogState extends State<_ArticleDialog> {
  late final TextEditingController icon;
  late final TextEditingController name;
  late final TextEditingController price;
  late final TextEditingController memberPrice;
  late final TextEditingController stock;
  late final TextEditingController threshold;
  late String category;
  late String type;

  @override
  void initState() {
    super.initState();
    final article = widget.article;
    icon = TextEditingController(text: article?.icon ?? '📦');
    name = TextEditingController(text: article?.name ?? '');
    price = TextEditingController(text: article?.price.toString() ?? '');
    memberPrice =
        TextEditingController(text: article?.memberPrice.toString() ?? '');
    stock = TextEditingController(text: article?.stock.toString() ?? '0');
    threshold =
        TextEditingController(text: article?.threshold.toString() ?? '5');
    category = (article?.category ?? widget.categoryOptions.first)
        .trim()
        .toUpperCase();
    if (!widget.categoryOptions.contains(category)) {
      widget.categoryOptions.add(category);
    }
    type = article?.type ?? (category == 'LOCATION' ? 'location' : 'standard');
  }

  @override
  void dispose() {
    icon.dispose();
    name.dispose();
    price.dispose();
    memberPrice.dispose();
    stock.dispose();
    threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.article == null ? 'Nouvel article' : 'Modifier article'),
      content: SizedBox(
        width: min(MediaQuery.sizeOf(context).width - 48, 720),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                SizedBox(
                    width: 76,
                    child: TextField(
                        controller: icon,
                        decoration: const InputDecoration(labelText: 'Icône'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Nom'))),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [
                  for (final option in widget.categoryOptions)
                    DropdownMenuItem(
                      value: option,
                      child: Text(option),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => category = value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type d’article'),
                items: const [
                  DropdownMenuItem(
                      value: 'standard', child: Text('Article en stock')),
                  DropdownMenuItem(value: 'location', child: Text('Location')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => type = value);
                },
              ),
              const SizedBox(height: 10),
              TacticalCard(
                borderColor:
                    type == 'location' ? AppColors.sumup : AppColors.border,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Row(
                  children: [
                    Icon(
                        type == 'location'
                            ? Icons.assignment_return
                            : Icons.inventory_2,
                        color: type == 'location'
                            ? AppColors.sumup
                            : AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        type == 'location'
                            ? 'Location : aucune sortie de stock automatique'
                            : 'Type automatique : standard',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: price,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Prix public'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: memberPrice,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Prix adhérent'))),
              ]),
              const SizedBox(height: 10),
              if (type == 'standard')
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: stock,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Stock'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: threshold,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Seuil'))),
                ])
              else
                const Text(
                  'Une location reste facturable mais ne modifie jamais le stock.',
                  style: TextStyle(color: AppColors.muted),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context, _draftArticle());
            },
            child: const Text('Enregistrer')),
      ],
    );
  }

  Article? _draftArticle() {
    final nameValue = name.text.trim();
    if (nameValue.isEmpty) return null;
    return Article(
      id: widget.article?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      category: category,
      type: type,
      icon: icon.text.trim().isEmpty ? '📦' : icon.text.trim(),
      name: nameValue,
      price: double.tryParse(price.text.replaceAll(',', '.')) ?? 0,
      memberPrice: double.tryParse(memberPrice.text.replaceAll(',', '.')) ?? 0,
      stock: type == 'standard' ? int.tryParse(stock.text) ?? 0 : 0,
      threshold: type == 'standard' ? int.tryParse(threshold.text) ?? 0 : 0,
      bbAuto: 0,
      gasAuto: 0,
    );
  }
}

Future<void> showAssociationConsumptionDialog(
    BuildContext context, AppController controller) async {
  final availableArticles =
      controller.articles.where((article) => article.tracksStock).toList();
  if (availableArticles.isEmpty) {
    snack(context, 'Aucun article avec stock disponible');
    return;
  }
  final result = await showDialog<_AssociationConsumptionResult>(
    context: context,
    builder: (context) =>
        _AssociationConsumptionDialog(availableArticles: availableArticles),
  );
  if (result == null) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  final article =
      availableArticles.where((entry) => entry.id == result.articleId).first;
  try {
    await controller.consumeStockForAssociation(
      article,
      result.quantity,
      note: result.note,
    );
    if (context.mounted) snack(context, 'Sortie association enregistrée');
  } on StateError catch (error) {
    if (context.mounted) snack(context, '$error');
  }
}

class _AssociationConsumptionResult {
  const _AssociationConsumptionResult({
    required this.articleId,
    required this.quantity,
    required this.note,
  });

  final String articleId;
  final int quantity;
  final String note;
}

class _AssociationConsumptionDialog extends StatefulWidget {
  const _AssociationConsumptionDialog({required this.availableArticles});

  final List<Article> availableArticles;

  @override
  State<_AssociationConsumptionDialog> createState() =>
      _AssociationConsumptionDialogState();
}

class _AssociationConsumptionDialogState
    extends State<_AssociationConsumptionDialog> {
  late String articleId;
  late final TextEditingController quantity;
  late final TextEditingController note;

  @override
  void initState() {
    super.initState();
    articleId = widget.availableArticles.first.id;
    quantity = TextEditingController(text: '1');
    note = TextEditingController();
  }

  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final article =
        widget.availableArticles.where((entry) => entry.id == articleId).first;
    return AlertDialog(
      title: const Text('Sortie stock association'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Cette sortie n'est ni une vente ni un paiement.",
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: articleId,
            decoration: const InputDecoration(labelText: 'Article'),
            items: [
              for (final entry in widget.availableArticles)
                DropdownMenuItem(
                  value: entry.id,
                  child: Text('${entry.name} (stock ${entry.stock})',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => articleId = value);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: 'Quantité',
                helperText: 'Disponible : ${article.stock}'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Motif (optionnel)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(
                context,
                _AssociationConsumptionResult(
                  articleId: articleId,
                  quantity: int.tryParse(quantity.text.trim()) ?? 0,
                  note: note.text,
                ),
              );
            },
            child: const Text('Valider la sortie')),
      ],
    );
  }
}

Future<void> showCashDialog(
    BuildContext context, AppController controller) async {
  final validate = await showDialog<bool>(
    context: context,
    builder: (context) => _CashDialog(controller: controller),
  );
  if (validate != true) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  try {
    await controller.checkout('ESP');
  } on StateError catch (error) {
    if (context.mounted) snack(context, '$error');
  }
}

class _CashDialog extends StatefulWidget {
  const _CashDialog({required this.controller});

  final AppController controller;

  @override
  State<_CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends State<_CashDialog> {
  final given = TextEditingController();

  @override
  void dispose() {
    given.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paid = double.tryParse(given.text.replaceAll(',', '.')) ?? 0;
    final total = widget.controller.cartTotal;
    final change = max(0.0, paid - total);
    return AlertDialog(
      title: const Text('Rendu monnaie'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricCard(
              label: 'À payer', value: money(total), color: AppColors.accent),
          const SizedBox(height: 10),
          TextField(
            controller: given,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Montant donné'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          if (paid > 0 && paid < total)
            Text('Manque ${money(total - paid)}',
                style: const TextStyle(color: AppColors.danger)),
          if (paid >= total)
            Text(
                change < .01
                    ? 'Compte exact'
                    : 'Rendu: ${money(change)}\n${changeBreakdown(change).join(' · ')}',
                style: const TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w900)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context, false);
            },
            child: const Text('Annuler')),
        FilledButton(
          onPressed: paid >= total && widget.controller.canCheckout
              ? () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context, true);
                }
              : null,
          child: const Text('Valider ESP'),
        ),
      ],
    );
  }
}

List<String> changeBreakdown(double change) {
  var cents = (change * 100).round();
  final chips = <String>[];
  for (final denom in denominations) {
    final value = (denom * 100).round();
    final count = cents ~/ value;
    if (count > 0) {
      chips.add(
          '$count x ${denom >= 1 ? '${denom.round()}€' : '${(denom * 100).round()}c'}');
      cents -= count * value;
    }
  }
  return chips;
}
