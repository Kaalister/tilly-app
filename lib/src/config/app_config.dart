import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const _dataEnvironmentSuffix = kReleaseMode ? '' : '_dev';
const _androidEmulatorHost = '10.0.2.2';
const firebaseOrganizationId = 'default';
const firebaseSnapshotId = kReleaseMode ? 'caisse-main' : 'caisse-dev';
const _devUpdateCheckDefine = String.fromEnvironment('DEV_UPDATE_CHECK');
const _devLicenseDefine = String.fromEnvironment('DEV_LICENSE');
const _devDemoDataDefine = String.fromEnvironment('DEV_DEMO_DATA');
const _devTutorialDefine = String.fromEnvironment('DEV_TUTORIAL');
const compiledAppVersion = String.fromEnvironment('APP_VERSION');
const defaultAppVersion = '1.0.0';
const downloadsPageUrl = 'https://tilly.orceus.fr/telechargements';

/// Version de l'application, affichée et comparée aux versions publiées.
/// Priorité au `--dart-define=APP_VERSION`, sinon résolue au démarrage depuis
/// le binaire par `initializeAppVersion()`, avec repli [defaultAppVersion].
String appBuildVersion = compiledAppVersion.trim().isEmpty
    ? defaultAppVersion
    : compiledAppVersion.trim();

/// Le controle de mise a jour est actif en release, ou en debug avec
/// `DEV_UPDATE_CHECK=true` (`.env.dev` ou `--dart-define`).
bool get updateCheckEnabled {
  if (kReleaseMode) return true;
  if (_devUpdateCheckDefine.trim().toLowerCase() == 'true') return true;
  if (dotenv.isInitialized) {
    return dotenv.maybeGet('DEV_UPDATE_CHECK')?.trim().toLowerCase() == 'true';
  }
  return false;
}

/// Force un etat de licence en debug uniquement (jamais pris en compte en
/// release) : `valid`, `none`, `grace`, `server`, `blocked`, `expired`.
String get devLicenseOverride {
  if (!kDebugMode) return '';
  final defined = _devLicenseDefine.trim();
  if (defined.isNotEmpty) return defined;
  if (dotenv.isInitialized) {
    return dotenv.maybeGet('DEV_LICENSE')?.trim() ?? '';
  }
  return '';
}

/// Remplit la base avec des donnees de demonstration (3 journees) au premier
/// lancement en debug. Jamais actif en release.
bool get demoDataEnabled {
  if (!kDebugMode) return false;
  if (_devDemoDataDefine.trim().toLowerCase() == 'true') return true;
  if (dotenv.isInitialized) {
    return dotenv.maybeGet('DEV_DEMO_DATA')?.trim().toLowerCase() == 'true';
  }
  return false;
}

/// `on` force le tuto, `off` le desactive (debug uniquement).
String get devTutorialOverride {
  if (!kDebugMode) return '';
  final value = _devTutorialDefine.trim().isNotEmpty
      ? _devTutorialDefine.trim()
      : (dotenv.isInitialized
          ? (dotenv.maybeGet('DEV_TUTORIAL')?.trim() ?? '')
          : '');
  return tutorialOverrideFor(value);
}

String tutorialOverrideFor(String value) {
  switch (value.trim().toLowerCase()) {
    case 'on':
    case 'true':
    case '1':
      return 'on';
    case 'off':
    case 'false':
    case '0':
      return 'off';
  }
  return '';
}
const firebaseSetupGuideUrl = 'https://tilly.orceus.fr/tutoriels/firebase';
const helloAssoSetupGuideUrl = 'https://tilly.orceus.fr/tutoriels/helloasso';

const _defaultLicenseApiBaseUrl = kReleaseMode
    ? 'https://tilly.orceus.fr'
    : 'http://localhost:3000';

const _licenseApiUrlDefine = String.fromEnvironment('LICENSE_API_URL');

String get licenseApiBaseUrl => _resolveAndroidLocalhost(_configuredLicenseApiBaseUrl);

String get _configuredLicenseApiBaseUrl {
  final defined = _licenseApiUrlDefine.trim();
  if (defined.isNotEmpty) return defined;
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
const releasesLatestPath = '$licenseApiPath/releases/latest';

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