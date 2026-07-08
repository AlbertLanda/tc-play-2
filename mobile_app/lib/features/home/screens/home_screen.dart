import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/screens/login_screen.dart';
import '../../live_tv/screens/categories_screen.dart';
import '../../live_tv/services/live_tv_service.dart';
import '../widgets/home_menu_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LiveTvService _liveTvService = LiveTvService();
  late Future<List<String>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _liveTvService.getCategories();
  }

  void _goToCategories() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesScreen()),
    );
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // Contador visual de categorías disponibles, mostrado como badge
  // sobre la tarjeta "Categorías".
  Widget _buildCategoryBadge() {
    return FutureBuilder<List<String>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final count = snapshot.data!.length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.green,
              size: 44,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '¡Bienvenido a TC Play 2.0!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Selecciona una opción para comenzar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 700;
    final horizontalPadding = width < 500 ? 16.0 : (isWide ? 60.0 : 40.0);

    final menuItems = <Widget>[
      HomeMenuCard(
        title: 'TV en vivo',
        subtitle: 'Explora los canales disponibles.',
        icon: Icons.live_tv_rounded,
        iconColor: AppColors.orange,
        onTap: _goToCategories,
      ),
      HomeMenuCard(
        title: 'Categorías',
        subtitle: 'Explora las categorías disponibles.',
        icon: Icons.category_rounded,
        iconColor: AppColors.green,
        onTap: _goToCategories,
        trailingBadge: _buildCategoryBadge(),
      ),
      HomeMenuCard(
        title: 'Mi cuenta',
        subtitle: 'Administrar información del usuario.',
        icon: Icons.person_outline_rounded,
        iconColor: Colors.blueAccent,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Función disponible próximamente'),
            ),
          );
        },
      ),
      HomeMenuCard(
        title: 'Cerrar sesión',
        subtitle: 'Salir de la aplicación.',
        icon: Icons.logout_rounded,
        iconColor: Colors.redAccent,
        onTap: _logout,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'TC Play 2.0',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background,
              Color.lerp(AppColors.background, Colors.black, 0.4) ??
                  AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWelcomeCard(),
                const SizedBox(height: 28),
                // Layout responsive: grid en pantallas anchas,
                // lista vertical en pantallas pequeñas.
                isWide
                    ? GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 3.2,
                        children: menuItems,
                      )
                    : Column(
                        children: menuItems
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 15),
                                child: item,
                              ),
                            )
                            .toList(),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
