import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ad_slot.dart';
import '../../../core/widgets/bottom_nav.dart';

/// Pestaña "Video" (video bajo demanda) — placeholder listo para
/// conectar al catálogo real cuando el backend exponga el endpoint
/// correspondiente.
class VideoScreen extends StatelessWidget {
  const VideoScreen({
    super.key,
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Video'),
        centerTitle: true,
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        username: username,
        password: password,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 40),
        children: [
          const Icon(Icons.ondemand_video_rounded,
              color: AppColors.textSecondary, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Muy pronto',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Estamos preparando el contenido bajo demanda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 28),
          const AdSlot(label: 'AD_SLOT_VIDEO', height: 80),
        ],
      ),
    );
  }
}
