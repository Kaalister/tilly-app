import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.fileName,
    this.size,
    this.sha256,
    this.publishedAt,
  });

  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String fileName;
  final int? size;
  final String? sha256;
  final DateTime? publishedAt;

  String get formattedSize {
    final bytes = size;
    if (bytes == null || bytes <= 0) return '';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  }
}

class AppUpdateResult {
  const AppUpdateResult({
    this.update,
    this.latestVersion,
    this.error,
    this.accessDenied = false,
  });

  final AppUpdateInfo? update;
  final String? latestVersion;
  final String? error;
  final bool accessDenied;

  bool get requiresUpdate => update != null;
}

class AppUpdateService {
  static const _requestTimeout = Duration(seconds: 15);
  static const _nativeClientHeader = 'X-Tilly-Client';

  static bool get supportedPlatform =>
      Platform.isAndroid || Platform.isWindows || Platform.isMacOS;

  static String get platformSlug {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return '';
  }

  static Future<AppUpdateResult> check({
    String? authToken,
    http.Client? client,
  }) async {
    if (!supportedPlatform) {
      return AppUpdateResult(latestVersion: appBuildVersion);
    }
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse(
          '$licenseApiBaseUrl$releasesLatestPath?platform=$platformSlug');
      final response = await httpClient.get(
        uri,
        headers: {
          'Accept': 'application/json',
          _nativeClientHeader: 'native',
          if (authToken != null && authToken.isNotEmpty)
            'Authorization': 'Bearer $authToken',
        },
      ).timeout(_requestTimeout);

      if (response.statusCode == 204) {
        return AppUpdateResult(latestVersion: appBuildVersion);
      }
      if (response.statusCode == 200) {
        return _parseRelease(response.body);
      }
      if (response.statusCode == 401) {
        return const AppUpdateResult(error: 'Session expirée. Reconnecte-toi.');
      }
      if (response.statusCode == 403) {
        return AppUpdateResult(
          error: _serverMessage(response) ??
              'Ton compte ne donne pas accès à la mise à jour.',
          accessDenied: true,
        );
      }
      if (response.statusCode == 404) {
        return const AppUpdateResult(
            error: 'Aucune version publiée pour cette plateforme.');
      }
      if (response.statusCode == 429) {
        return const AppUpdateResult(
            error: 'Trop de vérifications. Réessaie dans quelques minutes.');
      }
      return AppUpdateResult(
          error: 'Vérification impossible (serveur ${response.statusCode}).');
    } on http.ClientException {
      return const AppUpdateResult(
          error: 'Impossible de joindre le serveur de mise à jour.');
    } on SocketException {
      return const AppUpdateResult(
          error: 'Impossible de joindre le serveur de mise à jour.');
    } on FormatException {
      return const AppUpdateResult(error: 'Réponse de mise à jour invalide.');
    } catch (error) {
      return AppUpdateResult(error: 'Vérification impossible : $error');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static AppUpdateResult _parseRelease(String body) {
    final decoded = jsonDecode(body);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) {
      return const AppUpdateResult(
          error: 'Aucune version publiée pour cette plateforme.');
    }
    final release = Map<String, dynamic>.from(data);
    final version = _cleanVersion('${release['version'] ?? ''}');
    if (version.isEmpty) {
      return const AppUpdateResult(error: 'Réponse de mise à jour invalide.');
    }
    if (_compareVersions(version, appBuildVersion) <= 0) {
      return AppUpdateResult(latestVersion: version);
    }
    final downloadPath = '${release['downloadUrl'] ?? ''}'.trim();
    final fileName = '${release['fileName'] ?? ''}'.trim();
    if (downloadPath.isEmpty || fileName.isEmpty) {
      return const AppUpdateResult(
          error: 'Fichier de mise à jour introuvable.');
    }
    final base = Uri.parse(licenseApiBaseUrl);
    final sha256 = '${release['sha256'] ?? ''}'.trim();
    return AppUpdateResult(
      latestVersion: version,
      update: AppUpdateInfo(
        latestVersion: version,
        currentVersion: appBuildVersion,
        downloadUrl: base.resolve(downloadPath).toString(),
        fileName: fileName,
        size: (release['size'] as num?)?.round(),
        sha256: sha256.isEmpty ? null : sha256.toLowerCase(),
        publishedAt: DateTime.tryParse('${release['publishedAt'] ?? ''}'),
      ),
    );
  }

  static String? _serverMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final detail = '${decoded['detail'] ?? decoded['title'] ?? ''}'.trim();
        if (detail.isNotEmpty) return detail;
      }
    } catch (_) {}
    return null;
  }
}

String _cleanVersion(String value) {
  return value.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
}

int _compareVersions(String a, String b) {
  final left = _versionParts(a);
  final right = _versionParts(b);
  final length = max(left.length, right.length);
  for (var index = 0; index < length; index++) {
    final leftPart = index < left.length ? left[index] : 0;
    final rightPart = index < right.length ? right[index] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

List<int> _versionParts(String version) {
  return _cleanVersion(version)
      .split('-')
      .first
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}
