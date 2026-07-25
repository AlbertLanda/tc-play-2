import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../controllers/live_tv_player_controller.dart';
import '../services/live_tv_service.dart';
import '../../../core/constants/app_colors.dart';

class LivePlayer extends StatefulWidget {
  const LivePlayer({
    super.key,
    required this.streamId,
    required this.username,
    required this.password,
    required this.channelName,
    this.channelIcon,
    this.onFullscreen,
  });

  final int streamId;
  final String username;
  final String password;
  final String channelName;
  final String? channelIcon;
  final VoidCallback? onFullscreen;

  @override
  State<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<LivePlayer> {
  final LiveTvService _service = LiveTvService();
  late LiveTvPlayerController _tvController;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tvController = LiveTvPlayerController();
    _loadChannel();
  }

  @override
  void didUpdateWidget(covariant LivePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamId != widget.streamId) {
      _loadChannel();
    }
  }

  Future<void> _loadChannel() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final url = await _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );

      debugPrint("LIVE PLAYER URL: $url");

      await _tvController.initializePlayer(url);

    } catch (e) {
      debugPrint("ERROR OBTENIENDO URL: $e");
      _tvController.hasError = true;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_tvController.hasError) {
      return const Center(
        child: Text(
          'No se pudo reproducir el canal',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // El widget Video reemplaza a VideoPlayer y AspectRatio
          Video(
            controller: _tvController.videoController,
            controls: NoVideoControls, // Oculta los controles por defecto de MediaKit
          ),

          Positioned(
            left: 16,
            bottom: 16,
            child: Text(
              widget.channelName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Positioned(
            right: 8,
            bottom: 8,
            child: IconButton(
              onPressed: widget.onFullscreen,
              icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tvController.dispose();
    _service.stopProxy(streamId: widget.streamId);
    super.dispose();
  }
}