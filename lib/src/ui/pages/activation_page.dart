import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../services/license/license_models.dart';
import '../../services/license/license_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class ActivationPage extends StatefulWidget {
  const ActivationPage({
    required this.licenseService,
    required this.controller,
    super.key,
  });

  final LicenseService licenseService;
  final AppController controller;

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  static const _welcomeImage =
      'assets/branding/expressions/tilli-welcome-transparent.png';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  var _isLoading = false;
  var _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = _initialMessage();
  }

  String? _initialMessage() {
    switch (widget.licenseService.currentState) {
      case LicenseState.noSubscription:
      case LicenseState.machineRevoked:
      case LicenseState.machineLimitReached:
      case LicenseState.licenseExpired:
      case LicenseState.invalidSignature:
      case LicenseState.invalidMachine:
      case LicenseState.versionNotCovered:
      case LicenseState.clockTampered:
        return widget.licenseService.getStateMessage();
      case LicenseState.licenseValid:
      case LicenseState.offlineGracePeriod:
      case LicenseState.serverValidationRequired:
      case LicenseState.noLicense:
        return null;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.maxHeight > 48 ? constraints.maxHeight - 48 : 0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        _welcomeImage,
                        height: 150,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.bolt,
                          size: 96,
                          color: context.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Connexion à votre compte Tilly',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: AppColors.muted),
                      ),
                      const SizedBox(height: 28),
                      if (_error != null) ...[
                        TacticalCard(
                          borderColor: AppColors.danger,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.danger),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style:
                                      const TextStyle(color: AppColors.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        onChanged: (_) => _clearError(),
                        onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Masquer le mot de passe'
                                : 'Afficher le mot de passe',
                            icon: Icon(_showPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        onChanged: (_) => _clearError(),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Se connecter',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'En vous connectant, vous acceptez les conditions d\'utilisation de Tilly.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(
          () => _error = 'Renseigne ton e-mail et ton mot de passe.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await widget.licenseService
          .loginAndActivate(email: email, password: password);
      if (result.state == LicenseState.licenseValid ||
          result.state == LicenseState.offlineGracePeriod) {
        if (context.mounted) {
          widget.controller.load();
        }
      } else {
        setState(() => _error = result.error ?? 'Connexion impossible.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}