import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../data/local_database.dart';
import '../domain/models.dart';
import 'firebase_bootstrap.dart';

enum FirebaseSyncAction {
  disabled,
  noUser,
  pushed,
  pulled,
  remoteNewer,
  unchanged,
  error
}

class FirebaseSyncResult {
  const FirebaseSyncResult(this.action, this.message, {this.syncedAt});

  final FirebaseSyncAction action;
  final String message;
  final DateTime? syncedAt;
}

class FirebaseSyncService {
  FirebaseSyncService();

  DocumentReference<Map<String, dynamic>> _snapshotRef(User user) =>
      FirebaseBootstrap.firestore
          .collection('organizations')
          .doc(firebaseOrganizationId)
          .collection('users')
          .doc(user.uid)
          .collection('snapshots')
          .doc(firebaseSnapshotId);

  bool get isAvailable =>
      FirebaseBootstrap.initialized && FirebaseBootstrap.currentUser != null;

  Future<bool> hasRemoteSnapshot() async {
    final user = FirebaseBootstrap.currentUser;
    if (!FirebaseBootstrap.initialized || user == null) return false;
    return (await _snapshotRef(user).get()).exists;
  }

  Future<FirebaseSyncResult> synchronize(LocalDatabase database,
      {bool allowPull = false}) async {
    if (!FirebaseBootstrap.initialized) {
      return FirebaseSyncResult(FirebaseSyncAction.disabled,
          FirebaseBootstrap.error ?? 'Firebase non configuré');
    }
    final user = FirebaseBootstrap.currentUser;
    if (user == null) {
      return const FirebaseSyncResult(
          FirebaseSyncAction.noUser, 'Connexion Firebase requise');
    }
    try {
      final snapshotRef = _snapshotRef(user);
      final remote = await snapshotRef.get();
      final localUpdatedAt = await database.loadLocalUpdatedAt();
      if (remote.exists) {
        final data = remote.data() ?? const <String, dynamic>{};
        final remoteUpdatedAt = _remoteUpdatedAt(data);
        var payload =
            Map<String, dynamic>.from(data['payload'] as Map? ?? const {});
        // The whole payload is only re-encoded when the HelloAsso secret must
        // actually be stripped: the previous full jsonEncode comparison cost
        // two serialisations of the entire dataset per sync.
        if (remotePayloadNeedsSanitize(payload)) {
          payload = sanitizePayloadForSync(payload);
          await snapshotRef.update({'payload': payload});
        }
        final shouldPull = payload.isNotEmpty &&
            remoteUpdatedAt != null &&
            (localUpdatedAt == null ||
                remoteUpdatedAt.isAfter(localUpdatedAt) ||
                await database.hasOnlyBootstrapData());
        if (shouldPull) {
          if (!allowPull) {
            return FirebaseSyncResult(FirebaseSyncAction.remoteNewer,
                'Firebase contient des donnees plus recentes. Confirme la restauration pour les recuperer.',
                syncedAt: remoteUpdatedAt);
          }
          await database.replaceFromExport(payload);
          await database.saveSyncMetadata(remoteUpdatedAt);
          return FirebaseSyncResult(
              FirebaseSyncAction.pulled, 'Données Firebase récupérées',
              syncedAt: remoteUpdatedAt);
        }
        if (localUpdatedAt == null ||
            (remoteUpdatedAt != null &&
                !localUpdatedAt.isAfter(remoteUpdatedAt))) {
          final syncedAt = remoteUpdatedAt ?? DateTime.now();
          await database.saveSyncMetadata(syncedAt);
          return FirebaseSyncResult(
              FirebaseSyncAction.unchanged, 'Données déjà synchronisées',
              syncedAt: syncedAt);
        }
      } else if (localUpdatedAt == null) {
        return const FirebaseSyncResult(
            FirebaseSyncAction.unchanged, 'Aucune donnée à synchroniser');
      }

      final payload = await database.exportAll();
      final updatedAt = localUpdatedAt;
      // exportAll already returns a freshly decoded JSON-safe payload.
      await snapshotRef.set({
        'payload': payload,
        'updatedAt': updatedAt.toIso8601String(),
        'updatedAtMillis': updatedAt.millisecondsSinceEpoch,
        'ownerUid': user.uid,
        'updatedBy': user.email ?? user.uid,
      });
      await database.saveSyncMetadata(updatedAt);
      return FirebaseSyncResult(
          FirebaseSyncAction.pushed, 'Données envoyées vers Firebase',
          syncedAt: updatedAt);
    } catch (exception) {
      debugPrint('Firebase sync failed: $exception');
      return FirebaseSyncResult(
          FirebaseSyncAction.error, _friendlySyncError(exception));
    }
  }

  DateTime? _remoteUpdatedAt(Map<String, dynamic> data) {
    final millis = data['updatedAtMillis'];
    if (millis is num) {
      return DateTime.fromMillisecondsSinceEpoch(millis.round());
    }
    return DateTime.tryParse('${data['updatedAt'] ?? ''}');
  }

  static Map<String, dynamic> sanitizePayloadForSync(
          Map<String, dynamic> sourcePayload) =>
      sanitizePortableBackupPayload(sourcePayload);

  /// True when the stored payload still carries a HelloAsso client secret, or
  /// holds unreadable settings, and must therefore be rewritten. This cheap
  /// check replaces a full jsonEncode comparison of both payloads.
  @visibleForTesting
  static bool remotePayloadNeedsSanitize(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map) return false;
    final rows = data['appSettings'];
    if (rows is! List) return false;
    for (final row in rows.whereType<Map>()) {
      if (row['key'] != 'helloasso_settings') continue;
      try {
        final settings = HelloAssoSettings.fromJson(
            Map<String, dynamic>.from(
                jsonDecode('${row['value'] ?? '{}'}') as Map));
        return settings.clientSecret.trim().isNotEmpty;
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  String _friendlySyncError(Object exception) {
    if (exception is FirebaseException &&
        exception.code == 'permission-denied') {
      return 'Accès Firestore refusé. Publie les règles du guide avec le chemin exact organizations/default/users.';
    }
    if (exception is FirebaseException) {
      final detail = exception.message ?? exception.code;
      return 'Synchronisation Firebase impossible (${exception.code}) : ${_shortError(detail)}';
    }
    return 'Synchronisation Firebase impossible : ${_shortError(exception)}';
  }

  String _shortError(Object detail) {
    final text = detail.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 180) return text;
    return '${text.substring(0, 177)}...';
  }
}
