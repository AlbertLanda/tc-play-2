import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Ventana flotante de bienvenida que aparece sobre el contenido
/// justo después de iniciar sesión y desaparece automáticamente
/// pasados unos segundos (fade-in + fade-out).
class WelcomeBanner extends StatefulWidget {
  final String message;
  final VoidCallback onFinished;
  final Duration visibleDuration;

  const WelcomeBanner({
    super.key,
    required this.message,
    required this.onFinished,
    this.visibleDuration = const Duration(seconds: 2),
  });

  @override
  State<WelcomeBanner> createState() => _WelcomeBannerState();
}

class _WelcomeBannerState extends State<WelcomeBanner> {
  bool _visible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Pequeño retraso para que el fade-in se aprecie desde 0.
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _visible = true);
    });

    _hideTimer = Timer(widget.visibleDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onFadeAnimationEnd() {
    // Solo se retira del Overlay cuando terminó el fade-out.
    if (!_visible) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 20,
      right: 20,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            onEnd: _onFadeAnimationEnd,
            child: AnimatedSlide(
              offset: _visible ? Offset.zero : const Offset(0, -0.25),
              duration: const Duration(milliseconds: 350),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.green,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: AppColors.title,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}