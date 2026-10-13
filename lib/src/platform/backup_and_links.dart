import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../controllers/app_controller.dart';

Future<void> copyBackup(BuildContext context, AppController controller) async {
  try {
    final payload = await controller.fullBackupPayload();
    final content = const JsonEncoder.withIndent('  ').convert(payload);
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final fileName = 'tilly-export-$timestamp.tilly';
    final savedFile = await _saveBackupFile(fileName, content);
    final name = savedFile['name'] ?? fileName;
    if (context.mounted) {
      snack(context, 'Export enregistré dans Downloads : $name');
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      snack(context, 'Export impossible : ${error.message ?? error.code}');
    }
  } catch (error) {
    if (context.mounted) snack(context, 'Export impossible : $error');
  }
}

Future<Map<String, String>> saveRecoveryBackup(
    AppController controller, String operation) async {
  final payload =
      await controller.fullBackupPayload(includeConfiguration: true);
  final content = const JsonEncoder.withIndent('  ').convert(payload);
  final timestamp =
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  return _saveBackupFile('tilly-avant-$operation-$timestamp.tilly', content);
}

const fileImportChannel = MethodChannel('tilly/file_import');

Future<Map<String, String>> _saveBackupFile(
    String fileName, String content) async {
  if (Platform.isAndroid) {
    final savedFile = await fileImportChannel.invokeMapMethod<String, String>(
      'saveBackup',
      {'name': fileName, 'content': content},
    );
    return savedFile ?? {'name': fileName};
  }

  final downloads = await getDownloadsDirectory();
  final directory = downloads ?? Directory.current;
  final safeName = _safeBackupFileName(fileName);
  final file = File(path.join(directory.path, safeName));
  await file.writeAsString(content, encoding: utf8, flush: true);
  return {'name': safeName, 'path': file.path};
}

String _safeBackupFileName(String name) {
  final baseName = name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  final safe = baseName.isEmpty ? 'tilly-export.tilly' : baseName;
  return safe.toLowerCase().endsWith('.tilly') ? safe : '$safe.tilly';
}

Future<void> installUpdateFile(File file) async {
  if (!await file.exists()) {
    throw const FileSystemException('Fichier de mise à jour introuvable');
  }

  if (Platform.isAndroid) {
    await fileImportChannel
        .invokeMethod('installApk', {'path': file.path});
    return;
  }

  if (Platform.isMacOS) {
    await Process.run('open', [file.path]);
    return;
  }

  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', file.path]);
    return;
  }

  throw UnsupportedError('Installation non supportée sur cette plateforme');
}

Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    throw const FormatException('Lien de mise à jour invalide');
  }

  if (Platform.isAndroid) {
    await fileImportChannel.invokeMethod('openUrl', {'url': url});
    return;
  }

  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', url]);
    return;
  }

  if (Platform.isMacOS) {
    await Process.run('open', [url]);
    return;
  }

  if (Platform.isLinux) {
    await Process.run('xdg-open', [url]);
    return;
  }

  throw UnsupportedError('Ouverture du lien non supportée');
}

Future<void> importBackupFromFile(
    BuildContext context, AppController controller) async {
  try {
    final file = await _pickBackupFile();
    if (file == null) return;

    final content = _stripUtf8Bom(file['content']);
    final name = file['name'] ?? 'sauvegarde.tilly';
    if (content == null || content.trim().isEmpty) {
      throw const FormatException('Fichier vide ou illisible');
    }

    final payload = jsonDecode(content);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Format de sauvegarde invalide');
    }
    if (!context.mounted) return;
    final data = payload['data'];
    final includesConfiguration = (data is Map && data['appSettings'] is List) ||
        payload['state'] is Map;
    final message = includesConfiguration
        ? 'Restaurer $name ? Toutes les données seront remplacées, y compris la configuration contenue dans cette ancienne sauvegarde.'
        : 'Restaurer $name ? Toutes les données seront remplacées. La configuration de cet appareil (synchronisation, HelloAsso, personnalisation) restera inchangée.';
    final ok = await confirm(context, message);
    if (!ok) return;
    final recoveryFile = await saveRecoveryBackup(controller, 'restauration');
    await controller.importBackup(payload);
    if (context.mounted) {
      snack(context,
          'Sauvegarde restaurée. Copie précédente : ${recoveryFile['name']}');
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      snack(context, 'Import impossible : ${error.message ?? error.code}');
    }
  } catch (error) {
    if (context.mounted) snack(context, 'Import impossible : $error');
  }
}

Future<Map<String, String>?> _pickBackupFile() async {
  if (Platform.isAndroid) {
    return fileImportChannel.invokeMapMethod<String, String>('pickBackup');
  }

  if (Platform.isWindows) {
    return _pickBackupFileWindows();
  }

  if (Platform.isMacOS) {
    return _pickBackupFileMacOS();
  }

  throw UnsupportedError(
      'Import de sauvegarde non supporté sur cette plateforme');
}

Future<Map<String, String>?> _pickBackupFileMacOS() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['tilly', 'json'],
    allowMultiple: false,
  );
  final selectedPath = result?.files.single.path;
  if (selectedPath == null || selectedPath.trim().isEmpty) return null;

  final file = File(selectedPath);
  final content = await file.readAsString(encoding: utf8);
  return {'name': path.basename(file.path), 'content': content};
}

Future<Map<String, String>?> _pickBackupFileWindows() async {
  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Choisir une sauvegarde Tilly'
$dialog.Filter = 'Sauvegardes Tilly (*.tilly;*.json)|*.tilly;*.json|Tous les fichiers (*.*)|*.*'
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $dialog.FileName
}
''';

  final result = await Process.run(
    'powershell.exe',
    ['-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-Command', script],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    final message = '${result.stderr}'.trim();
    throw PlatformException(
      code: 'picker_unavailable',
      message: message.isEmpty
          ? 'Impossible d\'ouvrir le sélecteur de fichier.'
          : message,
    );
  }

  final selectedPath = _lastNonEmptyLine('${result.stdout}');
  if (selectedPath == null) return null;

  final file = File(selectedPath);
  final content = await file.readAsString(encoding: utf8);
  return {'name': path.basename(file.path), 'content': content};
}

String? _stripUtf8Bom(String? content) {
  if (content == null) return null;
  return content.startsWith('\uFEFF') ? content.substring(1) : content;
}

String? _lastNonEmptyLine(String value) {
  String? last;
  for (final line in value.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) last = trimmed;
  }
  return last;
}

Future<bool> confirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmation'),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmer')),
          ],
        ),
      ) ??
      false;
  await Future<void>.delayed(kThemeAnimationDuration);
  return result;
}

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
