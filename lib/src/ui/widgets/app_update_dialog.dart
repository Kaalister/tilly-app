import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/app_controller.dart';
import '../../platform/backup_and_links.dart';
import '../../services/app_update_downloader.dart';
import '../../services/app_update_service.dart';
import '../theme.dart';

Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppUpdateInfo update,
  required AppController controller,
  String? authToken,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppUpdateDialog(
      update: update,
      controller: controller,
      authToken: authToken,
    ),
  );
}

enum _UpdatePhase { ready, downloading, downloaded, launching }

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    required this.update,
    required this.controller,
    this.authToken,
    super.key,
  });

  final AppUpdateInfo update;
  final AppController controller;
  final String? authToken;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  var _phase = _UpdatePhase.ready;
  double? _progress;
  String? _backupName;
  String? _error;
  File? _file;

  AppUpdateInfo get update => widget.update;

  @override
  void initState() {
    super.initState();
    _lookForExistingDownload();
  }

  Future<void> _lookForExistingDownload() async {
    final existing = await AppUpdateDownloader.existingFile(update);
    if (!mounted || existing == null) return;
    final expected = update.sha256;
    if (expected != null &&
        !await AppUpdateDownloader.matchesSha256(existing, expected)) {
      await existing.delete();
      return;
    }
    setState(() {
      _file = existing;
      _phase = _UpdatePhase.downloaded;
    });
  }

  Future<void> _download() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = null;
      _error = null;
    });
    try {
      if (_backupName == null) {
        final backup =
            await saveRecoveryBackup(widget.controller, 'mise-a-jour');
        _backupName = backup['name'];
      }
      final file = await AppUpdateDownloader.download(
        update,
        authToken: widget.authToken,
        onProgress: (received, total) {
          if (!mounted || total == null || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _phase = _UpdatePhase.downloaded;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.ready;
        _error = error.message ?? 'Téléchargement impossible.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.ready;
        _error = _friendlyDownloadError(error);
      });
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _phase = _UpdatePhase.launching;
      _error = null;
    });
    try {
      await installUpdateFile(file);
      if (!mounted) return;
      Navigator.pop(context);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.downloaded;
        _error = error.message ?? 'Installation impossible.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.downloaded;
        _error = 'Installation impossible : $error';
      });
    }
  }

  String _friendlyDownloadError(Object error) {
    final message = '$error'
        .replaceFirst('HttpException: ', '')
        .replaceFirst('FormatException: ', '');
    return 'Téléchargement impossible : $message';
  }

  String get _installLabel {
    if (Platform.isAndroid) return 'Installer maintenant';
    if (Platform.isMacOS) return 'Ouvrir le DMG';
    if (Platform.isWindows) return 'Lancer l\'installation';
    return 'Installer';
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _UpdatePhase.downloading ||
        _phase == _UpdatePhase.launching;
    return AlertDialog(
      title: const Text('Mise à jour disponible'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Installée', value: update.currentVersion),
            const SizedBox(height: 4),
            _InfoRow(label: 'Disponible', value: update.latestVersion),
            if (update.size != null) ...[
              const SizedBox(height: 4),
              _InfoRow(label: 'Taille', value: update.formattedSize),
            ],
            if (update.publishedAt != null) ...[
              const SizedBox(height: 4),
              _InfoRow(
                label: 'Publiée le',
                value: _dateLabel(update.publishedAt!),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Tes données et ta connexion restent intactes. Une copie de '
              'sécurité est créée avant le téléchargement.',
              style: TextStyle(color: AppColors.muted, height: 1.35),
            ),
            if (_phase == _UpdatePhase.downloading) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                _progress == null
                    ? 'Téléchargement en cours...'
                    : 'Téléchargement ${(_progress! * 100).round()} %',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
            if (_phase == _UpdatePhase.downloaded) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _backupName == null
                          ? 'Fichier téléchargé et vérifié.'
                          : 'Fichier téléchargé et vérifié. Copie : $_backupName',
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
            if (_phase == _UpdatePhase.launching) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, height: 1.35),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Plus tard'),
        ),
        if (_phase == _UpdatePhase.downloaded)
          FilledButton.icon(
            onPressed: busy ? null : _install,
            icon: const Icon(Icons.system_update),
            label: Text(_installLabel),
          )
        else
          FilledButton.icon(
            onPressed: busy ? null : _download,
            icon: const Icon(Icons.download),
            label: Text(_error == null ? 'Télécharger' : 'Réessayer'),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

String _dateLabel(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
