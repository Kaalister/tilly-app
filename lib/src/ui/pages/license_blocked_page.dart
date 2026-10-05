import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../platform/backup_and_links.dart';
import '../../services/license/license_models.dart';
import '../../services/license/license_service.dart';
import '../theme.dart';

class LicenseBlockedPage extends StatelessWidget {
  const LicenseBlockedPage({required this.licenseService, super.key});

  final LicenseService licenseService;

  bool get _offersAccountLink =>
      licenseService.currentState == LicenseState.machineRevoked ||
      licenseService.currentState == LicenseState.machineLimitReached;

  String get _explanation {
    switch (licenseService.currentState) {
      case LicenseState.machineRevoked:
        return 'Cet appareil a été désactivé. Réactivez-le depuis votre compte '
            'Tilly, dans « Mes appareils ».';
      case LicenseState.machineLimitReached:
        return 'Trop d\'appareils sont associés à cette licence. Gérez vos '
            'appareils depuis votre compte Tilly.';
      default:
        return 'Déconnecte-toi pour utiliser un autre compte. Les données de '
            'l’association restent sur cet appareil.';
    }
  }

  Future<void> _openAccount(BuildContext context) async {
    try {
      await openExternalUrl(licenseAccountUrl);
    } catch (_) {
      if (context.mounted) {
        snack(context,
            'Impossible d\'ouvrir le navigateur. Va sur tilly.orceus.fr/compte.');
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await confirm(
      context,
      'Se déconnecter de ce compte ? Tu pourras te reconnecter avec un autre compte.',
    );
    if (!confirmed || !context.mounted) return;
    await licenseService.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/expressions/tiko-locked.png',
                    height: 150,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.lock_outline,
                      size: 96,
                      color: context.primaryAccent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    licenseService.getStateMessage(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _explanation,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  if (_offersAccountLink) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () => _openAccount(context),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text(
                          'Ouvrir mon compte',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout),
                      label: const Text('Se déconnecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}