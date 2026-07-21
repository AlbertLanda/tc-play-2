import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../home/screens/home_screen.dart';
import '../services/auth_service.dart';

import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // ---------------------------------------------------------------------
  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          content: const Text('Ingrese su usuario y contraseña.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _authService.login(
        username: username,
        password: password,
      );

      if (!mounted) return;

      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              username: username,
              password: password,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------
  // ---------------------------------------------------------------------

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.textSecondary.withValues(alpha: .6),
        fontSize: 15,
      ),
      prefixIcon: Icon(
        icon,
        color: AppColors.textSecondary,
        size: 20,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: .05),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: 1.4,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Texto "TC PLAY 2.0" con tipografía distintiva + degradado neon
  // ---------------------------------------------------------------------
  Widget _buildBrandmark() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [AppColors.accent, AppColors.primary],
      ).createShader(bounds),
      child: Text(
        'TC PLAY 2.0',
        style: GoogleFonts.orbitron(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 4,
          shadows: [
            Shadow(
              color: AppColors.primary.withValues(alpha: .6),
              blurRadius: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(double cardWidth) {
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: 32,
        vertical: 40,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: .2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .6),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AppLogo(size: 84)),

          const SizedBox(height: 32),

          const Text(
            'USUARIO',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: _fieldDecoration(
              hint: 'Tu usuario',
              icon: Icons.alternate_email_rounded,
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'CONTRASEÑA',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: _fieldDecoration(
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),

          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                      activeColor: AppColors.primary,
                      checkColor: Colors.black,
                      side: BorderSide(
                        color: AppColors.textSecondary.withValues(alpha: .5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Recordarme',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {},
                child: const Text(
                  '¿Olvidaste tu contraseña?',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 26),

          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: .4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: PrimaryButton(
              text: 'Iniciar sesión',
              loading: _isLoading,
              onPressed: _login,
            ),
          ),

          const SizedBox(height: 30),

          Center(child: _buildBrandmark()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Imagen de fondo a pantalla completa, sin oscurecer de más
          Image.asset(
            'assets/images/login_background.png',
            fit: BoxFit.cover,
          ),

          // Degradado: la imagen se ve arriba, se oscurece hacia el centro
          // donde está el formulario, para mantener legibilidad
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .15),
                    Colors.black.withValues(alpha: .35),
                    Colors.black.withValues(alpha: .55),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 700
                    ? 420.0
                    : constraints.maxWidth * 0.9;

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: _buildFormCard(cardWidth),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}