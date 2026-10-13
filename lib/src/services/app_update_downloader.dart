import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_update_service.dart';

class AppUpdateDownloader {
  static const _connectTimeout = Duration(seconds: 30);
  static const _nativeClientHeader = 'X-Tilly-Client';

  static Future<Directory> updatesDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(path.join(support.path, 'Tilly', 'updates'));
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> fileFor(AppUpdateInfo info) async {
    final directory = await updatesDirectory();
    return File(path.join(directory.path, info.fileName));
  }

  static Future<File?> existingFile(AppUpdateInfo info) async {
    final file = await fileFor(info);
    return await file.exists() ? file : null;
  }

  static Future<bool> matchesSha256(File file, String expected) async {
    if (!await file.exists()) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expected.toLowerCase();
  }

  static Future<File> download(
    AppUpdateInfo info, {
    String? authToken,
    void Function(int received, int? total)? onProgress,
    http.Client? client,
  }) async {
    final file = await fileFor(info);
    if (await file.exists()) await file.delete();

    final httpClient = client ?? http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl))
        ..headers['Accept'] = 'application/octet-stream'
        ..headers[_nativeClientHeader] = 'native';
      if (authToken != null && authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      final response = await httpClient.send(request).timeout(_connectTimeout);
      if (response.statusCode != 200) {
        throw HttpException(
            'Téléchargement refusé (${response.statusCode})', uri: request.url);
      }

      final total = response.contentLength ?? info.size;
      sink = file.openWrite();
      final digest = _DigestSink();
      final hashInput = sha256.startChunkedConversion(digest);
      var received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        hashInput.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }

      hashInput.close();
      await sink.flush();
      await sink.close();
      sink = null;

      final expected = info.sha256;
      final computed = digest.value?.toString().toLowerCase();
      if (expected != null && computed != null && computed != expected) {
        await file.delete();
        throw const FormatException('Le fichier téléchargé est corrompu.');
      }
      return file;
    } catch (_) {
      await sink?.close();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      if (client == null) httpClient.close();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
