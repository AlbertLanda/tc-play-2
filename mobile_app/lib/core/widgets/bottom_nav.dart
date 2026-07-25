import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/live_tv/screens/live_tv_home_screen.dart';

/// Barra inferior compartida por las 4 pantallas principales
/// (Inicio / TV en Vivo / Películas / Video), igual que en las capturas
/// de referencia. Cada pantalla la instancia con su propio [currentIndex]
/// y la navegación entre pestañas se resuelve aquí con
/// [Navigator.pushReplacement] para no apilar pantallas.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.username,
    required this.password,
  });

  final int currentIndex;
  final String username;
  final String password;

  static const _items = [
  BottomNavigationBarItem(
    icon: Icon(Icons.home_rounded),
    label: 'Inicio',
  ),
  BottomNavigationBarItem(
    icon: Icon(Icons.live_tv_rounded),
    label: 'TV en Vivo',
  ),
];

  void _onTap(BuildContext context, int index) {
  if (index == currentIndex) return;

  late final Widget target;

  switch (index) {
    case 0:
      target = HomeScreen(
        username: username,
        password: password,
      );
      break;

    case 1:
      target = LiveTvHomeScreen(
        username: username,
        password: password,
      );
      break;

    default:
      return;
  }

  Navigator.pushReplacement(
    context,
    PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => target,
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) => _onTap(context, index),
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.liveRed,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      elevation: 0,
      items: _items,
    );
  }
}
