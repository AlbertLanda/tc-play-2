import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/screens/login_screen.dart';
import '../../live_tv/screens/categories_screen.dart';
import '../../live_tv/services/live_tv_service.dart';
import '../../live_tv/screens/player_screen.dart';
import '../widgets/home_menu_card.dart';
import '../widgets/welcome_banner.dart';

class HomeScreen extends StatefulWidget {
  final String username;

  const HomeScreen({super.key, required this.username});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LiveTvService _liveTvService = LiveTvService();
  late Future<List<String>> _categoriesFuture;

  // 0 = Home (menú de opciones), 1 = Cuenta.
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _liveTvService.getCategories();

    // Muestra la ventana flotante de bienvenida apenas se construye
    // la pantalla (justo después del login) y se retira sola.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWelcomeBanner());
  }

  void _showWelcomeBanner() {
    final overlayState = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => WelcomeBanner(
        message: 'BIENVENIDO ${widget.username.toUpperCase()} A TC PLAY 2.0',
        onFinished: () => entry.remove(),
      ),
    );
    overlayState.insert(entry);
  }

  // ---------------------------------------------------------------------
  // Navegación: SIN CAMBIOS en la conexión con el backend, solo se
  // reutiliza CategoriesScreen (que consume LiveTvService) como destino
  // de "TV en vivo", "Canales" y "Categorías".
  // ---------------------------------------------------------------------
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

  // ---------------------------------------------------------------------
  // Pestaña Home: al pulsar el ícono de casita se muestra este submenú
  // con las 4 opciones solicitadas.
  // ---------------------------------------------------------------------
  Widget _buildHomeTab(bool isWide) {
    final options = <Widget>[
      HomeMenuCard(
        title: 'TV en vivo',
        subtitle: 'Mira la señal en vivo de tus canales favoritos.',
        icon: Icons.live_tv_rounded,
        iconColor: AppColors.orange,
        onTap: _goToCategories,
      ),
      HomeMenuCard(
        title: 'Canales',
        subtitle: 'Explora todos los canales disponibles.',
        icon: Icons.tv_rounded,
        iconColor: Colors.purpleAccent,
        // TODO(backend): reemplazar por ChannelsScreen cuando exista la
        // pantalla dedicada a canales; por ahora reutiliza CategoriesScreen.
        onTap: _goToCategories,
      ),
      HomeMenuCard(
        title: 'Categorías',
        subtitle: 'Elige entre todas las categorías disponibles.',
        icon: Icons.category_rounded,
        iconColor: AppColors.green,
        onTap: _goToCategories,
        trailingBadge: _buildCategoryBadge(),
      ),
      HomeMenuCard(
        title: 'Mi cuenta',
        subtitle: 'Administra tu información de usuario.',
        icon: Icons.person_outline_rounded,
        iconColor: Colors.blueAccent,
        onTap: () => setState(() => _selectedIndex = 1),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hola, ${widget.username}',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '¿Qué quieres ver hoy?',
            style: TextStyle(color: AppColors.white70),
          ),
          const SizedBox(height: 24),
          isWide
              ? GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 3.2,
                  children: options,
                )
              : Column(
                  children: options
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
    );
  }

  // ---------------------------------------------------------------------
  // Pestaña Cuenta
  // ---------------------------------------------------------------------
  Widget _buildAccountTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Container(
          padding: const EdgeInsets.all(28),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.blueAccent,
                  size: 42,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.username,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cuenta de TC Play 2.0',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Función disponible próximamente'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar información'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: AppColors.white,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Barra inferior de navegación por íconos: Home, Cuenta, Salir.
  // ---------------------------------------------------------------------
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final color = isSelected ? AppColors.orange : AppColors.white70;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(AppColors.background, Colors.black, 0.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _buildNavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              isSelected: _selectedIndex == 0,
              onTap: () => setState(() => _selectedIndex = 0),
            ),
            _buildNavItem(
              icon: Icons.person_rounded,
              label: 'Cuenta',
              isSelected: _selectedIndex == 1,
              onTap: () => setState(() => _selectedIndex = 1),
            ),
            _buildNavItem(
              icon: Icons.logout_rounded,
              label: 'Salir',
              isSelected: false,
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 700;
    final horizontalPadding = width < 500 ? 16.0 : (isWide ? 60.0 : 40.0);

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
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildHomeTab(isWide),
                _buildAccountTab(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }
}