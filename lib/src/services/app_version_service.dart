import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';

Future<void> initializeAppVersion() async {
  if (compiledAppVersion.trim().isNotEmpty) return;
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    if (version.isNotEmpty) {
      appBuildVersion = version;
    }
  } catch (_) {
    // Le binaire reste sur la version compilee par defaut.
  }
}
