import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ad_slot.dart';
import '../../auth/screens/login_screen.dart';
import '../../home/widgets/home_menu_card.dart';

/// Pantalla "Mi cuenta" — accesible desde el ícono de perfil de la
/// barra superior del Home. Agrupa las opciones típicas de cuenta y
/// el botón de cerrar sesión.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: const Text('Función disponible próximamente'),
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cerrar sesión',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '¿Seguro que deseas cerrar sesión?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Cerrar sesión',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Mi cuenta'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: .4)),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.primary, size: 40),
                ),
                const SizedBox(height: 12),
                Text(
                  username,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Cuenta activa',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                HomeMenuCard(
                  title: 'Mis datos',
                  subtitle: 'Editar información personal',
                  icon: Icons.badge_outlined,
                  iconColor: AppColors.primary,
                  onTap: () => _comingSoon(context),
                ),
                const SizedBox(height: 12),
                HomeMenuCard(
                  title: 'Mi suscripción',
                  subtitle: 'Plan actual y método de pago',
                  icon: Icons.workspace_premium_outlined,
                  iconColor: AppColors.liveRed,
                  onTap: () => _comingSoon(context),
                ),
                const SizedBox(height: 12),
                HomeMenuCard(
                  title: 'Dispositivos vinculados',
                  subtitle: 'Administra dónde ves TC Play',
                  icon: Icons.devices_rounded,
                  iconColor: AppColors.accent,
                  onTap: () => _comingSoon(context),
                ),
                const SizedBox(height: 12),
                HomeMenuCard(
                  title: 'Ayuda y soporte',
                  subtitle: 'Preguntas frecuentes y contacto',
                  icon: Icons.help_outline_rounded,
                  iconColor: AppColors.orange,
                  onTap: () => _comingSoon(context),
                ),
                const SizedBox(height: 12),
                HomeMenuCard(
                  title: 'Cerrar sesión',
                  subtitle: 'Salir de la aplicación',
                  icon: Icons.logout_rounded,
                  iconColor: AppColors.error,
                  onTap: () => _logout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const AdSlot(label: 'AD_SLOT_ACCOUNT', height: 80),
        ],
      ),
    );
  }
}
