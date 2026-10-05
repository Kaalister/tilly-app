import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'license_api.dart';
import 'license_models.dart';
import 'license_store.dart';
import 'license_verifier.dart';
import 'machine_id.dart';
import '../secure_settings_service.dart';
import '../../config/app_config.dart';

const _validationInterval = Duration(hours: 6);

class LicenseService extends ChangeNotifier {
  LicenseService({
    required SecureSettingsService secureStorage,
    LicenseApiClient? apiClient,
    LicenseVerifier? verifier,
    LicenseStore? store,
    MachineIdService? machineIdService,
  })  : _secureStorage = secureStorage,
        _apiClient = apiClient ?? LicenseApiClient(),
        _verifier = verifier ?? LicenseVerifier(),
        _store = store ?? LicenseStore(secureStorage),
        _machineIdService = machineIdService ?? MachineIdService(secureStorage);

  final SecureSettingsService _secureStorage;
  final LicenseApiClient _apiClient;
  final LicenseVerifier _verifier;
  final LicenseStore _store;
  final MachineIdService _machineIdService;

  LicenseState _currentState = LicenseState.noLicense;
  String? _authToken;
  String? _userEmail;
  String? _accountId;
  String? _coveredVersion;
  DateTime? _lastValidationAttempt;
  Timer? _backgroundTimer;

  LicenseState get currentState => _currentState;

  // Stable identifier of the licence account, used to scope the local dataset.
  String? get accountId => _accountId;

  // Version covered by a lifetime licence (null for subscriptions).
  String? get coveredVersion => _coveredVersion;
  String? get authToken => _authToken;
  String? get userEmail => _userEmail;
  bool get isLicensed => _currentState == LicenseState.licenseValid ||
      _currentState == LicenseState.offlineGracePeriod;
  bool get requiresOnlineValidation =>
      _currentState == LicenseState.serverValidationRequired ||
      _currentState == LicenseState.clockTampered;
  // The app stays visible but no longer accepts modifications: either the
  // licence must be revalidated online, or the installed version is not
  // covered by a lifetime licence.
  bool get isReadOnly =>
      requiresOnlineValidation ||
      _currentState == LicenseState.versionNotCovered;
  // Hard refusal: the device/licence cannot be used at all. Only logging out
  // (to switch account) remains possible.
  bool get isBlocked =>
      _currentState == LicenseState.machineRevoked ||
      _currentState == LicenseState.machineLimitReached ||
      _currentState == LicenseState.licenseExpired ||
      _currentState == LicenseState.invalidSignature ||
      _currentState == LicenseState.invalidMachine;

  Future<void> initialize() async {
    await _loadPersistedAuth();
    await _checkLicenseOffline();
    _startBackgroundValidation();
    // Check at every app opening (non-blocking): detects a revoked machine or
    // a reconnected subscription as soon as the app starts. The 6 h interval
    // only applies to the periodic timer while the app stays open.
    unawaited(_validateOnStartup());
  }

  Future<void> _validateOnStartup() async {
    if (_authToken == null) return;
    if (!isLicensed && !requiresOnlineValidation) return;
    try {
      _lastValidationAttempt = DateTime.now();
      await validateOnline();
    } catch (error) {
      if (!kReleaseMode) {
        debugPrint('Tilly license startup validation skipped: $error');
      }
    }
  }

  Future<void> _loadPersistedAuth() async {
    try {
      final token = await _secureStorage.read(key: 'tilly_license_auth_token');
      final email = await _secureStorage.read(key: 'tilly_license_user_email');
      _authToken = token?.isNotEmpty == true ? token : null;
      _userEmail = email?.isNotEmpty == true ? email : null;
    } catch (_) {}
  }

  Future<void> _persistAuth(String token, String email) async {
    _authToken = token;
    _userEmail = email;
    await _secureStorage.write(key: 'tilly_license_auth_token', value: token);
    await _secureStorage.write(key: 'tilly_license_user_email', value: email);
  }

  Future<void> _clearAuth() async {
    _authToken = null;
    _userEmail = null;
    await _secureStorage.delete(key: 'tilly_license_auth_token');
    await _secureStorage.delete(key: 'tilly_license_user_email');
  }

  Future<void> _checkLicenseOffline() async {
    final envelope = await _store.loadEnvelope();
    final stateData = await _store.loadState();
    final machineId = await _machineIdService.getOrCreateMachineId();
    final deviceSecret = await _store.getOrCreateDeviceSecret();

    if (envelope == null) {
      _currentState = LicenseState.noLicense;
      _accountId = null;
      _coveredVersion = null;
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final lastValidatedAt = stateData?.lastValidatedAt;
    final lastServerTime = stateData?.lastServerTime;

    if (stateData != null) {
      final hmacValid = await _store.verifyStateHmac(stateData, deviceSecret);
      if (!hmacValid) {
        _currentState = LicenseState.invalidSignature;
        notifyListeners();
        return;
      }
    }

    final state = await _verifier.verify(
      envelope: envelope,
      localMachineId: machineId,
      appVersion: appBuildVersion,
      now: now,
      lastServerTime: lastServerTime,
      lastValidatedAt: lastValidatedAt,
    );

    _currentState = state;
    // Metadata is only trusted when the envelope signature was valid
    // (invalidMachine still implies a valid signature).
    if (state != LicenseState.invalidSignature) {
      final payloadJson = _payloadFromEnvelope(envelope);
      final userId = payloadJson?['userId'];
      _accountId = userId is String && userId.trim().isNotEmpty
          ? userId.trim()
          : null;
      final covered = payloadJson?['coveredVersion'];
      _coveredVersion =
          covered is String && covered.trim().isNotEmpty ? covered.trim() : null;
    }
    notifyListeners();
  }

  Map<String, dynamic>? _payloadFromEnvelope(LicenseEnvelope envelope) {
    try {
      return jsonDecode(utf8.decode(base64UrlDecodeBytes(envelope.payload)))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeLicense(LicenseData licenseData, String machineId) async {
    await _store.saveEnvelope(licenseData.license);
    final stateData = await _store.signState(
      lastValidatedAt: DateTime.now(),
      lastServerTime: licenseData.machine.lastSeenAt,
      machineId: machineId,
      deviceSecret: await _store.getOrCreateDeviceSecret(),
    );
    await _store.saveState(stateData);
  }

  // Single activate call with the stored bearer token. Used for a device that
  // is unknown to the server (first activation). Never used to reactivate a
  // revoked device: the site is the only place allowed to do that.
  Future<({LicenseState state, String? error})> _activateWithToken() async {
    final token = _authToken;
    if (token == null) {
      return (state: LicenseState.noLicense, error: 'Non connecté');
    }
    try {
      final machineId = await _machineIdService.getOrCreateMachineId();
      final machineInfo = MachineInfo(
        machineId: machineId,
        platform: _getPlatformString(),
        appVersion: appBuildVersion,
        fingerprintHash: await _machineIdService.generateFingerprintHash(),
      );
      final licenseData =
          await _apiClient.activate(token: token, machineInfo: machineInfo);
      await _storeLicense(licenseData, machineId);
      await _checkLicenseOffline();
      return (state: _currentState, error: null);
    } on LicenseApiException catch (e) {
      _currentState = _mapApiErrorToState(e.state);
      notifyListeners();
      return (state: _currentState, error: e.message);
    }
  }

  Future<({LicenseState state, String? error})> loginAndActivate({
    required String email,
    required String password,
  }) async {
    try {
      final loginResult = await _apiClient.login(email: email, password: password);
      if (!loginResult.authenticated || loginResult.token == null) {
        return (state: LicenseState.noLicense, error: 'Connexion échouée');
      }

      await _persistAuth(loginResult.token!, email);

      final machineId = await _machineIdService.getOrCreateMachineId();
      final fingerprintHash = await _machineIdService.generateFingerprintHash();

      final machineInfo = MachineInfo(
        machineId: machineId,
        platform: _getPlatformString(),
        appVersion: appBuildVersion,
        fingerprintHash: fingerprintHash,
      );

      final licenseData = await _apiClient.activate(token: loginResult.token!, machineInfo: machineInfo);

      await _storeLicense(licenseData, machineId);

      await _checkLicenseOffline();
      return (state: _currentState, error: null);
    } on LicenseApiException catch (e) {
      if (!kReleaseMode) {
        debugPrint(
          'Tilly license login rejected: state=${e.state} message=${e.message}',
        );
      }
      _currentState = _mapApiErrorToState(e.state);
      notifyListeners();
      return (state: _currentState, error: e.message);
    } catch (error, stackTrace) {
      if (!kReleaseMode) {
        debugPrint('Tilly license login failed: $error');
        debugPrint('$stackTrace');
      }
      return (
        state: LicenseState.noLicense,
        error: 'Une erreur est survenue. Réessaie dans quelques instants.',
      );
    }
  }

  Future<({LicenseState state, String? error})> validateOnline() async {
    if (isBlocked) {
      // Terminal state: no retry, no network call.
      return (state: _currentState, error: null);
    }
    if (_authToken == null) {
      return (state: LicenseState.noLicense, error: 'Non connecté');
    }

    final machineId = await _machineIdService.getOrCreateMachineId();
    final machineInfo = MachineInfo(
      machineId: machineId,
      platform: _getPlatformString(),
      appVersion: appBuildVersion,
    );

    try {
      final licenseData = await _apiClient.validate(token: _authToken!, machineInfo: machineInfo);

      await _storeLicense(licenseData, machineId);

      await _checkLicenseOffline();
      return (state: _currentState, error: null);
    } on LicenseApiException catch (e) {
      if (e.state == 'MACHINE_NOT_ACTIVATED') {
        // Unknown device: a single activation is allowed (first activation).
        // Never a reactivation: a revoked device is refused upstream.
        return await _activateWithToken();
      }
      if (_isTransientState(e.state)) {
        // Keep the local state: a network hiccup must not lock the app out.
        return (state: _currentState, error: e.message);
      }
      _currentState = _mapApiErrorToState(e.state);
      notifyListeners();
      return (state: _currentState, error: e.message);
    } catch (e) {
      return (state: _currentState, error: null);
    }
  }

  bool _isTransientState(String state) {
    return state == 'network_error' ||
        state == 'server_error' ||
        state == 'unexpected' ||
        state == 'rate_limit_exceeded';
  }

  // Local logout only. The app never revokes a machine: deactivation is done
  // exclusively from the marketplace account page. The machine id is
  // identifier-stable and is never deleted.
  Future<void> logout() async {
    await _store.clearAll();
    await _clearAuth();
    _currentState = LicenseState.noLicense;
    _accountId = null;
    _coveredVersion = null;
    notifyListeners();
  }

  Future<void> refreshLicense() async {
    if (_authToken == null) return;
    final now = DateTime.now();
    if (_lastValidationAttempt != null &&
        now.difference(_lastValidationAttempt!) < _validationInterval) {
      return;
    }
    _lastValidationAttempt = now;
    await validateOnline();
  }

  void _startBackgroundValidation() {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(_validationInterval, (_) {
      if (isLicensed || requiresOnlineValidation) {
        refreshLicense();
      }
    });
  }

  @override
  void dispose() {
    _backgroundTimer?.cancel();
    _apiClient.dispose();
    super.dispose();
  }

  String _getPlatformString() {
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isWindows) return 'WINDOWS';
    if (Platform.isMacOS) return 'MACOS';
    if (Platform.isLinux) return 'LINUX';
    return 'UNKNOWN';
  }

  LicenseState _mapApiErrorToState(String state) {
    switch (state) {
      case 'NOT_FOUND':
        return LicenseState.noSubscription;
      case 'LICENSE_REVOKED':
        return LicenseState.licenseExpired;
      case 'LICENSE_SUSPENDED':
        return LicenseState.licenseExpired;
      case 'LICENSE_EXPIRED':
        return LicenseState.licenseExpired;
      case 'MACHINE_REVOKED':
        return LicenseState.machineRevoked;
      case 'MACHINE_LIMIT_REACHED':
        return LicenseState.machineLimitReached;
      case 'MACHINE_NOT_ACTIVATED':
        return LicenseState.invalidMachine;
      case 'VERSION_NOT_COVERED':
        return LicenseState.versionNotCovered;
      case 'email_not_verified':
        return LicenseState.noLicense;
      default:
        return LicenseState.noLicense;
    }
  }

  String getStateMessage() {
    switch (_currentState) {
      case LicenseState.licenseValid:
        return 'Tilly est activé';
      case LicenseState.offlineGracePeriod:
        return 'Mode hors ligne — Connexion requise bientôt';
      case LicenseState.serverValidationRequired:
        return 'Connexion Internet nécessaire pour vérifier votre licence';
      case LicenseState.clockTampered:
        return "L'horloge de votre appareil semble incorrecte";
      case LicenseState.machineRevoked:
        return "Cet appareil n'est plus autorisé";
      case LicenseState.machineLimitReached:
        return 'Trop d\'appareils pour cette licence';
      case LicenseState.licenseExpired:
        return 'Abonnement expiré';
      case LicenseState.noSubscription:
        return 'Aucun abonnement en cours trouvé';
      case LicenseState.versionNotCovered:
        final covered = _coveredVersion;
        return covered == null
            ? 'Cette version n\'est pas couverte par la licence'
            : 'Licence limitée à la version $covered';
      case LicenseState.invalidSignature:
      case LicenseState.invalidMachine:
      case LicenseState.noLicense:
        return 'Aucune licence active';
    }
  }
}