import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'license_models.dart';

const _requestTimeout = Duration(seconds: 15);
const _networkErrorMessage =
    'Impossible de joindre le serveur. Vérifie ta connexion Internet.';
const _serverErrorMessage =
    'Le serveur est momentanément indisponible. Réessaie dans quelques instants.';
const _unexpectedErrorMessage =
    'Une erreur est survenue. Réessaie dans quelques instants.';
const _sessionExpiredMessage = 'Session expirée. Reconnecte-toi.';

typedef LicenseLoginResult = ({
  bool authenticated,
  String? userId,
  String? email,
  String? token,
  DateTime? expiresAt,
});

class LicenseApiClient {
  LicenseApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers({String? token}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      licenseClientHeader: licenseClientValue,
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on LicenseApiException catch (error) {
      if (!kReleaseMode) {
        debugPrint(
          'Tilly license api error: state=${error.state} '
          'status=${error.statusCode} message=${error.message}',
        );
      }
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      _logFailure('timeout', error, stackTrace);
      throw const LicenseApiException(_networkErrorMessage,
          state: 'network_error');
    } on SocketException catch (error, stackTrace) {
      _logFailure('socket', error, stackTrace);
      throw const LicenseApiException(_networkErrorMessage,
          state: 'network_error');
    } on http.ClientException catch (error, stackTrace) {
      _logFailure('client', error, stackTrace);
      throw const LicenseApiException(_networkErrorMessage,
          state: 'network_error');
    } catch (error, stackTrace) {
      _logFailure('unexpected', error, stackTrace);
      throw const LicenseApiException(_unexpectedErrorMessage,
          state: 'unexpected');
    }
  }

  void _logFailure(String kind, Object error, StackTrace stackTrace) {
    if (kReleaseMode) return;
    debugPrint('Tilly license ($kind): $error');
    debugPrint('$stackTrace');
  }

  Future<LicenseLoginResult> login({
    required String email,
    required String password,
  }) {
    return _request(() async {
      final response = await _client
          .post(
            Uri.parse('$licenseApiBaseUrl$licenseAuthLoginPath'),
            headers: _headers(),
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (
          authenticated: json['authenticated'] as bool? ?? false,
          userId: json['user']?['id'] as String?,
          email: json['user']?['email'] as String?,
          token: json['token'] as String?,
          expiresAt: json['expiresAt'] != null
              ? DateTime.tryParse('${json['expiresAt']}')
              : null,
        );
      }

      switch (response.statusCode) {
        case 401:
          throw const LicenseApiException(
            'E-mail ou mot de passe incorrect.',
            state: 'invalid_credentials',
          );
        case 403:
          if (_errorState(response) == 'email_not_verified') {
            throw const LicenseApiException(
              'Vérifie ton adresse e-mail sur le site tilly.orceus.fr.',
              state: 'email_not_verified',
            );
          }
          throw const LicenseApiException(
            'Accès refusé. Vérifie ton compte sur tilly.orceus.fr.',
            state: 'forbidden',
          );
        case 422:
          throw const LicenseApiException(
            'Vérifie les informations saisies.',
            state: 'validation_error',
          );
        case 429:
          throw const LicenseApiException(
            'Trop de tentatives. Réessaie dans quelques minutes.',
            state: 'rate_limit_exceeded',
          );
      }
      if (response.statusCode >= 500) {
        throw const LicenseApiException(_serverErrorMessage,
            state: 'server_error');
      }
      throw const LicenseApiException(_unexpectedErrorMessage,
          state: 'unexpected');
    });
  }

  Future<bool> checkSession({required String token}) {
    return _request(() async {
      final response = await _client
          .post(
            Uri.parse('$licenseApiBaseUrl$licenseAuthSessionPath'),
            headers: _headers(token: token),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['authenticated'] as bool? ?? false;
      }
      return false;
    });
  }

  Future<void> logout({required String token}) {
    return _request(() async {
      await _client
          .post(
            Uri.parse('$licenseApiBaseUrl$licenseAuthLogoutPath'),
            headers: _headers(token: token),
          )
          .timeout(_requestTimeout);
    });
  }

  Future<LicenseData> activate({
    required String token,
    required MachineInfo machineInfo,
  }) {
    return _request(() async {
      final response = await _client
          .post(
            Uri.parse('$licenseApiBaseUrl$licenseActivatePath'),
            headers: _headers(token: token),
            body: jsonEncode(machineInfo.toJson()),
          )
          .timeout(_requestTimeout);

      return _licenseDataFromResponse(response);
    });
  }

  Future<LicenseData> validate({
    required String token,
    required MachineInfo machineInfo,
  }) {
    return _request(() async {
      final response = await _client
          .post(
            Uri.parse('$licenseApiBaseUrl$licenseValidatePath'),
            headers: _headers(token: token),
            body: jsonEncode(machineInfo.toJson()),
          )
          .timeout(_requestTimeout);

      return _licenseDataFromResponse(response);
    });
  }

  Future<LicenseStatus> status({required String token}) {
    return _request(() async {
      final response = await _client
          .get(
            Uri.parse('$licenseApiBaseUrl$licenseStatusPath'),
            headers: _headers(token: token),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        return LicenseStatus.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      if (response.statusCode == 401) {
        throw const LicenseApiException(_sessionExpiredMessage,
            state: 'unauthorized');
      }
      throw _licenseErrorFromResponse(response);
    });
  }

  LicenseData _licenseDataFromResponse(http.Response response) {
    if (response.statusCode == 200) {
      return LicenseData.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    if (response.statusCode == 401) {
      throw const LicenseApiException(_sessionExpiredMessage,
          state: 'unauthorized');
    }
    throw _licenseErrorFromResponse(response);
  }

  String _errorState(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final state = json['state'] as String?;
      if (state != null && state.isNotEmpty) return state;
      return json['type'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  LicenseApiException _licenseErrorFromResponse(http.Response response) {
    final state = _errorState(response);
    return LicenseApiException(
      _messageForState(state, response.statusCode),
      state: state.isEmpty ? 'unknown' : state,
      statusCode: response.statusCode,
    );
  }

  String _messageForState(String state, int statusCode) {
    switch (state) {
      case 'NOT_FOUND':
        return 'Aucun abonnement en cours trouvé. '
            'Vérifie ton compte sur tilly.orceus.fr.';
      case 'LICENSE_REVOKED':
        return 'Cette licence a été révoquée.';
      case 'LICENSE_SUSPENDED':
        return 'Cette licence est suspendue.';
      case 'LICENSE_EXPIRED':
        return 'Ton abonnement a expiré.';
      case 'MACHINE_REVOKED':
        return 'Cet appareil n\'est plus autorisé.';
      case 'MACHINE_LIMIT_REACHED':
        return 'Trop d\'appareils sont associés à cette licence.';
      case 'MACHINE_NOT_ACTIVATED':
        return 'Cet appareil doit être activé.';
      case 'VERSION_NOT_COVERED':
        return 'Cette version de Tilly n\'est pas couverte par ta licence à vie.';
      case 'unauthorized':
        return _sessionExpiredMessage;
      case 'rate_limit_exceeded':
        return 'Trop de tentatives. Réessaie dans quelques minutes.';
      case 'validation_error':
        return 'Vérifie les informations saisies.';
    }
    if (statusCode == 422) return 'Vérifie les informations saisies.';
    if (statusCode == 429) {
      return 'Trop de tentatives. Réessaie dans quelques minutes.';
    }
    if (statusCode >= 500) return _serverErrorMessage;
    return _unexpectedErrorMessage;
  }

  void dispose() {
    _client.close();
  }
}

class LicenseApiException implements Exception {
  const LicenseApiException(this.message, {required this.state, this.statusCode});

  final String message;
  final String state;
  final int? statusCode;

  @override
  String toString() => 'LicenseApiException: $message (state: $state)';
}