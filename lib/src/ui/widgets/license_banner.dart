import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../platform/backup_and_links.dart';
import '../../services/license/license_models.dart';
import '../../services/license/license_service.dart';
import '../theme.dart';

class LicenseBanner extends StatelessWidget {
  const LicenseBanner({
    required this.licenseService,
    required this.onReconnect,
    required this.onExport,
    super.key,
  });

  final LicenseService licenseService;
  final VoidCallback onReconnect;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final state = licenseService.currentState;
    if (state == LicenseState.versionNotCovered) {
      final covered = licenseService.coveredVersion;
      return _banner(
        context,
        icon: Icons.system_update,
        message: covered == null
            ? 'Cette version de Tilly n\'est pas couverte par votre licence à vie.'
            : 'Votre licence couvre Tilly jusqu\'à la version $covered. '
                'Cette version ($appBuildVersion) n\'est pas incluse.',
        actionLabel:
            covered == null ? 'Voir les versions' : 'Télécharger la version $covered',
        onAction: () => _openReleases(context),
      );
    }
    if (state != LicenseState.serverValidationRequired &&
        state != LicenseState.clockTampered) {
      return const SizedBox.shrink();
    }
    return _banner(
      context,
      icon: Icons.wifi_off,
      message: licenseService.getStateMessage(),
      actionLabel: 'Se connecter',
      onAction: onReconnect,
    );
  }

  Widget _banner(
    BuildContext context, {
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: AppColors.warn.withValues(alpha: 0.14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.warn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.warn,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Exporter mes données',
            onPressed: onExport,
            color: AppColors.warn,
            icon: const Icon(Icons.download),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warn,
              side: const BorderSide(color: AppColors.warn),
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _openReleases(BuildContext context) async {
    try {
      await openExternalUrl(githubReleasesUrl);
    } catch (_) {
      if (context.mounted) {
        snack(context, 'Impossible d\'ouvrir le navigateur.');
      }
    }
  }
}