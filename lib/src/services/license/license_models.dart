import 'dart:convert';
import 'dart:typed_data';

enum LicenseType {
  lifetime,
  subscription,
}

enum LicenseState {
  licenseValid,
  licenseExpired,
  offlineGracePeriod,
  machineRevoked,
  invalidSignature,
  invalidMachine,
  noLicense,
  noSubscription,
  serverValidationRequired,
  clockTampered,
  machineLimitReached,
  versionNotCovered,
}

class LicensePayload {
  const LicensePayload({
    required this.version,
    required this.licenseId,
    required this.userId,
    required this.machineId,
    required this.product,
    required this.licenseType,
    required this.issuedAt,
    required this.serverTime,
    required this.licenseValidUntil,
    required this.offlineValidUntil,
    required this.features,
    this.coveredVersion,
  });

  final int version;
  final String licenseId;
  final String userId;
  final String machineId;
  final String product;
  final LicenseType licenseType;
  final String? coveredVersion;
  final DateTime issuedAt;
  final DateTime serverTime;
  final DateTime? licenseValidUntil;
  final DateTime? offlineValidUntil;
  final List<String> features;

  factory LicensePayload.fromJson(Map<String, dynamic> json) {
    final covered = json['coveredVersion'];
    return LicensePayload(
      version: json['version'] as int,
      licenseId: json['licenseId'] as String,
      userId: json['userId'] as String,
      machineId: json['machineId'] as String,
      product: json['product'] as String,
      licenseType: (json['licenseType'] as String) == 'LIFETIME'
          ? LicenseType.lifetime
          : LicenseType.subscription,
      coveredVersion: covered is String && covered.trim().isNotEmpty
          ? covered.trim()
          : null,
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      serverTime: DateTime.parse(json['serverTime'] as String),
      licenseValidUntil: json['licenseValidUntil'] != null
          ? DateTime.parse(json['licenseValidUntil'] as String)
          : null,
      offlineValidUntil: json['offlineValidUntil'] != null
          ? DateTime.parse(json['offlineValidUntil'] as String)
          : null,
      features: (json['features'] as List).map((e) => e as String).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'licenseId': licenseId,
      'userId': userId,
      'machineId': machineId,
      'product': product,
      'licenseType': licenseType == LicenseType.lifetime ? 'LIFETIME' : 'SUBSCRIPTION',
      'coveredVersion': coveredVersion,
      'issuedAt': issuedAt.toIso8601String(),
      'serverTime': serverTime.toIso8601String(),
      'licenseValidUntil': licenseValidUntil?.toIso8601String(),
      'offlineValidUntil': offlineValidUntil?.toIso8601String(),
      'features': features,
    };
  }
}

/// Lifetime licences cover the app up to [coveredVersion] (inclusive, patches
/// included: "2.1" covers 2.1.x). A null [coveredVersion] means a legacy
/// licence issued before version coverage existed: treated as covering.
bool versionIsCovered(String appVersion, String? coveredVersion) {
  final covered = _versionParts(coveredVersion);
  if (covered.isEmpty) return true;
  final app = _versionParts(appVersion);
  if (app.isEmpty) return true;
  for (var index = 0; index < covered.length; index++) {
    final appPart = index < app.length ? app[index] : 0;
    final coveredPart = covered[index];
    if (appPart != coveredPart) return appPart < coveredPart;
  }
  return true;
}

List<int> _versionParts(String? version) {
  if (version == null) return const [];
  final cleaned =
      version.trim().replaceFirst(RegExp(r'^[vV]'), '').split('-').first;
  if (cleaned.isEmpty) return const [];
  return [
    for (final part in cleaned.split('.'))
      int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
  ];
}

class LicenseEnvelope {
  const LicenseEnvelope({
    required this.kid,
    required this.payload,
    required this.signature,
    this.rawPayloadBytes,
  });

  final String kid;
  final String payload;
  final String signature;
  final Uint8List? rawPayloadBytes;

  factory LicenseEnvelope.fromJson(Map<String, dynamic> json) {
    return LicenseEnvelope(
      kid: json['kid'] as String,
      payload: json['payload'] as String,
      signature: json['signature'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kid': kid,
      'payload': payload,
      'signature': signature,
    };
  }
}

class LicenseMachine {
  const LicenseMachine({
    required this.machineId,
    required this.platform,
    required this.appVersion,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.name,
    this.revokedAt,
    this.revokedReason,
  });

  final String machineId;
  final String platform;
  final String appVersion;
  final String? name;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;
  final String? revokedReason;

  factory LicenseMachine.fromJson(Map<String, dynamic> json) {
    return LicenseMachine(
      machineId: json['machineId'] as String,
      platform: json['platform'] as String,
      appVersion: json['appVersion'] as String,
      name: json['name'] as String?,
      firstSeenAt: DateTime.parse(json['firstSeenAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      revokedAt: json['revokedAt'] != null
          ? DateTime.parse(json['revokedAt'] as String)
          : null,
      revokedReason: json['revokedReason'] as String?,
    );
  }
}

class LicenseData {
  const LicenseData({
    required this.granted,
    required this.state,
    required this.license,
    required this.machine,
  });

  final bool granted;
  final String state;
  final LicenseEnvelope license;
  final LicenseMachine machine;

  factory LicenseData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return LicenseData(
      granted: data['granted'] as bool,
      state: data['state'] as String,
      license: LicenseEnvelope.fromJson(data['license'] as Map<String, dynamic>),
      machine: LicenseMachine.fromJson(data['machine'] as Map<String, dynamic>),
    );
  }
}

class LicenseSubscriptionStatus {
  const LicenseSubscriptionStatus({
    required this.status,
    this.coveredVersion,
    this.validUntil,
  });

  final String status;
  final String? coveredVersion;
  final DateTime? validUntil;

  factory LicenseSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return LicenseSubscriptionStatus(
      status: json['status'] as String? ?? '',
      coveredVersion: json['coveredVersion'] as String?,
      validUntil: json['validUntil'] != null
          ? DateTime.tryParse('${json['validUntil']}')
          : null,
    );
  }
}

class LicenseLifetimeStatus {
  const LicenseLifetimeStatus({
    required this.status,
    this.coveredVersion,
  });

  final String status;
  final String? coveredVersion;

  factory LicenseLifetimeStatus.fromJson(Map<String, dynamic> json) {
    return LicenseLifetimeStatus(
      status: json['status'] as String? ?? '',
      coveredVersion: json['coveredVersion'] as String?,
    );
  }
}

class LicensePurchase {
  const LicensePurchase({
    required this.kind,
    this.coveredVersion,
    this.quantity = 1,
    this.orderRef,
    this.createdAt,
  });

  final String kind;
  final String? coveredVersion;
  final int quantity;
  final String? orderRef;
  final DateTime? createdAt;

  factory LicensePurchase.fromJson(Map<String, dynamic> json) {
    return LicensePurchase(
      kind: json['kind'] as String? ?? '',
      coveredVersion: json['coveredVersion'] as String?,
      quantity: (json['quantity'] as num?)?.round() ?? 1,
      orderRef: json['orderRef'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse('${json['createdAt']}')
          : null,
    );
  }
}

class LicenseStatus {
  const LicenseStatus({
    this.subscription,
    this.lifetime,
    this.machines = const [],
    this.maxMachines = 0,
    this.purchases = const [],
  });

  final LicenseSubscriptionStatus? subscription;
  final LicenseLifetimeStatus? lifetime;
  final List<LicenseMachine> machines;
  final int maxMachines;
  final List<LicensePurchase> purchases;

  factory LicenseStatus.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return LicenseStatus(
      subscription: data['subscription'] != null
          ? LicenseSubscriptionStatus.fromJson(
              data['subscription'] as Map<String, dynamic>)
          : null,
      lifetime: data['lifetime'] != null
          ? LicenseLifetimeStatus.fromJson(
              data['lifetime'] as Map<String, dynamic>)
          : null,
      machines: (data['machines'] as List? ?? [])
          .map((e) => LicenseMachine.fromJson(e as Map<String, dynamic>))
          .toList(),
      maxMachines: (data['maxMachines'] as num?)?.round() ?? 0,
      purchases: (data['purchases'] as List? ?? [])
          .map((e) => LicensePurchase.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LicenseError {
  const LicenseError({
    required this.type,
    required this.title,
    required this.status,
    required this.state,
    required this.detail,
  });

  final String type;
  final String title;
  final int status;
  final String state;
  final String detail;

  factory LicenseError.fromJson(Map<String, dynamic> json) {
    return LicenseError(
      type: json['type'] as String,
      title: json['title'] as String,
      status: json['status'] as int,
      state: json['state'] as String,
      detail: json['detail'] as String,
    );
  }
}

class MachineInfo {
  const MachineInfo({
    required this.machineId,
    required this.platform,
    required this.appVersion,
    this.fingerprintHash,
  });

  final String machineId;
  final String platform;
  final String appVersion;
  final String? fingerprintHash;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'machineId': machineId,
      'platform': platform,
      'appVersion': appVersion,
    };
    if (fingerprintHash != null) {
      map['fingerprintHash'] = fingerprintHash;
    }
    return map;
  }
}

String base64UrlDecode(String input) {
  var output = input.replaceAll('-', '+').replaceAll('_', '/');
  switch (output.length % 4) {
    case 0:
      break;
    case 2:
      output += '==';
      break;
    case 3:
      output += '=';
      break;
    default:
      throw FormatException('Invalid base64url string');
  }
  return utf8.decode(base64.decode(output));
}

Uint8List base64UrlDecodeBytes(String input) {
  var output = input.replaceAll('-', '+').replaceAll('_', '/');
  switch (output.length % 4) {
    case 0:
      break;
    case 2:
      output += '==';
      break;
    case 3:
      output += '=';
      break;
    default:
      throw FormatException('Invalid base64url string');
  }
  return Uint8List.fromList(base64.decode(output));
}

String base64UrlEncode(Uint8List bytes) {
  return base64Url.encode(bytes);
}