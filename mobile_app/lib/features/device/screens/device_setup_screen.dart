import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/device/device_profile.dart';
import '../../../core/device/device_profile_service.dart';
import '../../auth/screens/login_screen.dart';

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  DeviceProfile _selectedProfile = DeviceProfile.tv;
  bool _saving = false;

  Future<void> _continue() async {
    if (_saving) return;

    setState(() => _saving = true);

    await DeviceProfileService.saveProfile(_selectedProfile);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  Widget _buildOption({
    required DeviceProfile profile,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedProfile == profile;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () {
          setState(() => _selectedProfile = profile);
        },
        borderRadius: BorderRadius.circular(18),
        focusColor: AppColors.primary.withValues(alpha: .25),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: .18)
                : AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: .10),
              width: selected ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 42,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 30,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 760,
              ),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/tc_play_logo.png',
                    height: 90,
                  ),
                  const SizedBox(height: 30),

                  const Text(
                    'Configura TC Play',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),

                  const Text(
                    'Selecciona cómo deseas utilizar TC Play en este dispositivo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 32),

                  _buildOption(
                    profile: DeviceProfile.tv,
                    icon: Icons.tv_rounded,
                    title: 'Televisor',
                    subtitle:
                        'Interfaz optimizada para control remoto y pantalla grande.',
                  ),

                  const SizedBox(height: 16),

                  _buildOption(
                    profile: DeviceProfile.mobile,
                    icon: Icons.smartphone_rounded,
                    title: 'Celular o tablet',
                    subtitle:
                        'Interfaz táctil optimizada para dispositivos móviles.',
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _continue,
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'CONTINUAR',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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