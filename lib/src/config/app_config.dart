import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const _dataEnvironmentSuffix = kReleaseMode ? '' : '_dev';
const _androidEmulatorHost = '10.0.2.2';
const firebaseOrganizationId = 'default';
const firebaseSnapshotId = kReleaseMode ? 'caisse-main' : 'caisse-dev';
const githubOwner = 'Kaalister';
const githubRepo = 'tilly-app';
const appBuildVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const latestReleaseApi =
    'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
const githubReleasesUrl =
    'https://github.com/$githubOwner/$githubRepo/releases';
const firebaseSetupGuideUrl =
    'https://github.com/$githubOwner/$githubRepo/blob/main/documentation/FIREBASE_SETUP.md';
const helloAssoSetupGuideUrl =
    'https://github.com/$githubOwner/$githubRepo/blob/main/documentation/MISE_EN_PLACE.md#13-configurer-helloasso';

const _defaultLicenseApiBaseUrl = kReleaseMode
    ? 'https://tilly.orceus.fr'
    : 'http://localhost:3000';

String get licenseApiBaseUrl => _resolveAndroidLocalhost(_configuredLicenseApiBaseUrl);

String get _configuredLicenseApiBaseUrl {
  if (dotenv.isInitialized) {
    final configured = dotenv.maybeGet('LICENSE_API_URL')?.trim() ?? '';
    if (configured.isNotEmpty) return configured;
  }
  return _defaultLicenseApiBaseUrl;
}

String _resolveAndroidLocalhost(String url) {
  if (kReleaseMode || !Platform.isAndroid) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (uri.host != 'localhost' && uri.host != '127.0.0.1') return url;
  // On the Android emulator, the host machine is reachable at 10.0.2.2.
  return uri.replace(host: _androidEmulatorHost).toString();
}

const licenseApiVersion = 'v1';
const licenseApiPath = '/api/$licenseApiVersion';
const licenseAuthLoginPath = '$licenseApiPath/auth/login';
const licenseAuthSessionPath = '$licenseApiPath/auth/session';
const licenseAuthLogoutPath = '$licenseApiPath/auth/logout';
const licenseActivatePath = '$licenseApiPath/license/activate';
const licenseValidatePath = '$licenseApiPath/license/validate';
const licenseStatusPath = '$licenseApiPath/license/status';

const licenseClientHeader = 'X-Tilly-Client';
const licenseClientValue = 'native';
const licenseAccountUrl = 'https://tilly.orceus.fr/compte';
const licensePublicKeyK1 = 'EKTtIkepcqat2Vezz2GkdoMS3wjlgy_HLGdowe21NQs';
const licenseSupportedKids = {'k1': licensePublicKeyK1};

String databaseFileName(String? userScopeId) {
  if (userScopeId == null) {
    return 'tilly$_dataEnvironmentSuffix.db';
  }
  return 'tilly${_dataEnvironmentSuffix}_$userScopeId.db';
}