import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/device/device_profile.dart';
import '../../../core/device/device_profile_service.dart';
import '../../auth/screens/login_screen.dart';
import '../../tv/constants/tv_colors.dart';

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
    required bool isTv,
  }) {
    final selected = _selectedProfile == profile;

    // Esta pantalla es compartida con el celular: la variante negra
    // (igual al isotipo) es exclusiva de pantallas grandes tipo TV,
    // controlada por [isTv]. El celular sigue usando AppColors sin
    // ningún cambio.
    final cardColor = isTv ? TvColors.card : AppColors.card;
    final accentColor = isTv ? TvColors.primary : AppColors.primary;
    final textPrimary = isTv ? TvColors.textPrimary : AppColors.textPrimary;
    final textSecondary =
        isTv ? TvColors.textSecondary : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        autofocus: isTv && profile == DeviceProfile.tv,
        onTap: () {
          setState(() => _selectedProfile = profile);
        },
        borderRadius: BorderRadius.circular(18),
        focusColor: accentColor.withValues(alpha: .25),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(isTv ? 28 : 22),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: .18)
                : cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? accentColor
                  : Colors.white.withValues(alpha: .10),
              width: selected ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: isTv ? 50 : 42,
                color: selected ? accentColor : textSecondary,
              ),
              SizedBox(width: isTv ? 22 : 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: isTv ? 24 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: isTv ? 16 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: accentColor,
                  size: isTv ? 34 : 30,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Detección simple por ancho: un celular o tablet no llega a
    // 900dp de ancho lógico, una TV sí. Así esta misma pantalla
    // (usada también en el primer arranque, antes de saber en qué
    // dispositivo está la app) se ve como TV cuando corresponde, sin
    // tocar en nada la experiencia en celular.
    final isTv = MediaQuery.of(context).size.width >= 900;

    final backgroundColor =
        isTv ? TvColors.background : AppColors.background;
    final textPrimary = isTv ? TvColors.textPrimary : AppColors.textPrimary;
    final textSecondary =
        isTv ? TvColors.textSecondary : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isTv ? 1000 : 760,
              ),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/tc_play_logo.png',
                    height: isTv ? 130 : 90,
                  ),
                  SizedBox(height: isTv ? 36 : 30),

                  Text(
                    'Configura TC Play',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: isTv ? 36 : 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Text(
                    'Selecciona cómo deseas utilizar TC Play en este dispositivo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: isTv ? 18 : 16,
                    ),
                  ),

                  SizedBox(height: isTv ? 40 : 32),

                  _buildOption(
                    profile: DeviceProfile.tv,
                    icon: Icons.tv_rounded,
                    title: 'Televisor',
                    subtitle:
                        'Interfaz optimizada para control remoto y pantalla grande.',
                    isTv: isTv,
                  ),

                  SizedBox(height: isTv ? 18 : 16),

                  _buildOption(
                    profile: DeviceProfile.mobile,
                    icon: Icons.smartphone_rounded,
                    title: 'Celular o tablet',
                    subtitle:
                        'Interfaz táctil optimizada para dispositivos móviles.',
                    isTv: isTv,
                  ),

                  SizedBox(height: isTv ? 40 : 32),

                  SizedBox(
                    width: double.infinity,
                    height: isTv ? 64 : 58,
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
                          : Text(
                              'CONTINUAR',
                              style: TextStyle(
                                fontSize: isTv ? 18 : 16,
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
