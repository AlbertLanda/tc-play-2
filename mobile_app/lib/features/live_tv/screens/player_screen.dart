import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../services/live_tv_service.dart';
import 'package:video_player/video_player.dart';

class PlayerScreen extends StatefulWidget {
  final String username;
  final String password;
  final int streamId;
  final String channelName;
  final String? channelIcon;

  const PlayerScreen({
    super.key,
    required this.username,
    required this.password,
    required this.streamId,
    required this.channelName,
    this.channelIcon,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final LiveTvService _service = LiveTvService();

  late Future<String> _streamUrl;

  VideoPlayerController? _videoController;

  bool _isInitializingPlayer = false;
  bool _playerError = false;

  @override
  void initState() {
    super.initState();

    _streamUrl = _service.getStreamUrl(
      username: widget.username,
      password: widget.password,
      streamId: widget.streamId,
    );
  }

  Future<void> _initializePlayer(String url) async {
    try {
      setState(() {
        _isInitializingPlayer = true;
        _playerError = false;
      });

      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(url),
      );

      await _videoController!.initialize();

      await _videoController!.play();

      if (mounted) {
        setState(() {
          _isInitializingPlayer = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _playerError = true;
          _isInitializingPlayer = false;

        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _streamUrl = _service.getStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );
    });

    await _streamUrl;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(widget.channelName),
        centerTitle: true,
      ),

      body: FutureBuilder<String>(
        future: _streamUrl,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.neonGreen,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 50,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudo obtener el stream.',
                      style: TextStyle(color: AppColors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            }

            final streamUrl = snapshot.data!;

            if (_videoController == null && !_isInitializingPlayer) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _initializePlayer(streamUrl);
              });
            }

            if (_isInitializingPlayer) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.neonGreen,
                ),
              );
            }

            if (_playerError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 50,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Error al reproducir el canal.',
                      style: TextStyle(color: AppColors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _initializePlayer(streamUrl);
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            }

            if (_videoController != null && 
                _videoController!.value.isInitialized) {
              return Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              );
            }

            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.neonGreen,
              ),
            );
        },
      ),
    );
  }
}