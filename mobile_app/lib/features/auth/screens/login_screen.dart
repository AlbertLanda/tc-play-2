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

  final FocusNode _passwordFocusNode = FocusNode();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  double _keyboardOffset = 0;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // ---------------------------------------------------------------------
  void _updateKeyboardOffset(bool keyboardVisible) {
    if (!mounted) return;

    setState(() {
      _keyboardOffset = keyboardVisible ? 90 : 0;
    });
  }

  Future<void> _login() async {

    if (_isLoading) return;
    
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
          content: const Text('Por favor, ingresa tu usuario y contraseña para continuar.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

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
              showWelcomeMessage: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      final errorMessage = e.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          content: Text(
            errorMessage.toLowerCase().contains('usuario') ||
                    errorMessage.toLowerCase().contains('contraseña') ||
                    errorMessage.toLowerCase().contains('credenciales')
                ? 'Usuario o contraseña incorrectos. Verifica tus datos e inténtalo nuevamente.'
                : errorMessage,
          ),
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
      hintStyle: GoogleFonts.manrope(
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
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.accent,
          width: 1.4,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Texto "TC PLAY 2.0" — Manrope sólido, sin degradado ni resplandor
  // ---------------------------------------------------------------------
  Widget _buildBrandmark() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TC PLAY 2.0',
          style: GoogleFonts.manrope(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tu entretenimiento, siempre contigo.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: .18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .5),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AppLogo(size: 84)),

          const SizedBox(height: 24),

          Text(
            'Bienvenido a TC Play',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Inicia sesión para disfrutar de televisión en vivo y contenido exclusivo.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Usuario',
            style: GoogleFonts.manrope(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          
          TextField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,

            onSubmitted: (_) {
              FocusScope.of(context).requestFocus(_passwordFocusNode);
            },

            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 15,
            ),

            decoration: _fieldDecoration(
              hint: 'Tu usuario',
              icon: Icons.alternate_email_rounded,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            'Contraseña',
            style: GoogleFonts.manrope(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          
          TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,

            textInputAction: TextInputAction.done,

            onSubmitted: (_) => _login(),

            obscureText: _obscurePassword,

            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 15,
            ),

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
                      activeColor: AppColors.accent,
                      checkColor: AppColors.textPrimary,
                      side: BorderSide(
                        color: AppColors.textSecondary.withValues(alpha: .5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recordarme',
                    style: GoogleFonts.manrope(
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
                child: Text(
                  '¿Olvidaste tu contraseña?',
                  style: GoogleFonts.manrope(
                    color: AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 26),

          PrimaryButton(
            text: 'Iniciar sesión',
            loading: _isLoading,
            onPressed: _login,
          ),

          if (_isLoading) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Iniciando sesión...',
                style: GoogleFonts.manrope(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],

          const SizedBox(height: 30),

          Center(child: _buildBrandmark()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateKeyboardOffset(keyboardVisible);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Imagen de fondo a pantalla completa, sin oscurecer de más
          Image.asset(
            'assets/images/login_background.png',
            fit: BoxFit.cover,
          ),

          // Degradado: la imagen se ve arriba, se oscurece hacia el centro
          // donde está el formulario, para mantener legibilidad. Se tiñe
          // levemente de azul marino (en vez de negro puro) para que el
          // fondo se funda con la paleta de marca.
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: .15),
                    AppColors.background.withValues(alpha: .45),
                    AppColors.background.withValues(alpha: .8),
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

                return AnimatedPadding(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 40,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 250),
                        offset: Offset(
                          0,
                          -_keyboardOffset / 500,
                        ),
                        child: Center(
                          child: _buildFormCard(cardWidth),
                        ),
                      )
                    ),
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
