import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/license/license_service.dart';
import '../services/secure_settings_service.dart';
import '../ui/root_shell.dart';
import '../ui/theme.dart';

class TillyApp extends StatefulWidget {
  const TillyApp({super.key});

  @override
  State<TillyApp> createState() => _TillyAppState();
}

class _TillyAppState extends State<TillyApp> {
  final controller = AppController();
  final secureStorage = SecureSettingsService();
  late final LicenseService licenseService;
  late Color primaryColor;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    primaryColor = controller.primaryColor;
    controller.addListener(_updateTheme);
    licenseService = LicenseService(secureStorage: secureStorage)
      ..addListener(_applyAccountScope);
    _initializeLicense();
  }

  Future<void> _initializeLicense() async {
    await licenseService.initialize();
    await controller.switchDataScope(licenseService.accountId);
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  // Each licence account owns its local dataset: switching account switches
  // the SQLite file, so two associations never share their data.
  void _applyAccountScope() {
    controller.switchDataScope(licenseService.accountId);
  }

  @override
  void dispose() {
    controller
      ..removeListener(_updateTheme)
      ..dispose();
    licenseService
      ..removeListener(_applyAccountScope)
      ..dispose();
    super.dispose();
  }

  void _updateTheme() {
    if (controller.primaryColor.toARGB32() == primaryColor.toARGB32()) return;
    setState(() => primaryColor = controller.primaryColor);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tilly',
      theme: caisseTheme(primaryColor),
      home: _ready
          ? RootShell(controller: controller, licenseService: licenseService)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}