import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/screens/login_screen.dart';
import '../../live_tv/screens/categories_screen.dart';
import '../widgets/home_menu_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 500 ? 16.0 : 40.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('TC Play 2.0'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 70,
                  ),
                  SizedBox(height: 15),
                  Text(
                    '¡Bienvenido a TC Play 2.0!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Selecciona una opción para comenzar.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            HomeMenuCard(
              title: 'TV en vivo',
              subtitle: 'Explora los canales disponibles.',
              icon: Icons.live_tv,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CategoriesScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 15),

            HomeMenuCard(
              title: 'Categorías',
              subtitle: 'Explora las categorías disponibles.',
              icon: Icons.category,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CategoriesScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 15),

            HomeMenuCard(
              title: 'Mi cuenta',
              subtitle: 'Administrar información del usuario.',
              icon: Icons.person_outline,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Función disponible próximamente'),
                  ),
                );
              },
            ),

            const SizedBox(height: 15),

            HomeMenuCard(
              title: 'Cerrar sesión',
              subtitle: 'Salir de la aplicación.',
              icon: Icons.logout,
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}