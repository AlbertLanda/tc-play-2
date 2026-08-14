import 'package:flutter/material.dart';

import '../../../core/device/device_profile_service.dart';
import '../../auth/screens/login_screen.dart';
import 'device_setup_screen.dart';

class DeviceBootScreen extends StatefulWidget {
  const DeviceBootScreen({super.key});

  @override
  State<DeviceBootScreen> createState() => _DeviceBootScreenState();
}

class _DeviceBootScreenState extends State<DeviceBootScreen> {
  @override
  void initState() {
    super.initState();
    _resolveDeviceProfile();
  }

  Future<void> _resolveDeviceProfile() async {
    final profile = await DeviceProfileService.getSavedProfile();

    if (!mounted) return;

    final Widget destination;

    if (profile == null) {
      destination = const DeviceSetupScreen();
    } else {
      destination = const LoginScreen();
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => destination,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF070B18),
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}