import 'package:flutter/foundation.dart';

const _dataEnvironmentSuffix = kReleaseMode ? '' : '_dev';
const firebaseOrganizationId = 'default';
const firebaseSnapshotId = kReleaseMode ? 'caisse-main' : 'caisse-dev';
const githubOwner = 'Kaalister';
const githubRepo = 'tilly-app';
const appBuildVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const latestReleaseApi =
    'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
const firebaseSetupGuideUrl =
    'https://github.com/$githubOwner/$githubRepo/blob/main/documentation/FIREBASE_SETUP.md';
const helloAssoSetupGuideUrl =
    'https://github.com/$githubOwner/$githubRepo/blob/main/documentation/MISE_EN_PLACE.md#12-configurer-helloasso';

String databaseFileName(String? userScopeId) {
  if (userScopeId == null) {
    return 'tilly$_dataEnvironmentSuffix.db';
  }
  return 'tilly${_dataEnvironmentSuffix}_$userScopeId.db';
}
