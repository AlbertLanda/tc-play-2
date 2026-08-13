// NOTA: este archivo usa dos paquetes adicionales:
//   url_launcher: ^6.3.0       (para abrir WhatsApp)
//   device_info_plus: ^10.0.0  (para reconocer el dispositivo actual)
// Si no están en el proyecto, agrégalos en pubspec.yaml y corre
// `flutter pub get`.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ad_slot.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/screens/login_screen.dart';
import '../../home/widgets/home_menu_card.dart';

/// Contacto de soporte de una sede, usado en "Método de pago" y
/// "Ayuda y soporte".
class _SupportContact {
  const _SupportContact({required this.label, required this.phoneNumber});

  final String label;
  final String phoneNumber; // Formato legible, ej: +51 987 360 334

  /// Número normalizado para wa.me (solo dígitos, sin '+', espacios ni guiones).
  String get whatsappNumber => phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Sedes y números de soporte.
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

/// Intenta reconocer el dispositivo actual (marca/modelo). Si falla,
/// devuelve un nombre genérico para no romper la pantalla.
Future<String> _currentDeviceLabel() async {
  try {
    final deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfoPlugin.androidInfo;
      final label = '${info.manufacturer} ${info.model}'.trim();
      return label.isNotEmpty ? label : 'Este dispositivo';
    } else if (Platform.isIOS) {
      final info = await deviceInfoPlugin.iosInfo;
      return info.name.isNotEmpty ? info.name : 'Este dispositivo';
    }
  } catch (_) {
    // Si no se puede leer la info del dispositivo, se usa el nombre genérico.
  }
  return 'Este dispositivo';
}

/// Ventana flotante de información simple (título + contenido + botón cerrar).
Future<void> _showInfoDialog(
  BuildContext context, {
  required String title,
  required Widget content,
  List<Widget>? actions,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: content,
      actions: actions ??
          [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cerrar',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
    ),
  );
}

/// Fila simple etiqueta/valor usada en "Mis datos".
class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opción dentro del diálogo de "Mi suscripción".
class _MenuOptionTile extends StatelessWidget {
  const _MenuOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de opción (sede / número) reutilizado dentro de [_ContactFlowDialog].
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flujo genérico de contacto por WhatsApp: (opcionalmente) describir el
/// problema -> elegir sede -> elegir número -> confirmar y enviar mensaje.
/// Se usa tanto en "Método de pago -> Más información" como en
/// "Ayuda y soporte".
class _ContactFlowDialog extends StatefulWidget {
  const _ContactFlowDialog({
    required this.title,
    required this.introText,
    required this.buildMessage,
    this.requireDescription = false,
    this.descriptionHint,
  });

  final String title;
  final String introText;
  final bool requireDescription;
  final String? descriptionHint;

  /// Construye el mensaje final a enviar. Recibe la descripción escrita
  /// por el usuario (null si [requireDescription] es false).
  final String Function(String? description) buildMessage;

  @override
  State<_ContactFlowDialog> createState() => _ContactFlowDialogState();
}

class _ContactFlowDialogState extends State<_ContactFlowDialog> {
  final TextEditingController _descriptionController =
      TextEditingController();

  String? _description;
  String? _selectedSede;
  _SupportContact? _selectedContact;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  List<_SupportContact> get _contactsForSelectedSede =>
      _kSupportSedes[_selectedSede] ?? const [];

  bool get _needsDescriptionStep =>
      widget.requireDescription && _description == null;
  bool get _showSedeStep => !_needsDescriptionStep && _selectedSede == null;
  bool get _showContactStep =>
      !_needsDescriptionStep && !_showSedeStep && _selectedContact == null;
  bool get _showMessageStep =>
      !_needsDescriptionStep && !_showSedeStep && !_showContactStep;

  bool get _canGoBack => _selectedSede != null || _description != null;

  void _confirmDescription() {
    final text = _descriptionController.text.trim();
    if (text.isEmpty) return;
    setState(() => _description = text);
  }

  void _selectSede(String sede) {
    final contacts = _kSupportSedes[sede] ?? const [];
    setState(() {
      _selectedSede = sede;
      _selectedContact = contacts.length == 1 ? contacts.first : null;
    });
  }

  void _selectContact(_SupportContact contact) {
    setState(() => _selectedContact = contact);
  }

  void _goBack() {
    setState(() {
      if (_selectedContact != null && _contactsForSelectedSede.length > 1) {
        _selectedContact = null;
      } else if (_selectedSede != null) {
        _selectedSede = null;
        _selectedContact = null;
      } else if (widget.requireDescription) {
        _description = null;
      }
    });
  }

  Future<void> _sendWhatsappMessage() async {
    final contact = _selectedContact;
    if (contact == null) return;

    final message = widget.buildMessage(_description);
    final encodedMessage = Uri.encodeComponent(message);
    final uri = Uri.parse(
      'https://wa.me/${contact.whatsappNumber}?text=$encodedMessage',
    );

    final navigator = Navigator.of(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched) {
      if (!mounted) return;
      await _showInfoDialog(
        context,
        title: 'No se pudo abrir WhatsApp',
        content: const Text(
          'Verifica que WhatsApp esté instalado en tu dispositivo e '
          'inténtalo nuevamente.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
      return;
    }

    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 380,
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
                if (_canGoBack)
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
                    widget.title,
                    style: const TextStyle(
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
            if (_needsDescriptionStep) ..._buildDescriptionStep(),
            if (_showSedeStep) ..._buildSedeOptions(),
            if (_showContactStep) ..._buildContactOptions(),
            if (_showMessageStep) ..._buildMessageStep(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDescriptionStep() {
    return [
      Text(
        widget.introText,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _descriptionController,
        maxLines: 4,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: widget.descriptionHint ?? 'Describe brevemente tu caso...',
          hintStyle: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: .6),
            fontSize: 13,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .05),
          contentPadding: const EdgeInsets.all(14),
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
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
          ),
        ),
      ),
      const SizedBox(height: 18),
      PrimaryButton(
        text: 'Continuar',
        onPressed: _confirmDescription,
      ),
    ];
  }

  List<Widget> _buildSedeOptions() {
    return [
      Text(
        'Selecciona la sede a la que perteneces para contactar a soporte.',
        style: const TextStyle(
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
        style: const TextStyle(
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
    final message = widget.buildMessage(_description);
    return [
      Text(
        'Se enviará este mensaje por WhatsApp a soporte de $_selectedSede '
        '(${contact.phoneNumber}):',
        style: const TextStyle(
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
          message,
          style: const TextStyle(
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

  void _showMyData(BuildContext context) {
    _showInfoDialog(
      context,
      title: 'Mis datos',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DataRow(label: 'Usuario', value: username),
          const _DataRow(
            label: 'Estado de la cuenta',
            value: 'Activo',
            valueColor: AppColors.primary,
          ),
          const _DataRow(label: 'Expiraciones activas', value: 'Ilimitado'),
          const _DataRow(label: 'Conexiones máximas', value: '1'),
        ],
      ),
    );
  }

  void _showPlanInfo(BuildContext context) {
    _showInfoDialog(
      context,
      title: 'Plan actual',
      content: const Text(
        'Tu plan actual cuenta con disponibilidad a todos los canales '
        'incluidos en tu suscripción de TC Play.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }

  void _showPaymentInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Método de pago',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Puedes realizar tus pagos mediante:',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '• Yape',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '• Efectivo en la oficina de tu sede',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              showDialog<void>(
                context: context,
                builder: (_) => _ContactFlowDialog(
                  title: 'Más información',
                  introText: 'Selecciona la sede a la que perteneces para '
                      'contactar a soporte.',
                  buildMessage: (_) => 'Hola, soy el usuario $username, '
                      'requiero información sobre el proceso de pagos.',
                ),
              );
            },
            child: const Text(
              'Más información',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSubscription(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Mi suscripción',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuOptionTile(
              icon: Icons.workspace_premium_outlined,
              label: 'Plan actual',
              onTap: () {
                Navigator.pop(dialogContext);
                _showPlanInfo(context);
              },
            ),
            const SizedBox(height: 10),
            _MenuOptionTile(
              icon: Icons.payments_outlined,
              label: 'Método de pago',
              onTap: () {
                Navigator.pop(dialogContext);
                _showPaymentInfo(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showLinkedDevices(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Dispositivos vinculados',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: FutureBuilder<String>(
          future: _currentDeviceLabel(),
          builder: (context, snapshot) {
            final deviceName = snapshot.data ?? 'Cargando dispositivo...';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.smartphone_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceName,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Este dispositivo · Conectado',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Tu cuenta permite 1 dispositivo vinculado como máximo.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpSupport(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _ContactFlowDialog(
        title: 'Ayuda y soporte',
        introText:
            'Cuéntanos qué problema tienes para poder ayudarte mejor.',
        requireDescription: true,
        descriptionHint: 'Describe brevemente el problema o consulta que tienes...',
        buildMessage: (description) => 'Hola, soy el usuario $username. '
            'Requiero soporte con lo siguiente: $description',
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
                  onTap: () => _showMyData(context),
                ),
                const SizedBox(height: 12),
                HomeMenuCard(
                  title: 'Mi suscripción',
                  subtitle: 'Plan actual y método de pago',
                  icon: Icons.workspace_premium_outlined,
                  iconColor: AppColors.liveRed,
                  onTap: () => _showSubscription(context),
                ),
                const SizedBox(height: 12),
                HomeMenuCard(
                  title: 'Dispositivos vinculados',
                  subtitle: 'Administra dónde ves TC Play',
                  icon: Icons.devices_rounded,
                  iconColor: AppColors.accent,
                  onTap: () => _showLinkedDevices(context),
                ),
                const SizedBox(height: 12),
                HomeMenuCard(
                  title: 'Ayuda y soporte',
                  subtitle: 'Preguntas frecuentes y contacto',
                  icon: Icons.help_outline_rounded,
                  iconColor: AppColors.orange,
                  onTap: () => _showHelpSupport(context),
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