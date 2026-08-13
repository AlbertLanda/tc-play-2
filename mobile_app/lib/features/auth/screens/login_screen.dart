// NOTA: este archivo usa el paquete `url_launcher` para abrir WhatsApp.
// Si aún no está en el proyecto, agrégalo en pubspec.yaml:
//   url_launcher: ^6.3.0
// y ejecuta `flutter pub get`.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/tv_utils.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/primary_button.dart';
import '../../home/screens/home_screen.dart';
import '../services/auth_service.dart';

/// Contacto de soporte de una sede, usado en la recuperación de contraseña.
class _SupportContact {
  const _SupportContact({required this.label, required this.phoneNumber});

  final String label;
  final String phoneNumber; // Formato legible, ej: +51 987 360 334

  /// Número normalizado para wa.me (solo dígitos, sin '+', espacios ni guiones).
  String get whatsappNumber => phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Sedes y números de soporte para recuperación de contraseña.
const Map<String, List<_SupportContact>> _kSupportSedes = {
  'Jauja': [
    _SupportContact(label: 'Teléfono fijo', phoneNumber: '+51 64 466080'),
    _SupportContact(label: 'Celular', phoneNumber: '+51 987 360 334'),
  ],
  'La Oroya': [
    _SupportContact(label: 'Celular', phoneNumber: '+51 970 870 534'),
  ],
  'Huancayo': [
    _SupportContact(label: 'Celular', phoneNumber: '+51 914 108 027'),
  ],
};

/// Mensaje predefinido que se envía por WhatsApp a soporte.
const String _kRecoveryMessage =
    'Hola, he olvide mi contraseña del aplicativo TC PLAY, solicito me '
    'brinde el apoyo necesario para recuperar mi contraseña';

/// Muestra un mensaje como ventana flotante (Dialog), reemplazando los
/// SnackBars para dar una mejor experiencia visual al usuario.
Future<void> _showFloatingMessage(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.info_outline_rounded,
  Color? iconColor,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: .18),
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
          children: [
            Icon(icon, color: iconColor ?? AppColors.accent, size: 36),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                text: 'Entendido',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Botón de opción usado dentro del flujo de recuperación de contraseña.
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTv = TvUtils.isTv(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        focusColor: AppColors.accent.withValues(alpha: .18),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: isTv ? 18 : 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child: Row(
            children: [
              Icon(icon, size: isTv ? 22 : 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    color: AppColors.textPrimary,
                    fontSize: isTv ? 16 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: isTv ? 22 : 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ventana flotante con el flujo de recuperación de contraseña:
/// 1) elegir sede, 2) elegir número (si hay más de uno), 3) enviar mensaje
/// predefinido por WhatsApp al número elegido.
class _RecoverPasswordDialog extends StatefulWidget {
  const _RecoverPasswordDialog();

  @override
  State<_RecoverPasswordDialog> createState() =>
      _RecoverPasswordDialogState();
}

class _RecoverPasswordDialogState extends State<_RecoverPasswordDialog> {
  String? _selectedSede;
  _SupportContact? _selectedContact;

  List<_SupportContact> get _contactsForSelectedSede =>
      _kSupportSedes[_selectedSede] ?? const [];

  void _selectSede(String sede) {
    final contacts = _kSupportSedes[sede] ?? const [];
    setState(() {
      _selectedSede = sede;
      // Si la sede tiene un único número, se selecciona automáticamente
      // y se pasa directo al paso del mensaje.
      _selectedContact = contacts.length == 1 ? contacts.first : null;
    });
  }

  void _selectContact(_SupportContact contact) {
    setState(() {
      _selectedContact = contact;
    });
  }

  void _goBack() {
    setState(() {
      if (_selectedContact != null && _contactsForSelectedSede.length > 1) {
        _selectedContact = null;
      } else {
        _selectedSede = null;
        _selectedContact = null;
      }
    });
  }

  Future<void> _sendWhatsappMessage() async {
    final contact = _selectedContact;
    if (contact == null) return;

    final encodedMessage = Uri.encodeComponent(_kRecoveryMessage);
    final uri = Uri.parse(
      'https://wa.me/${contact.whatsappNumber}?text=$encodedMessage',
    );

    final navigator = Navigator.of(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched) {
      if (!mounted) return;
      await _showFloatingMessage(
        context,
        title: 'No se pudo abrir WhatsApp',
        message:
            'Verifica que WhatsApp esté instalado en tu dispositivo e '
            'inténtalo nuevamente.',
        icon: Icons.error_outline_rounded,
        iconColor: Colors.redAccent,
      );
      return;
    }

    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final showSedeStep = _selectedSede == null;
    final showContactStep = !showSedeStep && _selectedContact == null;
    final showMessageStep = _selectedContact != null;

    final isTv = TvUtils.isTv(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: isTv ? 480 : 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: .18),
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
            Row(
              children: [
                if (_selectedSede != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: _goBack,
                      borderRadius: BorderRadius.circular(20),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    showSedeStep
                        ? 'Recuperar contraseña'
                        : showContactStep
                            ? 'Selecciona un número'
                            : 'Enviar solicitud',
                    style: GoogleFonts.manrope(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(20),
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (showSedeStep) ..._buildSedeOptions(),
            if (showContactStep) ..._buildContactOptions(),
            if (showMessageStep) ..._buildMessageStep(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSedeOptions() {
    return [
      Text(
        'Selecciona la sede a la que perteneces para contactar a soporte.',
        style: GoogleFonts.manrope(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 16),
      ..._kSupportSedes.keys.map(
        (sede) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _OptionButton(
            label: sede,
            icon: Icons.location_on_outlined,
            onTap: () => _selectSede(sede),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildContactOptions() {
    return [
      Text(
        'Sede $_selectedSede: elige el número al que deseas escribir.',
        style: GoogleFonts.manrope(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 16),
      ..._contactsForSelectedSede.map(
        (contact) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _OptionButton(
            label: '${contact.label} · ${contact.phoneNumber}',
            icon: Icons.call_outlined,
            onTap: () => _selectContact(contact),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildMessageStep() {
    final contact = _selectedContact!;
    return [
      Text(
        'Se enviará este mensaje por WhatsApp a soporte de $_selectedSede '
        '(${contact.phoneNumber}):',
        style: GoogleFonts.manrope(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Text(
          _kRecoveryMessage,
          style: GoogleFonts.manrope(
            color: AppColors.textPrimary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
      ),
      const SizedBox(height: 20),
      PrimaryButton(
        text: 'Enviar mensaje',
        onPressed: _sendWhatsappMessage,
      ),
    ];
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _rememberMeKey = 'remember_me';
  static const String _rememberedUsernameKey = 'remembered_username';

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _passwordFocusNode = FocusNode();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  double _keyboardOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadRememberedUser();
  }

  Future<void> _loadRememberedUser() async {
    try {
      final preferences = await SharedPreferences.getInstance();

      final rememberMe = preferences.getBool(_rememberMeKey) ?? false;
      final rememberedUsername =
          preferences.getString(_rememberedUsernameKey) ?? '';

      if (!mounted) return;

      if (rememberMe && rememberedUsername.isNotEmpty) {
        setState(() {
          _rememberMe = true;
          _usernameController.text = rememberedUsername;
        });
      }
    } catch (_) {
      // Si falla la lectura local, el login continúa funcionando normalmente.
    }
  }

  // Por seguridad, la contraseña NUNCA se guarda en el dispositivo.
  // "Recordarme" solo precarga el usuario en el siguiente inicio de sesión.
  Future<void> _saveRememberedUser(String username) async {
    try {
      final preferences = await SharedPreferences.getInstance();

      if (_rememberMe) {
        await preferences.setBool(_rememberMeKey, true);
        await preferences.setString(
          _rememberedUsernameKey,
          username,
        );
      } else {
        await preferences.setBool(_rememberMeKey, false);
        await preferences.remove(_rememberedUsernameKey);
      }
    } catch (_) {
      // La persistencia local no debe impedir un login exitoso.
    }
  }

  Future<void> _clearRememberedUser() async {
    try {
      final preferences = await SharedPreferences.getInstance();

      await preferences.setBool(_rememberMeKey, false);
      await preferences.remove(_rememberedUsernameKey);
    } catch (_) {
      // No interrumpir la interacción si falla el almacenamiento local.
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

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
      await _showFloatingMessage(
        context,
        title: 'Datos incompletos',
        message: 'Por favor, ingresa tu usuario y contraseña para continuar.',
        icon: Icons.info_outline_rounded,
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
        // Guardamos solamente el usuario.
        // La contraseña nunca se almacena localmente.
        await _saveRememberedUser(username);

        if (!mounted) return;

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

      final errorMessage = e.toString().replaceFirst(
            'Exception: ',
            '',
          );

      final normalizedError = errorMessage.toLowerCase();

      final isCredentialsError = normalizedError.contains('usuario') ||
          normalizedError.contains('contraseña') ||
          normalizedError.contains('credenciales');

      await _showFloatingMessage(
        context,
        title: 'No se pudo iniciar sesión',
        message: isCredentialsError
            ? 'Usuario o contraseña incorrectos. '
                'Verifica tus datos e inténtalo nuevamente.'
            : errorMessage,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    bool isTv = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.manrope(
        color: AppColors.textSecondary.withValues(alpha: .6),
        fontSize: isTv ? 17 : 15,
      ),
      prefixIcon: Icon(
        icon,
        color: AppColors.textSecondary,
        size: isTv ? 24 : 20,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: .05),
      contentPadding: EdgeInsets.symmetric(
        horizontal: isTv ? 22 : 18,
        vertical: isTv ? 20 : 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: .12),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: .12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: AppColors.accent,
          width: isTv ? 2.4 : 1.4,
        ),
      ),
    );
  }

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
    final isTv = TvUtils.isTv(context);

    return Container(
      width: cardWidth,
      padding: EdgeInsets.symmetric(
        horizontal: isTv ? 44 : 32,
        vertical: isTv ? 48 : 40,
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
          Center(
            child: AppLogo(size: isTv ? 108 : 84),
          ),

          const SizedBox(height: 24),

          Text(
            'Bienvenido a TC Play',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppColors.textPrimary,
              fontSize: isTv ? 28 : 24,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Inicia sesión para disfrutar de televisión en vivo '
            'y contenido exclusivo.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppColors.textSecondary,
              fontSize: isTv ? 16 : 14,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Usuario',
            style: GoogleFonts.manrope(
              color: AppColors.textPrimary,
              fontSize: isTv ? 15 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          TextField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            autofocus: isTv,
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: isTv ? 17 : 15,
            ),
            onSubmitted: (_) {
              FocusScope.of(context).requestFocus(
                _passwordFocusNode,
              );
            },
            decoration: _fieldDecoration(
              hint: 'Tu usuario',
              icon: Icons.alternate_email_rounded,
              isTv: isTv,
            ),
          ),

          SizedBox(height: isTv ? 22 : 18),

          Text(
            'Contraseña',
            style: GoogleFonts.manrope(
              color: AppColors.textPrimary,
              fontSize: isTv ? 15 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            textInputAction: TextInputAction.done,
            obscureText: _obscurePassword,
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: isTv ? 17 : 15,
            ),
            onSubmitted: (_) => _login(),
            decoration: _fieldDecoration(
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              isTv: isTv,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.textSecondary,
                  size: isTv ? 24 : 20,
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

          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: isTv ? 26 : 20,
                    height: isTv ? 26 : 20,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (value) async {
                        final newValue = value ?? false;

                        setState(() {
                          _rememberMe = newValue;
                        });

                        if (!newValue) {
                          await _clearRememberedUser();
                        }
                      },
                      activeColor: AppColors.accent,
                      checkColor: AppColors.textPrimary,
                      side: BorderSide(
                        color: AppColors.textSecondary.withValues(
                          alpha: .5,
                        ),
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
                      fontSize: isTv ? 15 : 13,
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
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: true,
                    builder: (context) => const _RecoverPasswordDialog(),
                  );
                },
                child: Text(
                  '¿Olvidaste tu contraseña?',
                  style: GoogleFonts.manrope(
                    color: AppColors.accent,
                    fontSize: isTv ? 15 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Nota explícita: por seguridad, solo se guarda el usuario.
          const SizedBox(height: 6),
          Text(
            'Por tu seguridad, solo guardamos tu usuario. '
            'La contraseña nunca se almacena en este dispositivo.',
            style: GoogleFonts.manrope(
              color: AppColors.textSecondary.withValues(alpha: .7),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20),

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

          Center(
            child: _buildBrandmark(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible =
        MediaQuery.of(context).viewInsets.bottom > 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateKeyboardOffset(keyboardVisible);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_background.png',
            fit: BoxFit.cover,
          ),

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
                final isTv = TvUtils.isTvWidth(constraints.maxWidth);
                final cardWidth = isTv
                    ? 560.0
                    : (constraints.maxWidth >= 700
                        ? 420.0
                        : constraints.maxWidth * 0.9);

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
                      ),
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